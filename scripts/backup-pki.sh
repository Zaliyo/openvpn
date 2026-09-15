#!/bin/bash

##############################################################################
# OpenVPN PKI Backup and Restore Script
# Create and restore backups of the PKI directory for disaster recovery
##############################################################################
#
# EXAMPLES:
#
#   # Create backup
#   ./scripts/backup-pki.sh backup
#
#   # Create encrypted backup
#   ./scripts/backup-pki.sh backup -e
#
#   # List available backups
#   ./scripts/backup-pki.sh list
#
#   # Restore from backup
#   ./scripts/backup-pki.sh restore backup_2026-09-15_120000.tar.gz
#
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
CONTAINER_NAME="openvpn"
USE_DOCKER_COMPOSE=true
BACKUP_DIR="openvpn-backups"
COMPRESS_ONLY=false
ENABLE_ENCRYPTION=false
ENCRYPT_PASS=""
VERBOSE=false

# Function to log messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
Usage: ./scripts/$0 [COMMAND] [OPTIONS]

Backup and restore OpenVPN PKI infrastructure.

COMMANDS:
    backup                  Create a backup of the PKI directory
    restore FILE            Restore from a backup file
    list                    List available backups

OPTIONS:
    -h, --help              Show this help message
    -e, --encrypt           Encrypt backup with GPG (requires 'gpg' command)
    -v, --verbose           Enable verbose output
    -c, --container NAME    Container name (for plain docker, default: openvpn)
    -d, --dir PATH          Backup directory (default: openvpn-backups)

EXAMPLES:
    # Create unencrypted backup
    ./scripts/$0 backup

    # Create encrypted backup
    ./scripts/$0 backup -e

    # List all backups
    ./scripts/$0 list

    # Restore from backup (requires confirmation)
    ./scripts/$0 restore openvpn-backups/backup_2026-09-15_120000.tar.gz
EOF
    exit 1
}

# Function to check if container is running
check_container() {
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if ! docker-compose ps openvpn | grep -q "Up"; then
            log_error "OpenVPN container is not running"
            log "Start the container with: docker-compose up -d openvpn"
            exit 1
        fi
    else
        if ! docker ps | grep -q "$CONTAINER_NAME"; then
            log_error "Container '$CONTAINER_NAME' is not running"
            exit 1
        fi
    fi
}

# Function to create backup
create_backup() {
    local encrypt=$1
    
    # Create backup directory if it doesn't exist
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
    
    local timestamp=$(date '+%Y-%m-%d_%H%M%S')
    local backup_file="$BACKUP_DIR/backup_${timestamp}.tar.gz"
    
    log "Creating PKI backup..."
    
    # Create tar backup using docker
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn tar czf - -C /etc/openvpn pki/ 2>/dev/null > "$backup_file"
    else
        docker exec "$CONTAINER_NAME" tar czf - -C /etc/openvpn pki/ 2>/dev/null > "$backup_file"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Failed to create backup"
        return 1
    fi
    
    local file_size=$(du -h "$backup_file" | cut -f1)
    log "✓ Backup created: $backup_file ($file_size)"
    
    # Encrypt if requested
    if [[ "$encrypt" == "true" ]]; then
        if ! command -v gpg &> /dev/null; then
            log_error "GPG not found. Cannot encrypt backup."
            log "Install with: brew install gnupg (or apt install gnupg on Linux)"
            return 1
        fi
        
        log "Encrypting backup with GPG..."
        
        # Generate symmetric encryption key interactively
        if ! gpg --symmetric --cipher-algo AES256 "$backup_file"; then
            log_error "GPG encryption failed"
            return 1
        fi
        
        # Remove unencrypted version
        rm "$backup_file"
        backup_file="${backup_file}.gpg"
        
        local enc_size=$(du -h "$backup_file" | cut -f1)
        log "✓ Encrypted backup: $backup_file ($enc_size)"
    fi
    
    # Security warnings
    echo ""
    echo -e "${YELLOW}⚠️  Backup contains sensitive data${NC}"
    echo "   - Keep backup in secure location"
    echo "   - Restrict access: chmod 600 $backup_file"
    if [[ "$encrypt" != "true" ]]; then
        echo "   - Consider encrypting: gpg --symmetric $backup_file"
    fi
    echo ""
    
    log "Backup location: $(pwd)/$backup_file"
}

# Function to list backups
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_warn "Backup directory does not exist: $BACKUP_DIR"
        return 0
    fi
    
    local backups=($(ls -1 "$BACKUP_DIR"/backup_*.tar.gz* 2>/dev/null || echo ""))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_warn "No backups found in $BACKUP_DIR"
        return 0
    fi
    
    echo ""
    echo -e "${BLUE}Available backups:${NC}"
    for backup in "${backups[@]}"; do
        local file=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$backup" 2>/dev/null || echo "Unknown")
        
        if [[ "$file" == *.gpg ]]; then
            echo -e "  ${YELLOW}🔒 $file${NC} ($size) - $date"
        else
            echo -e "  📦 $file ($size) - $date"
        fi
    done
    echo ""
}

# Function to restore backup
restore_backup() {
    local backup_file=$1
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    # Check if file is encrypted
    if [[ "$backup_file" == *.gpg ]]; then
        log_warn "Backup is GPG encrypted. Decrypting..."
        
        if ! command -v gpg &> /dev/null; then
            log_error "GPG not found. Cannot decrypt backup."
            return 1
        fi
        
        # Decrypt to temp file
        local temp_file="/tmp/openvpn_backup_$$_temp.tar.gz"
        if ! gpg --decrypt --output "$temp_file" "$backup_file"; then
            log_error "Failed to decrypt backup"
            return 1
        fi
        backup_file="$temp_file"
    fi
    
    # Confirmation
    echo ""
    echo -e "${RED}WARNING: Restoring from backup will overwrite current PKI!${NC}"
    echo "Backup file: $backup_file"
    echo ""
    read -p "Are you sure you want to restore? (type 'yes' to confirm): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Restore cancelled"
        return 0
    fi
    
    # Create backup of current PKI before restoring
    log "Creating backup of current PKI before restore..."
    local pre_restore_backup="$BACKUP_DIR/backup_pre_restore_$(date '+%Y-%m-%d_%H%M%S').tar.gz"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn tar czf - -C /etc/openvpn pki/ 2>/dev/null > "$pre_restore_backup"
    else
        docker exec "$CONTAINER_NAME" tar czf - -C /etc/openvpn pki/ 2>/dev/null > "$pre_restore_backup"
    fi
    log "Pre-restore backup: $pre_restore_backup"
    
    # Restore
    log "Restoring PKI from backup..."
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        cat "$backup_file" | docker-compose exec -T openvpn tar xzf - -C /etc/openvpn
    else
        cat "$backup_file" | docker exec -i "$CONTAINER_NAME" tar xzf - -C /etc/openvpn
    fi
    
    log "✓ Successfully restored PKI from backup"
    
    # Clean up temp file if was encrypted
    if [[ -f "/tmp/openvpn_backup_$$_temp.tar.gz" ]]; then
        rm "/tmp/openvpn_backup_$$_temp.tar.gz"
    fi
    
    echo ""
    log_warn "PKI has been restored. Verify:"
    log "  1. Run: ./scripts/status.sh"
    log "  2. Check: ./scripts/list-clients.sh -e"
    log "  3. Restart container: docker-compose restart openvpn"
    echo ""
}

# Main function
main() {
    # Parse arguments
    local command=$1
    shift || true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -e|--encrypt)
                ENABLE_ENCRYPTION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -c|--container)
                CONTAINER_NAME="$2"
                USE_DOCKER_COMPOSE=false
                shift 2
                ;;
            -d|--dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                # This is the restore filename
                break
                ;;
        esac
    done
    
    # Auto-detect docker-compose vs plain docker
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if ! command -v docker-compose &> /dev/null; then
            log_warn "docker-compose not found. Using plain docker with container: $CONTAINER_NAME"
            USE_DOCKER_COMPOSE=false
        else
            cd "$(dirname "$0")/.." || exit 1
        fi
    fi
    
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        exit 1
    fi
    
    # Validate command
    if [[ -z "$command" ]]; then
        usage
    fi
    
    # Execute command
    case $command in
        backup)
            check_container
            echo ""
            create_backup "$ENABLE_ENCRYPTION"
            ;;
        list)
            list_backups
            ;;
        restore)
            check_container
            if [[ -z "$1" ]]; then
                log_error "Restore filename required"
                usage
            fi
            echo ""
            restore_backup "$1"
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            ;;
    esac
}

# Run main function
main "$@"
