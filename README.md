# OpenVPN Server Setup and Configuration Guide

## Table of Contents
1. Server Installation
2. Managing Client Certificates
3. Client Configuration
4. Troubleshooting
5. Security Considerations
6. Maintenance

## 1. Server Installation

### Prerequisites
- Ubuntu/Debian based system
- Root access or sudo privileges
- Internet connectivity

### Installation Steps
1. Download the installation script:
```bash
wget https://raw.githubusercontent.com/dfanso/openvpn-script/main/install_openvpn.sh
```

2. Make the script executable:
```bash
chmod +x install_openvpn.sh
```

3. Run the installation script:
```bash
./install_openvpn.sh
```

The script will automatically:
- Install required packages
- Configure PKI infrastructure
- Set up server certificates
- Configure networking and firewall rules
- Start the OpenVPN service

## 2. Managing Client Certificates

### Creating a New Client Certificate
1. Navigate to the Easy-RSA directory:
```bash
cd /etc/openvpn/easy-rsa/
```

2. Generate a new client certificate:
```bash
./easyrsa gen-req CLIENT_NAME nopass
./easyrsa sign-req client CLIENT_NAME
```
Replace CLIENT_NAME with your desired client name.

### Revoking Client Certificates
1. To revoke a certificate:
```bash
cd /etc/openvpn/easy-rsa/
./easyrsa revoke CLIENT_NAME
./easyrsa gen-crl
```

2. Copy the new CRL to OpenVPN directory:
```bash
cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/
```

## 3. Client Configuration

### Creating Client Configuration Files
1. Generate the client configuration:
replace the ```CLIENT_NAME```
```bash
mkdir -p /etc/openvpn/client-configs/files
cat /etc/openvpn/client-configs/base.conf \
    <(echo -e '<ca>') \
    /etc/openvpn/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    /etc/openvpn/easy-rsa/pki/issued/CLIENT_NAME.crt \
    <(echo -e '</cert>\n<key>') \
    /etc/openvpn/easy-rsa/pki/private/CLIENT_NAME.key \
    <(echo -e '</key>\n<tls-auth>') \
    /etc/openvpn/ta.key \
    <(echo -e '</tls-auth>') \
    > /etc/openvpn/client-configs/files/CLIENT_NAME.ovpn
```

### Distributing Client Configurations
- Transfer the .ovpn file securely to clients using SCP or SFTP
- Never send configuration files through unsecured channels

## 4. Troubleshooting

### Common Issues

#### Server Won't Start
1. Check service status:
```bash
systemctl status openvpn@server
```

2. View logs:
```bash
tail -f /var/log/openvpn/openvpn.log
```

#### Client Can't Connect
1. Verify server is listening:
```bash
netstat -tulpn | grep openvpn
```

2. Check firewall rules:
```bash
iptables -L -n -v
```

3. Verify IP forwarding:
```bash
cat /proc/sys/net/ipv4/ip_forward
```

### Server Maintenance Commands

#### Restart OpenVPN Service
```bash
systemctl restart openvpn@server
```

#### Check Server Status
```bash
systemctl status openvpn@server
```

## 5. Security Considerations

### Best Practices
1. Keep the system updated:
```bash
apt update && apt upgrade
```

2. Regular certificate management:
- Review and revoke unused certificates
- Update CRL regularly
- Monitor access logs

3. Firewall Configuration:
- Only allow necessary ports
- Monitor and log suspicious activities

### Important Files and Directories
- Server Configuration: `/etc/openvpn/server.conf`
- Certificates: `/etc/openvpn/easy-rsa/pki/`
- Client Configurations: `/etc/openvpn/client-configs/`
- Logs: `/var/log/openvpn/`

## 6. Maintenance

### Regular Maintenance Tasks
1. Update the system and OpenVPN regularly
2. Monitor server logs
3. Check certificate expiration dates
4. Review and update firewall rules
5. Monitor server resources
6. Backup important configurations

### Backup Important Files
```bash
tar -czf openvpn-backup.tar.gz \
    /etc/openvpn \
    /etc/openvpn/easy-rsa/pki \
    /etc/openvpn/client-configs
```

### Support and Resources
- Documentation: https://openvpn.net/community-resources/
- Community Support: https://forums.openvpn.net/
- Security Advisories: https://openvpn.net/security-advisories/

## Additional Notes
- Default UDP port: 1194
- Protocol: UDP (can be changed to TCP if needed)
- Encryption: AES-256-CBC
- Authentication: TLS + Certificate based