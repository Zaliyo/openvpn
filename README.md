# OpenVPN Setup Guide

## Overview

This is a production-ready OpenVPN server running on Docker with automated certificate management and monitoring tools.

**Current Versions:**
- OpenVPN 2.7.7 (built from official source)
- EasyRSA 3.2.6 (Official PKI management)
- OpenSSL 3.6.4 (Security hardened)
- Debian 12-slim base image

For version history and changes, see [CHANGELOG.md](CHANGELOG.md)

## Building the Docker Image

### Prerequisites for Building

**Required:** The OpenVPN source tarball must be in the `source/` directory before building.

Check if it exists:
```bash
ls -lh source/openvpn-2.7.7.tar.gz
```

If not present, download it:
```bash
mkdir -p source/
cd source/
wget https://github.com/OpenVPN/openvpn/archive/refs/tags/v2.7.7.tar.gz -O openvpn-2.7.7.tar.gz
cd ..
```

### Quick Build
```bash
# Build with defaults (OpenVPN 2.7.7, EasyRSA 3.2.6, OpenSSL 3.6.4)
docker-compose build openvpn
```

### Build with Custom Versions

**Via docker-compose with environment variable:**
```bash
# Build with specific OpenVPN version (must have source/openvpn-X.Y.Z.tar.gz)
OPENVPN_VERSION=2.7.7 docker-compose build openvpn

# Or with EasyRSA version
EASYRSA_VERSION=3.1.7 docker-compose build openvpn
```

**Via .env file:**
```bash
# Create/edit .env
OPENVPN_VERSION=2.7.7
EASYRSA_VERSION=3.2.6
OPENSSL_VERSION=3.6.4

# Then build
docker-compose build openvpn
```

**Via --build-arg:**
```bash
docker-compose build --build-arg OPENVPN_VERSION=2.7.7 --build-arg EASYRSA_VERSION=3.2.6 --build-arg OPENSSL_VERSION=3.6.4 openvpn
```

### Version Notes

For detailed technical information about compiled features, security patches, and compilation flags, see [CHANGELOG.md](CHANGELOG.md#security).

**To use a different OpenVPN version:**
1. Download the source: `wget https://github.com/OpenVPN/openvpn/archive/refs/tags/v2.X.Y.tar.gz -O source/openvpn-2.X.Y.tar.gz`
2. Update `OPENVPN_VERSION` in docker-compose.yml or use: `OPENVPN_VERSION=2.X.Y docker-compose build`

**To use a different EasyRSA version:**
- Update `EASYRSA_VERSION` in docker-compose.yml (automatically downloaded during build)

**To use a different OpenSSL version:**
- Update `OPENSSL_VERSION` in docker-compose.yml
- Download source: `wget https://github.com/openssl/openssl/releases/download/openssl-X.Y.Z/openssl-X.Y.Z.tar.gz -O source/openssl-X.Y.Z.tar.gz`

### Force Rebuild
```bash
# Rebuild with latest packages from Debian
docker-compose build --no-cache openvpn

# Force pull latest base image
docker-compose build --pull --no-cache openvpn
```

## Prerequisites

Before starting, create a `.env` file from the provided `env-sample`:

```bash
cp env-sample .env
```

Then edit `.env` and set the required values:
- `VPN_IP`: The public IP address or hostname of your VPN server (e.g., `vpn.example.com` or `1.2.3.4`)
- `CLIENTNAME`: Default client name for initial setup (optional, can be overridden per client)

## Step 1: Initialize Configuration Files and Certificates

Run the following commands to initialize the OpenVPN configuration files and certificates.

**First, generate the OpenVPN server configuration:**

```bash
# Replace VPN_IP with your actual server IP or hostname
# Examples: 203.0.113.45 or vpn.example.com
docker-compose run --rm openvpn ovpn_genconfig -u udp://203.0.113.45

# Alternative with domain name:
# docker-compose run --rm openvpn ovpn_genconfig -u udp://vpn.example.com
```

**Then, initialize the PKI (creates certificates and keys):**

```bash
# This will prompt for a passphrase - use a strong one
docker-compose run --rm openvpn ovpn_initpki
```

## Step 2: Fix File Permissions (Optional)

If you need to access the generated files as a non-root user, adjust the permissions:

```bash
# Allow current user to read/write config and data
sudo chown -R $(whoami): ./openvpn-data
```

This is useful if you're backing up or managing files outside Docker.

## Step 3: Start OpenVPN Server Process

Start the OpenVPN server in detached mode:

```bash
docker-compose up -d openvpn
```

You can monitor the container logs using:

```bash
docker-compose logs -f
```

## Step 4: Generate Client Certificates (Multiple Ways)

### Option A: Automated Script (Recommended for Multiple Clients)

Use the provided `scripts/create-clients.sh` script to generate multiple clients efficiently:

```bash
# Interactive mode - prompts for client names
./scripts/create-clients.sh

# Create single client
./scripts/create-clients.sh alice

# Create multiple clients
./scripts/create-clients.sh alice bob charlie

# Create clients without passphrases (not recommended)
./scripts/create-clients.sh -n alice bob

# Create with audit logging
./scripts/create-clients.sh -l audit.log alice bob

# View all options
./scripts/create-clients.sh --help
```

The script will:
- Generate certificates with passphrases by default (more secure)
- Export `.ovpn` configuration files to `users/` folder automatically
- Verify operations completed successfully
- Provide audit logging option for compliance tracking
- Provide friendly feedback on progress with operation summary

### Option B: Manual Command Line

Generate a client certificate with a passphrase (recommended, more secure):

```bash
# Replace 'alice' with your desired client name
docker-compose run --rm openvpn easyrsa build-client-full alice
```

Alternatively, generate without a passphrase (not recommended for production):

```bash
docker-compose run --rm openvpn easyrsa build-client-full alice nopass
```

The command will prompt for your CA passphrase (set during `ovpn_initpki`).

## Step 5: Retrieve Client Configuration

*Note: If you used the `scripts/create-clients.sh` script, your `.ovpn` files are already created in `users/` folder. Skip this step.*

For manual client creation, export the client configuration with embedded certificates:

```bash
# Replace 'alice' with your client name
docker-compose run --rm openvpn ovpn_getclient alice > alice.ovpn

# The .ovpn file is ready to import into any OpenVPN client
# Verify it was created: ls -lh alice.ovpn
```

## Step 6: Revoke a Client Certificate

To revoke a client certificate while keeping the corresponding `.crt`, `.key`, and `.req` files:

```bash
docker-compose run --rm openvpn ovpn_revokeclient $CLIENTNAME
```

To revoke a client certificate and remove the corresponding `.crt`, `.key`, and `.req` files:

```bash
docker-compose run --rm openvpn ovpn_revokeclient $CLIENTNAME remove
```

## Project Structure

```
openvpn/
├── Dockerfile                 # Multi-stage build: OpenVPN 2.7.7 + OpenSSL 3.6.4 from source
├── docker-compose.yml         # Container orchestration with health checks
├── bin/                       # Helper scripts (container entrypoint)
│   ├── entrypoint.sh         # Container entrypoint - routes commands
│   ├── ovpn_run              # Start OpenVPN daemon
│   ├── ovpn_genconfig        # Generate server configuration
│   ├── ovpn_initpki          # Initialize PKI with EasyRSA
│   ├── ovpn_getclient        # Export client .ovpn files
│   └── ovpn_revokeclient     # Revoke client certificates
├── scripts/                   # Management scripts
│   ├── create-clients.sh      # Automated multi-client creation with verification
│   ├── revoke-clients.sh      # Batch client revocation
│   ├── list-clients.sh        # List certificates with status/expiry/fingerprint
│   ├── status.sh              # System health check
│   ├── renew-clients.sh       # Auto-detect and renew expiring certificates
│   └── backup-pki.sh          # Backup/restore with encryption support
├── users/                     # Client configuration files (.ovpn)
├── openvpn-data/             # Volume mount (created automatically)
│   ├── conf/                 # OpenVPN config & PKI
│   └── logs/                 # Container logs
├── openvpn-backups/          # PKI backups directory
├── Readme.md                  # This file
└── env-sample                 # Environment template
```

### Files to Customize

**Configuration:**
- **docker-compose.yml**: Port mappings, restart policy, resource limits
- **bin/ovpn_genconfig**: Default OpenVPN settings (cipher, auth, DNS, subnet)
- **.env**: Server IP (VPN_IP) and optional default client name

**Scripts (optional):**
- Any management script in `scripts/` can be customized for your environment
- All scripts support `-h|--help` for options

See [CHANGELOG.md](CHANGELOG.md) for technical version information.

## Security & Hardening

### Security Features
- Multi-stage Docker build with minimal runtime image
- OpenSSL 3.6.4 compiled from source (security patched)
- Modern encryption: AES-256-GCM, ChaCha20-Poly1305
- TLS 1.2+ with strong ciphers
- Automatic certificate renewal with expiry warnings
- Audit logging support for compliance

For detailed security information, vulnerability details, and CVE patches, see [CHANGELOG.md](CHANGELOG.md#-security).

### Container Security Best Practices
- The container runs with `NET_ADMIN` capability (required for OpenVPN)
- Firewall port 1194/UDP to trusted networks only
- Use `docker-compose up` with `unless-stopped` restart policy
- Store PKI certificates securely; don't commit to version control
- Regularly update with: `docker-compose build --pull --no-cache openvpn`
- Use audit logging for production deployments: `./scripts/create-clients.sh -l audit.log`

## Debugging Tips

Enable debug output by setting the `DEBUG` environment variable in your `.env` file:

```bash
DEBUG=1
```

Then view logs:

```bash
docker-compose logs -f openvpn
```

## Troubleshooting

**Build fails with "COPY source/openvpn-..." error:**
- The source tarball is missing. Download it first:
  ```bash
  mkdir -p source/
  cd source/
  wget https://github.com/OpenVPN/openvpn/archive/refs/tags/v2.7.7.tar.gz -O openvpn-2.7.7.tar.gz
  cd ..
  ```

**"openvpn: error while loading shared libraries" at runtime:**
- Missing runtime dependencies. Rebuild with: `docker-compose build --no-cache openvpn`

**Container starts but clients can't connect:**
- Check that port 1194/UDP is open on your firewall: `sudo ufw allow 1194/udp`
- Verify your `VPN_IP` in `.env` matches your actual server IP
- Check logs: `docker-compose logs -f openvpn`

**Certificate generation fails with "CA not initialized":**
- Run `docker-compose run --rm openvpn ovpn_initpki` first
- This creates the certificate authority and must be done before creating client certs

