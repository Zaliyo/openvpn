# OpenVPN 2.7.7 - Production Ready Docker Image

**OpenVPN server** with automated certificate management, built from official source code.

## Features

- ✅ **OpenVPN 2.7.7** - Compiled from official source with all features enabled
- ✅ **OpenSSL 3.6.4** - Source-compiled and linked by the OpenVPN binary itself, patching CVE-2026-75803 for that process (the Debian base image separately carries its own unpatched libssl3 package - see Security Specifications below)
- ✅ **EasyRSA 3.2.6** - Official PKI certificate management
- ✅ **Multi-architecture** - linux/amd64 + linux/arm64 support
- ✅ **Hardened build** - Perl and its packages purged from the final image
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
backup-pki                # Backup PKI (encrypted; needs GPG_PASSPHRASE[_FILE])
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
- Multi-stage Docker build - build tooling is meant to stay in the builder stage, though `docker scout cves` currently shows `gcc-12` present in the runtime image too; worth tracing which runtime package pulls it in as a dependency and removing it if it's not actually needed
- OpenSSL 3.6.4 compiled from source and linked by the OpenVPN process via `LD_LIBRARY_PATH`
- Perl and its packages purged from the runtime image
- Non-root user (nobody:nogroup) for the OpenVPN process itself

### Known residual vulnerabilities

The base image (`debian:12-slim`) still ships a handful of packages with
open CVEs that this project doesn't control, since Debian hasn't
released fixes for most of them yet. Run `docker scout cves
zaliyo/openvpn:2.7.7` for the current, authoritative count - do not
treat any number here as up to date, since it changes with every base
image refresh. As of the last check:
- `pcre2` was out of date relative to Debian's own patched version
  (`10.42-1+deb12u1`) - fixable by adding an `apt-get upgrade` step to
  the Dockerfile before/after package install, not yet done.
- `openssl`/`libssl3` (the Debian-packaged copy, distinct from the
  source-compiled 3.6.4 above) still carries the unfixed
  CVE-2026-75803 - it's a transitive dependency of another runtime
  package, not something OpenVPN itself loads, but it is present on
  disk and picked up by scanners.
- The remaining findings (glibc, util-linux, systemd, coreutils, tar,
  krb5, and others) have no Debian-provided fix available at all yet;
  reducing them further would mean dropping packages that pull them in
  or moving off `debian:12-slim`.

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

The archive contains the CA private key, the server key and every client key,
so `backup-pki` **requires a passphrase and refuses to run without one**. A
mounted file is preferred over an environment variable, which is readable via
`/proc/<pid>/environ` and lands in your shell history.

```bash
# Preferred: passphrase from a mounted file / docker secret
docker-compose exec -e GPG_PASSPHRASE_FILE=/run/secrets/ovpn_backup_pass \
  openvpn backup-pki

# Or via environment variable
docker-compose exec -e GPG_PASSPHRASE='<passphrase>' openvpn backup-pki
```

The archive is streamed straight into GPG, so the unencrypted PKI never touches
the backups volume, and it is verified to decrypt before the command reports
success. Output is `openvpn-backup-<timestamp>.tar.gz.gpg`, mode 0600, in
`/backups` (AES-256, s2k mode 3 / SHA-512 / max iteration count).

Store the passphrase somewhere other than the backup. Without it the archive is
unrecoverable; with it, it is the entire VPN.

```bash
# Restore: decrypt and unpack over /etc/openvpn
docker cp openvpn-backup-<timestamp>.tar.gz.gpg openvpn:/tmp/
docker-compose exec openvpn sh -c \
  'gpg -d /tmp/openvpn-backup-<timestamp>.tar.gz.gpg | tar -xzf - -C /etc/openvpn'
docker-compose restart openvpn
```

An unencrypted backup is still possible, but has to be requested explicitly:

```bash
docker-compose exec -e ALLOW_UNENCRYPTED_BACKUP=1 openvpn backup-pki
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

For full changelog, see [CHANGELOG.md](https://github.com/Zaliyo/openvpn/blob/main/CHANGELOG.md)

---

**Built with** ❤️ for production deployments  
**Start your secure VPN today** →  Use `docker-compose up -d` to get started!
