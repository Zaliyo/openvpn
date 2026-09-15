# OpenVPN Docker Compose Stack

This is a standalone docker-compose project that deploys OpenVPN from a pre-built Docker Hub image.

## Quick Start

### 1. Configuration

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` and set your Docker Hub image:

```env
DOCKER_IMAGE=yourusername/openvpn:2.7.7
```

### 2. Create Directories

```bash
mkdir -p openvpn-data/conf
mkdir -p openvpn-data/logs
mkdir -p openvpn-backups
mkdir -p users
```

### 3. Start the Container

```bash
docker-compose up -d
```

### 4. Initialize PKI (first time only)

```bash
docker-compose exec openvpn /etc/openvpn/bin/ovpn_initpki
```

### 5. Create a Client

```bash
docker-compose exec openvpn /opt/scripts/create-clients.sh myuser
```

The `.ovpn` config file will be in the `users/` directory.

## Management Scripts

Available inside the container at `/opt/scripts/`:

- `create-clients.sh` - Create new VPN clients
- `revoke-clients.sh` - Revoke client certificates
- `list-clients.sh` - List all certificates
- `status.sh` - System health check
- `renew-clients.sh` - Auto-renew expiring certificates
- `backup-pki.sh` - Backup/restore PKI with encryption

### Examples

```bash
# List all clients with expiry dates
docker-compose exec openvpn /opt/scripts/list-clients.sh -e

# Create multiple clients
docker-compose exec openvpn /opt/scripts/create-clients.sh alice bob charlie

# Check system status
docker-compose exec openvpn /opt/scripts/status.sh -v

# Renew expiring certificates
docker-compose exec openvpn /opt/scripts/renew-clients.sh -d 7

# Backup PKI with encryption
docker-compose exec openvpn /opt/scripts/backup-pki.sh backup -e

# Revoke a client
docker-compose exec openvpn /opt/scripts/revoke-clients.sh baduser
```

## Logs

View OpenVPN logs:

```bash
docker-compose logs openvpn
docker-compose logs -f openvpn  # Follow logs
```

Or directly:

```bash
cat openvpn-data/logs/openvpn.log
```

## Troubleshooting

**Container fails to start:**
```bash
docker-compose logs openvpn
docker-compose ps  # Check status
```

**Health check failing:**
```bash
docker-compose exec openvpn nc -u -z localhost 1194
```

**Certificate permissions issue:**
```bash
sudo chown -R 65534:65534 openvpn-data/conf
chmod 755 openvpn-data/conf
```

## Stop & Cleanup

```bash
# Stop container
docker-compose down

# Remove container and volumes
docker-compose down -v

# Remove image
docker rmi $(DOCKER_IMAGE)
```

## Network Configuration

Edit `docker-compose.yml` to customize:
- `VPN_PORT` - Change UDP port (default: 1194)
- `openvpn-network` - Change bridge network name
- Volume mounts - Change data directories

## Security

1. Always back up PKI before changes:
   ```bash
   docker-compose exec openvpn /opt/scripts/backup-pki.sh backup -e
   ```

2. Protect `.ovpn` files:
   ```bash
   chmod 600 users/*.ovpn
   ```

3. Use encryption for backups (included with `-e` flag)

4. Monitor audit logs if enabled:
   ```bash
   docker-compose exec openvpn cat /var/log/openvpn/audit.log
   ```

## More Information

- [README.md](../README.md) - Build from source instructions
- [CHANGELOG.md](../CHANGELOG.md) - Version history and features
