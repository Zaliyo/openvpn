# OpenVPN 2.7.7 

Production-ready OpenVPN server with EasyRSA PKI management, 6 command-line utilities, and enterprise security hardening.

## 🚀 Features

### Core Components
- **OpenVPN 2.7.7** — Built from official source with all features enabled
  - LZO & LZ4 compression support
  - PKCS11 hardware security module support
  - PAM authentication
  - Async push capability
  - epoll support for high performance

- **OpenSSL 3.6.4** — Compiled from source (CVE-2026-75803 patched)
  - Modern AEAD cipher support
  - TLS 1.2+ with strong cipher suites
  - Latest security patches applied
  - Replaces system OpenSSL via LD_LIBRARY_PATH

- **EasyRSA 3.2.6** — Automated PKI management
  - Non-interactive certificate generation
  - Batch mode support for automation
  - Full X.509 PKI capabilities
  - CRL management

### Management Scripts (6 Included)
```bash
./bin/create-clients          # Create new VPN clients
./bin/revoke-clients          # Revoke client certificates
./bin/list-clients            # List all active clients
./bin/status                  # Check server status
./bin/renew-clients           # Renew expiring certificates
./bin/backup-pki              # GPG-encrypted PKI backup
```

### Architecture & Security
- ✅ **Multi-Architecture Support** — linux/amd64 & linux/arm64
- ✅ **Multi-Stage Build** — Minimal runtime image (~200MB)
- ✅ **Perl Removed** — Eliminated CVE-2026-13221, CVE-2026-12087, CVE-2026-57432
- ✅ **Audit Logging** — Compliance-ready event logging
- ✅ **Encrypted Backups** — GPG-encrypted PKI backup/restore
- ✅ **Vulnerability Optimized** — ~160 vulnerabilities (45% reduction)

### Modern Ciphers
- AES-256-GCM (default)
- ChaCha20-Poly1305
- TLS 1.2/1.3 with strong cipher suites

---

## 📦 Quick Start

### Using Docker
```bash
docker run -d \
  --name openvpn \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -p 1194:1194/udp \
  -v openvpn-data:/etc/openvpn/pki \
  -v openvpn-logs:/var/log/openvpn \
  -e VPN_IP=10.8.0.0 \
  -e VPN_PORT=1194 \
  zaliyo/openvpn:2.7.7
```

### Using Docker Compose
```bash
# Clone or download docker-compose.yml and .env.example
wget https://raw.githubusercontent.com/Zaliyo/openvpn/main/docker-compose/docker-compose.yml
cp docker-compose/.env.example docker-compose/.env

# Edit .env with your configuration
docker-compose up -d

# Initialize PKI and create clients
docker-compose exec openvpn easyrsa init-pki
docker-compose exec openvpn create-clients client1
```

---

## 🔐 Security Specifications

### Hardening Measures
- **Minimal attack surface** — Only OpenVPN, OpenSSL, and utilities included
- **No package manager** — Base image uses alpine/debian-slim
- **No development tools** — gcc, make, perl removed from runtime
- **CVE patching** — Latest OpenSSL with security fixes
- **Capability-based isolation** — NET_ADMIN only (no root)
- **Read-only filesystem support** — Configurable for compliance

### Certificate Security
- 4096-bit RSA keys by default
- SHA-512 signature algorithm
- 365-day certificate validity
- Automated CRL management
- GPG encryption for backups

---

## 📋 Environment Variables

```bash
VPN_IP=10.8.0.0              # VPN network subnet
VPN_PORT=1194                # UDP port (change for firewall)
DEBUG=0                       # Enable debug logging (0/1)
EASYRSA_BATCH=1              # Non-interactive mode (1 = enabled)
EASYRSA_REQ_CN=OpenVPN       # Certificate CN
EASYRSA_EXPIRE_DAYS=365      # Certificate validity
```

---

## 📁 Volume Mounts

| Path | Purpose |
|------|---------|
| `/etc/openvpn/pki` | PKI certificates, keys, CRL |
| `/var/log/openvpn` | Server and audit logs |
| `/etc/openvpn/conf` | OpenVPN configuration files |
| `/root/.gnupg` | GPG keys for backup encryption |

---

## 🎯 Management Examples

### Create a New Client
```bash
docker-compose exec openvpn create-clients alice
# Generates: /etc/openvpn/pki/issued/alice.crt, alice.key
```

### List All Clients
```bash
docker-compose exec openvpn list-clients
# Output: alice, bob, charlie, ...
```

### Revoke a Client
```bash
docker-compose exec openvpn revoke-clients alice
# Regenerates CRL (Certificate Revocation List)
```

### Backup PKI (GPG Encrypted)
```bash
docker-compose exec openvpn backup-pki
# Creates: openvpn-backup-TIMESTAMP.tar.gz.gpg
# Copy from: docker-compose/openvpn-backups/
```

### Check Server Status
```bash
docker-compose exec openvpn status
# Shows: OpenVPN version, loaded config, connected clients
```

### Renew Expiring Certificates
```bash
docker-compose exec openvpn renew-clients alice
# Renews alice's certificate for another 365 days
```

---

## 🏥 Health Checks

The container includes built-in health checks:
```bash
# Manual health check
nc -u -z localhost 1194
# Returns: 0 (healthy), 1 (unhealthy)
```

Interval: 30 seconds | Timeout: 10 seconds | Retries: 3

---

## 📊 Image Specifications

| Metric | Value |
|--------|-------|
| Base Image | debian:12-slim |
| Compressed Size | 53.2 MB |
| Uncompressed Size | 241 MB |
| Architectures | linux/amd64, linux/arm64 |
| OpenVPN | 2.7.7 (official) |
| OpenSSL | 3.6.4 (CVE patched) |
| EasyRSA | 3.2.6 (official) |
| Build Time | ~15 minutes (GitHub Actions) |

---

## 🔧 Troubleshooting

### Container Won't Start
```bash
# Check logs
docker-compose logs openvpn

# Verify PKI exists
docker-compose exec openvpn ls -la /etc/openvpn/pki/

# Reinitialize if corrupted
docker-compose exec openvpn easyrsa init-pki
```

### Health Check Failing
```bash
# Verify port binding
docker-compose ps

# Check firewall (port 1194/UDP must be open)
netstat -uln | grep 1194

# Manually test
docker exec openvpn nc -u -z localhost 1194
```

### Certificate Issues
```bash
# List all certificates
docker-compose exec openvpn easyrsa show-cert ca

# Check certificate validity
docker-compose exec openvpn openssl x509 -in /etc/openvpn/pki/issued/alice.crt -noout -dates
```

### Backup Recovery
```bash
# Find backup
ls -lh docker-compose/openvpn-backups/

# Restore (requires GPG passphrase)
docker-compose exec openvpn restore-pki <backup-file>.tar.gz.gpg
```

---

## 📚 Documentation

- **[GitHub Repository](https://github.com/Zaliyo/openvpn)** — Full source code, issues, discussions
- **[README](https://github.com/Zaliyo/openvpn/blob/main/README.md)** — Comprehensive setup guide
- **[CHANGELOG](https://github.com/Zaliyo/openvpn/blob/main/CHANGELOG.md)** — Version history and releases
- **[Docker Compose Guide](https://github.com/Zaliyo/openvpn/blob/main/docker-compose/README.md)** — Standalone deployment

---

## 🔄 CI/CD & Automation

### GitHub Actions Workflow
- **Trigger:** Push to `main` branch or manual `workflow_dispatch`
- **Builds:** Multi-architecture images (amd64 + arm64)
- **Pushes to:** Docker Hub as `zaliyo/openvpn:{version}` and `latest`
- **Build Time:** ~15 minutes per architecture
- **Caching:** GitHub Actions cache for layer reuse

### Build Locally
```bash
./build-multiarch.sh [repo] [version] [push]

# Examples:
./build-multiarch.sh zaliyo 2.7.7 true    # Build and push
./build-multiarch.sh myrepo 2.7.7 false   # Build only (no push)
```

---

## 🛡️ Security Best Practices

1. **Keep Certificates Private**
   - Never share `.key` files
   - Store PKI backups securely
   - Use GPG encryption for backups (built-in)

2. **Network Isolation**
   - Only expose UDP 1194 to public internet
   - Use firewall rules to restrict client IPs if possible
   - Monitor logs for failed authentication attempts

3. **Certificate Management**
   - Renew certificates before expiration (use `renew-clients`)
   - Revoke compromised certificates immediately
   - Maintain updated CRL

4. **Secrets & Credentials**
   - Store backups in secure location
   - Protect GPG passphrases
   - Use strong DH parameters (generated during init-pki)

5. **Updates**
   - Monitor [OpenVPN releases](https://github.com/OpenVPN/openvpn/releases)
   - Update Dockerfile when new versions available
   - Rebuild image and redeploy container

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/Zaliyo/openvpn/issues)
- **Discussions:** [GitHub Discussions](https://github.com/Zaliyo/openvpn/discussions)
- **OpenVPN Docs:** [https://openvpn.net/community-resources/](https://openvpn.net/community-resources/)

---

## 📄 License

See [LICENSE](https://github.com/Zaliyo/openvpn/blob/main/LICENSE) in repository.

---

## 🎉 Release Info

- **Version:** 2.7.7
- **Released:** 2026-09-15
- **Status:** Production Ready
- **Support:** LTS (OpenSSL 3.6.x, OpenVPN 2.7.x)
