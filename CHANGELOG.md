# Changelog

All notable changes to this OpenVPN project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.7.7] - 2026-09-15

### 🎯 Initial Release - Production-Ready OpenVPN Server

This is the first official release featuring a complete, enterprise-grade OpenVPN infrastructure with automated certificate management, monitoring, and disaster recovery capabilities.

### 🔐 Security
- OpenSSL 3.6.4 compiled from source to patch CVE-2026-75803 (AEAD forgeries vulnerability)
- OpenSSL prioritized via `LD_LIBRARY_PATH` in runtime container
- Multi-stage Docker build removes unnecessary build tools from final image
- Image vulnerabilities: ~160 total (optimized, minimal attack surface)

### ✨ Added
- **Enterprise-grade management scripts** (6 total):
  - `scripts/create-clients.sh` - Automated batch client creation with verification & audit logging
  - `scripts/revoke-clients.sh` - Batch revocation with operation tracking
  - `scripts/list-clients.sh` - Certificate listing with fingerprint/serial/expiry info
  - `scripts/status.sh` - System health check (container, PKI, client counts, versions)
  - `scripts/renew-clients.sh` - Auto-detect and renew expiring certificates
  - `scripts/backup-pki.sh` - Backup/restore with optional GPG encryption

- **Client management features**:
  - Certificate verification after creation/revocation
  - Automatic expiry warnings (3-level: expired, <7 days, <30 days)
  - Audit logging support with `-l|--log` flag for compliance
  - Bulk operation summaries with color-coded results
  - Certificate fingerprint, serial number, and key usage extraction

- **System reliability**:
  - Operation verification functions
  - Pre-restore automatic backup creation
  - Docker-compose and plain docker dual-mode support in all scripts
  - Comprehensive error handling and validation

- **Documentation**:
  - Comprehensive CHANGELOG.md with semantic versioning
  - Updated README.md focused on usage
  - IMPLEMENTATION_SUMMARY.md with complete feature guide
  - ENHANCEMENTS.md with specifications

### 🔄 Changed
- **EasyRSA:** Updated from 3.2.1 → 3.2.6 (latest stable)
- **OpenSSL:** Upgraded from 3.0.20 → 3.6.4 (compiled from source)
- **Dockerfile:** All versions now fully parameterized (OPENVPN_VERSION, EASYRSA_VERSION, OPENSSL_VERSION)
- **File structure:**
  - Generated `.ovpn` files now saved to `users/` folder (was: project root)
  - Management scripts organized in `scripts/` folder
  - Backups saved to `openvpn-backups/` with auto-detection
- **docker-compose.yml:** 
  - Updated volume mounts to use `./openvpn-data/` paths
  - Added backup volume mapping `./openvpn-backups:/backups`
  - Build args now support all three versions

### 🐛 Fixed
- Renew-clients.sh array syntax error (bad substitution in line 402)
- Docker-compose volume paths alignment
- EasyRSA version mismatch between Dockerfile and docker-compose.yml
- Security warning text paths in create-clients.sh

### 🗑️ Removed
- Deprecated `persist-key` and `persist-tun` OpenVPN options
- Deprecated `comp-lz4` compression (using modern alternatives)
- Hardcoded version strings (now using build arguments)

### 📊 Improved
- Image size optimization: 241MB uncompressed, 53.2MB compressed (multi-stage)
- Build time: ~3-5 minutes with source compilation
- Vulnerability profile: ~160 total (minimal attack surface)
- Error messages with actionable guidance
- Color-coded CLI output for better UX

---

## Version Features

| Feature | v2.7.7 |
|---------|--------|
| OpenVPN | 2.7.7 (built from source) |
| EasyRSA | 3.2.6 |
| OpenSSL | 3.6.4 (compiled from source) |
| Management Scripts | 6 (create, revoke, list, status, renew, backup) |
| Audit Logging | ✅ |
| Certificate Verification | ✅ |
| Auto Renewal | ✅ |
| Backup/Restore with Encryption | ✅ (GPG) |
| Docker Support | docker-compose + plain docker |
| Image Size | 241MB uncompressed, 53.2MB compressed |
| Vulnerabilities | ~160 (optimized) |

---

## Security Notes

### CVE-2026-75803 Patch
OpenSSL 3.6.4 is compiled from source to address AEAD forgeries vulnerability in earlier versions.
This fixes the cryptographic weakness that could allow attackers to forge authenticated encryption.

**Affected OpenSSL versions:** 3.0.x - 3.5.x (fixed in 3.6.0+)
**Impact:** All encrypted traffic potentially vulnerable in earlier versions
**Resolution:** Use this v2.7.7 release which includes OpenSSL 3.6.4

### Deployment Best Practices
1. Always back up PKI before upgrades: `./scripts/backup-pki.sh backup -e`
2. Monitor certificate expiry: `./scripts/renew-clients.sh -d 7`
3. Audit all operations: `./scripts/create-clients.sh -l audit.log alice`
4. Keep Docker base image updated: `docker-compose build --pull --no-cache`
5. Restrict file permissions: `chmod 600 users/*.ovpn`

---

## Known Issues & Limitations

- OpenVPN requires NET_ADMIN capability (not compatible with strict security policies)
- PKI passwords are not persisted (re-enter on each container start if needed)
- Client revocation requires CRL regeneration (automatic, but adds ~2s to revoke operation)
- Large certificate counts (500+) may slow down list operations

---

## Contributing

To report issues or suggest improvements:
1. Check existing issues first
2. Include version number and error messages
3. Provide reproducible steps
4. Include relevant logs from `docker-compose logs openvpn`

---

## References

- [OpenVPN Project](https://openvpn.net/)
- [EasyRSA Documentation](https://easy-rsa.readthedocs.io/)
- [OpenSSL Releases](https://www.openssl.org/source/)
- [Debian LTS Support](https://wiki.debian.org/LTS)
- [Keep a Changelog](https://keepachangelog.com/)
