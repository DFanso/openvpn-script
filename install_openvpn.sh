#!/bin/bash

# OpenVPN installation script
# Run this script as root or with sudo privileges

# Exit on any error
set -e

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root or with sudo privileges."
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "Cannot detect OS. Please ensure you're running a supported Linux distribution."
        exit 1
    fi
}

# Function to install dependencies based on OS
install_dependencies() {
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y openvpn easy-rsa net-tools
            ;;
        centos|rhel|fedora)
            yum update -y
            yum install -y epel-release
            yum install -y openvpn easy-rsa net-tools
            ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Function to set up PKI infrastructure
setup_pki() {
    # Create PKI directory
    mkdir -p /etc/openvpn/easy-rsa
    cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/
    cd /etc/openvpn/easy-rsa

    # Initialize PKI
    ./easyrsa init-pki
    
    # Create vars file
    cat > vars << EOF
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "California"
set_var EASYRSA_REQ_CITY       "San Francisco"
set_var EASYRSA_REQ_ORG        "OpenVPN-CA"
set_var EASYRSA_REQ_EMAIL      "admin@example.com"
set_var EASYRSA_REQ_OU         "Community"
EOF

    # Build CA (non-interactive)
    echo -en "\n" | ./easyrsa build-ca nopass
    
    # Generate server certificate and key
    echo -en "\n" | ./easyrsa gen-req server nopass
    echo -en "yes\n" | ./easyrsa sign-req server server
    
    # Generate Diffie-Hellman parameters
    ./easyrsa gen-dh
    
    # Generate TLS authentication key
    openvpn --genkey secret ta.key
}

# Function to configure OpenVPN server
configure_server() {
    # Create necessary directories
    mkdir -p /etc/openvpn
    
    # Copy certificates and keys directly to /etc/openvpn
    cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/
    cp /etc/openvpn/easy-rsa/pki/issued/server.crt /etc/openvpn/
    cp /etc/openvpn/easy-rsa/pki/private/server.key /etc/openvpn/
    cp /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/
    cp /etc/openvpn/easy-rsa/ta.key /etc/openvpn/

    # Set proper permissions
    chmod 600 /etc/openvpn/server.key
    chmod 644 /etc/openvpn/*.crt /etc/openvpn/*.pem /etc/openvpn/ta.key

    # Create server configuration file
    cat > /etc/openvpn/server.conf << EOF
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
EOF

    # Create the client configuration directory
    mkdir -p /etc/openvpn/client-configs
    chmod 700 /etc/openvpn/client-configs
}

# Function to enable IP forwarding
enable_ip_forwarding() {
    echo 1 > /proc/sys/net/ipv4/ip_forward
    # Make IP forwarding persistent
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-openvpn.conf
    sysctl -p
}

# Function to configure firewall rules
configure_firewall() {
    # Detect default network interface
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}')
    
    # Configure iptables
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $DEFAULT_INTERFACE -j MASQUERADE
    iptables -A INPUT -i tun+ -j ACCEPT
    iptables -A FORWARD -i tun+ -j ACCEPT
    iptables -A FORWARD -i tun+ -o $DEFAULT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i $DEFAULT_INTERFACE -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Make iptables rules persistent
    case $OS in
        ubuntu|debian)
            apt-get install -y iptables-persistent
            netfilter-persistent save
            ;;
        centos|rhel|fedora)
            service iptables save
            ;;
    esac
}

# Function to start and enable OpenVPN service
start_openvpn() {
    # Ensure proper permissions for OpenVPN configuration
    chmod 750 /etc/openvpn
    chown -R root:root /etc/openvpn

    # Enable and start the OpenVPN service
    systemctl enable openvpn@server
    systemctl start openvpn@server
    
    echo "Waiting for OpenVPN to start..."
    sleep 5
    
    # Check OpenVPN status
    if systemctl is-active --quiet openvpn@server; then
        echo "OpenVPN server is running successfully!"
    else
        echo "OpenVPN server failed to start. Checking logs..."
        journalctl -xeu openvpn@server.service
        exit 1
    fi
}

# Function to create initial client config template
create_client_config() {
    mkdir -p /etc/openvpn/client-configs/files
    
    # Create base client configuration
    # Get the server's public IPv4 address
    SERVER_IP=$(curl -s -4 ifconfig.me || wget -qO- -4 ifconfig.me || dig +short myip.opendns.com @resolver1.opendns.com)
    
    # If we couldn't get IPv4, try to get IPv6
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -s -6 ifconfig.me || wget -qO- -6 ifconfig.me)
    fi
    
    if [ -z "$SERVER_IP" ]; then
        echo "Warning: Could not automatically detect server IP address"
        SERVER_IP="YOUR_SERVER_IP"
    fi
    
    echo "Detected Server IP: $SERVER_IP"
    
    cat > /etc/openvpn/client-configs/base.conf << EOF
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
EOF
}

# Main installation process
main() {
    echo "Starting OpenVPN installation..."
    check_root
    detect_os
    install_dependencies
    setup_pki
    configure_server
    enable_ip_forwarding
    configure_firewall
    create_client_config
    start_openvpn
    
    # Final status message
    IP=$(curl -s ifconfig.me || wget -qO- ifconfig.me)
    echo "OpenVPN installation completed successfully!"
    echo "Server IP: $IP"
    echo "Configuration files are located in /etc/openvpn/"
    echo "Client configuration template is at /etc/openvpn/client-configs/base.conf"
    echo "Remember to:"
    echo "1. Update the client config template with your server's IP address"
    echo "2. Generate client certificates using the easy-rsa tools in /etc/openvpn/easy-rsa"
    echo "3. Distribute client configurations securely to your users"
}

# Run the installation
main