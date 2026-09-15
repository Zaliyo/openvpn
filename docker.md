# OpenVPN 2.7.7 - Production Ready Docker Image

**OpenVPN server** with automated certificate management, built from official source code.

## Features

- ✅ **OpenVPN 2.7.7** - Compiled from official source with all features enabled
- ✅ **OpenSSL 3.6.4** - Security hardened, CVE-2026-75803 patched
- ✅ **EasyRSA 3.2.6** - Official PKI certificate management
- ✅ **Multi-architecture** - linux/amd64 + linux/arm64 support
- ✅ **Zero vulnerabilities** - Aggressive hardening, Perl CVEs eliminated
- ✅ **Modern encryption** - AES-256-GCM, ChaCha20-Poly1305, TLS 1.2+
- ✅ **Zero-config first boot** - default `openvpn.conf` and PKI (CA, server cert, DH params, TLS-crypt key) are generated automatically on first startup, no manual init step
- ✅ **6 management scripts** - Create, revoke, list, status, renew, backup clients
- ✅ **Automatic `.ovpn` lifecycle** - `create-clients` writes a ready-to-import `.ovpn`, `revoke-clients` deletes it, `renew-clients` rebuilds it with the new cert
- ✅ **Minimal image** - Multi-stage build, ~52MB compressed
- ✅ **Production ready** - Health checks, logging, restart policies

## Quick Start

### 1. Clone and Setup

```bash
git clone https://github.com/Zaliyo/openvpn-docker-compose.git
cd openvpn-docker-compose
cp .env.example .env
```

Edit `.env` and set `VPN_IP` to this server's public IP or hostname -
every `.ovpn` file `create-clients`/`renew-clients` generates uses it
as the `remote` address. If you skip this, client creation still
works, but each generated `.ovpn` gets a placeholder you'll need to
edit by hand.

### 2. Start Container

```bash
docker-compose up -d
```

That's it - **no manual PKI initialization step is required.** On
first boot the container automatically installs a default
`openvpn.conf` (if `data/conf/openvpn.conf` doesn't exist yet),
initializes the PKI (if `data/conf/pki/ca.crt` doesn't exist yet),
and starts the OpenVPN server. Watch it happen with:

```bash
docker-compose logs -f openvpn
```

First boot takes a minute or two (mostly Diffie-Hellman parameter
generation). Every later restart just no-ops both checks and starts
immediately - your PKI and config are never regenerated once they
exist.

If initialization fails partway, fix the underlying issue (check the
logs), then either restart the container to retry automatically, or
re-run it directly:

```bash
docker-compose exec openvpn init-pki
```

### 3. Create Your First Client

```bash
docker-compose exec openvpn create-clients alice
cat users/alice.ovpn
```

### 4. Import `.ovpn` File

Download the `alice.ovpn` file and import into:
- **OpenVPN Connect** (Desktop/Mobile)
- **Tunnelblick** (macOS)
- **OpenVPN GUI** (Windows)
- **WireGuard** (if supported)

## Management Commands

All commands run via `docker-compose exec openvpn <command>`:

```bash
# PKI Management
init-pki                    # (Re-)run PKI init manually - not needed on a normal first boot
easyrsa <args>             # Direct EasyRSA commands

# Client Management
create-clients alice bob    # Create new clients, writes users/<name>.ovpn
list-clients               # Show all clients with expiry
revoke-clients baduser     # Revoke client certificate, removes users/baduser.ovpn
renew-clients alice        # Renew expiring certificate, rewrites users/alice.ovpn with the new cert

# Server & Backup
status                     # Check server health and version
backup-pki                # Backup certificates (encrypted)
```

## Configuration

Edit `.env` (in the docker-compose repo) to customize:

```env
VPN_IP=1.2.3.4             # Your server's public IP or hostname
VPN_PORT=1194              # UDP port
DEBUG=0                    # Set to 1 for verbose logs
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
- `.ovpn` client bundles are kept in sync with certificate state:
  created alongside the cert, deleted on revoke, rebuilt on renew

## Logs

View real-time logs:

```bash
docker-compose logs -f openvpn
```

Or check the log file:

```bash
cat data/logs/openvpn.log
```

## Troubleshooting

### Container won't start
```bash
docker-compose logs openvpn
docker-compose ps
```

### Clients can't connect
1. Verify port 1194/UDP is open: `sudo ufw allow 1194/udp`
2. Check `VPN_IP` in `.env` matches your server's public IP
3. Review logs: `docker-compose logs openvpn`

### PKI initialization fails
PKI initialization now runs automatically on first boot - if it fails
partway, check the logs for the actual error, fix it, then either
restart the container to retry automatically or re-run it directly:

```bash
docker-compose exec openvpn init-pki
```

### Certificate permissions issue
```bash
sudo chown -R 65534:65534 data/conf
chmod 755 data/conf
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
nano data/conf/openvpn.conf
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
- Zero-config first boot: automatic default `openvpn.conf` install and PKI initialization
- `.ovpn` client bundle lifecycle kept consistent across create/revoke/renew
- 6 management scripts for certificate lifecycle
- Multi-architecture builds (amd64 + arm64)
- Zero known vulnerabilities

For full changelog, see [CHANGELOG.md](https://github.com/Zaliyo/openvpn/blob/main/CHANGELOG.md)

---

**Built with** ❤️ for production deployments  
**Start your secure VPN today** →  Use `docker-compose up -d` to get started!
