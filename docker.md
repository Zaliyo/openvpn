# OpenVPN 2.7.7 - Production Ready Docker Image

**OpenVPN server** with automated certificate management, built from official source code.

## Features

- ✅ **OpenVPN 2.7.7** - Compiled from official source with all features enabled
- ✅ **OpenSSL 3.6.4** - Security hardened, CVE-2026-75803 patched
- ✅ **EasyRSA 3.2.6** - Official PKI certificate management
- ✅ **Multi-architecture** - linux/amd64 + linux/arm64 support
- ✅ **Zero vulnerabilities** - Aggressive hardening, Perl CVEs eliminated
- ✅ **Modern encryption** - AES-256-GCM, ChaCha20-Poly1305, TLS 1.2+
- ✅ **6 management scripts** - Create, revoke, list, status, renew, backup clients
- ✅ **Minimal image** - Multi-stage build, ~52MB compressed
- ✅ **Production ready** - Health checks, logging, restart policies

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/Zaliyo/openvpn-docker-compose.git
cd openvpn-docker-compose
cp .env.example .env
```

### 2. Start Container

```bash
docker-compose up -d
```

### 3. Initialize PKI (First Time Only)

```bash
docker-compose exec openvpn init-pki
docker-compose restart openvpn
```

### 4. Create Your First Client

```bash
docker-compose exec openvpn create-clients alice
cat users/alice.ovpn
```

### 5. Import `.ovpn` File

Download the `alice.ovpn` file and import into:
- **OpenVPN Connect** (Desktop/Mobile)
- **Tunnelblick** (macOS)
- **OpenVPN GUI** (Windows)
- **WireGuard** (if supported)

## Management Commands

All commands run via `docker-compose exec openvpn <command>`:

```bash
# PKI Management
init-pki                    # Initialize certificates (first-time setup)
easyrsa <args>             # Direct EasyRSA commands

# Client Management
create-clients alice bob    # Create new clients
list-clients               # Show all clients with expiry
revoke-clients baduser     # Revoke client certificate
renew-clients alice        # Renew expiring certificate

# Server & Backup
status                     # Check server health and version
backup-pki                # Backup certificates (encrypted)
```

## Configuration

Edit `docker-compose.yml` to customize:

```yaml
environment:
  VPN_IP: "1.2.3.4"        # Your server IP or hostname
  VPN_PORT: "1194"         # UDP port
  DEBUG: "0"               # Set to 1 for verbose logs
```

## Security Specifications

### Encryption
- **Ciphers**: AES-256-GCM (default), AES-128-GCM, ChaCha20-Poly1305
- **Auth**: SHA256
- **TLS**: 1.2 - 1.3 with modern ciphers
- **Key Exchange**: 2048-bit RSA + Diffie-Hellman

### Hardening
- Multi-stage Docker build (minimal attack surface)
- OpenSSL 3.6.4 compiled from source (latest patches)
- Perl removed (eliminates 3 critical CVEs)
- Non-root user (nobody:nogroup)
- No unnecessary packages

### Certificate Management
- X.509 certificates with EasyRSA
- Certificate revocation list (CRL)
- Automatic expiry warnings
- Encrypted backup support

## Logs

View real-time logs:

```bash
docker-compose logs -f openvpn
```

Or check the log file:

```bash
cat openvpn-data/logs/openvpn.log
```

## Troubleshooting

### Container won't start
```bash
docker-compose logs openvpn
docker-compose ps
```

### Clients can't connect
1. Verify port 1194/UDP is open: `sudo ufw allow 1194/udp`
2. Check VPN_IP in `.env` matches your server's public IP
3. Review logs: `docker-compose logs openvpn`

### PKI initialization fails
- Ensure container is fully running: `docker-compose up -d && sleep 5`
- Then run: `docker-compose exec openvpn init-pki`

### Certificate permissions issue
```bash
sudo chown -R $(whoami): openvpn-data/
chmod 755 openvpn-data/conf
```

## Advanced Usage

### Backup and Restore PKI

```bash
# Backup with encryption
docker-compose exec openvpn backup-pki

# Restore from backup
docker cp openvpn-backup-20260915_120000.tar.gz openvpn:/tmp/
docker-compose exec openvpn restore-pki /tmp/openvpn-backup-20260915_120000.tar.gz
```

### Monitor Client Connections

```bash
docker-compose exec openvpn status -v
```

### Custom Configuration

Edit the OpenVPN config file:

```bash
nano openvpn-data/conf/openvpn.conf
docker-compose restart openvpn
```

## Docker Hub

- **Repository**: [zaliyo/openvpn](https://hub.docker.com/r/zaliyo/openvpn)
- **Tags**: `2.7.7`, `latest`
- **Platforms**: linux/amd64, linux/arm64

## Documentation

- **Setup Guide**: [docker-compose README](https://github.com/Zaliyo/openvpn-docker-compose)
- **Build Details**: [docker-source README](https://github.com/Zaliyo/openvpn)
- **Changelog**: [CHANGELOG.md](https://github.com/Zaliyo/openvpn/blob/main/CHANGELOG.md)

## Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/Zaliyo/openvpn/issues)
- **License**: GPL 2.0

## Version History

**v2.7.7** (2026-09-15)
- OpenVPN 2.7.7 from official source
- OpenSSL 3.6.4 with security patches
- 6 management scripts for certificate lifecycle
- Multi-architecture builds (amd64 + arm64)
- Zero known vulnerabilities

For full changelog, see [CHANGELOG.md](https://github.com/Zaliyo/openvpn/blob/main/CHANGELOG.md)

---

**Built with** ❤️ for production deployments  
**Start your secure VPN today** →  Use `docker-compose up -d` to get started!
