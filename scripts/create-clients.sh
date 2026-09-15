#!/bin/bash

##############################################################################
# OpenVPN Client Creation Script
# Automates the process of creating multiple OpenVPN client certificates
# and exporting their configuration files
##############################################################################
#
# EXAMPLES:
#
#   # Create single client
#   ./scripts/create-clients.sh alice
#
#   # Create multiple clients
#   ./scripts/create-clients.sh alice bob charlie
#
#   # Create clients WITHOUT passphrases (faster, less secure)
#   ./scripts/create-clients.sh -n alice bob
#
#   # Create with verbose output
#   ./scripts/create-clients.sh -v alice bob charlie
#
#   # Interactive mode (prompts for client names)
#   ./scripts/create-clients.sh
#
# OUTPUT:
#   Generated .ovpn files are saved to project root directory
#
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default settings
PASSPHRASE_MODE="with"  # with or without
VERBOSE=false
CONTAINER_NAME="openvpn"  # Default container name
USE_DOCKER_COMPOSE=true
DOCKER_CMD="docker-compose"  # Default command
AUDIT_LOG=""  # Optional audit log file
ENABLE_AUDIT=false

# Track operation results for summary
CREATED_COUNT=0
FAILED_COUNT=0
EXISTING_COUNT=0
FAILED_CLIENTS=()
declare -a CREATED_CLIENTS
declare -a EXISTING_CLIENTS

# Function to display usage
usage() {
    cat << EOF
Usage: ./scripts/$0 [OPTIONS] CLIENT_NAME [CLIENT_NAME2 ...]

Create OpenVPN client certificates and configuration files.
Generated .ovpn files are saved to users/ folder.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -c, --container NAME    Container name (for plain docker, default: openvpn)
    -l, --log FILE          Log operations to audit file

EXAMPLES:
    # With docker-compose (default)
    ./scripts/$0 alice

    # With plain docker container named 'my-vpn'
    ./scripts/$0 -c my-vpn alice

    # Interactive mode (if no clients specified)
    ./scripts/$0
EOF
    exit 1
}

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

# Function to log audit events
audit_log() {
    local action=$1
    local clientname=$2
    local status=$3
    
    if [[ -z "$ENABLE_AUDIT" ]] || [[ "$ENABLE_AUDIT" != "true" ]]; then
        return
    fi
    
    if [[ -z "$AUDIT_LOG" ]]; then
        return
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user=$(whoami)
    local host=$(hostname)
    
    echo "$timestamp | $action | $clientname | $status | $user@$host" >> "$AUDIT_LOG"
}

# Function to verify certificate was created
verify_certificate() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn test -f "$cert_path" > /dev/null 2>&1
    else
        docker exec "$CONTAINER_NAME" test -f "$cert_path" > /dev/null 2>&1
    fi
}

# Function to get certificate expiry date
get_expiry_days() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2
    else
        docker exec "$CONTAINER_NAME" openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2
    fi
}

# Function to check if certificate expires soon
check_expiry_warning() {
    local clientname=$1
    local expiry_date=$(get_expiry_days "$clientname")
    
    if [[ -z "$expiry_date" ]]; then
        return
    fi
    
    # Convert expiry date to epoch seconds
    local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" "+%s" 2>/dev/null || echo "")
    if [[ -z "$expiry_epoch" ]]; then
        return
    fi
    
    local now_epoch=$(date "+%s")
    local days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    if [[ $days_until_expiry -lt 30 ]]; then
        echo "$days_until_expiry"
    else
        echo ""
    fi
}

# Function to verify .ovpn file was created
verify_ovpn_file() {
    local filename=$1
    if [[ ! -f "$filename" ]] || [[ ! -s "$filename" ]]; then
        return 1
    fi
    return 0
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
            log "Start the container with: docker run ... --name $CONTAINER_NAME ..."
            exit 1
        fi
    fi
}

# Function to create a single client
create_client() {
    local clientname=$1
    
    # Validate client name
    if [[ ! $clientname =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid client name: $clientname (use only alphanumeric, underscore, and dash)"
        return 1
    fi
    
    # Check if certificate already exists
    log "Checking if certificate already exists for: $clientname"
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        CERT_CHECK="docker-compose exec openvpn test -f /etc/openvpn/pki/issued/${clientname}.crt"
        EASYRSA_CMD="docker-compose run --rm openvpn easyrsa --batch build-client-full"
        GETCLIENT_CMD="docker-compose run --rm openvpn ovpn_getclient"
    else
        CERT_CHECK="docker exec $CONTAINER_NAME test -f /etc/openvpn/pki/issued/${clientname}.crt"
        EASYRSA_CMD="docker exec $CONTAINER_NAME bash -c 'export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH && cd /etc/openvpn && /usr/local/bin/easyrsa --batch build-client-full"
        GETCLIENT_CMD="docker exec $CONTAINER_NAME /usr/local/bin/ovpn_getclient"
    fi
    
    if eval "$CERT_CHECK" > /dev/null 2>&1; then
        log_warn "Certificate already exists for client: $clientname"
        log "Exporting existing configuration for client: $clientname"
        mkdir -p users
        eval "$GETCLIENT_CMD" "$clientname" > "users/${clientname}.ovpn"
        log "✓ Exported existing ${GREEN}users/${clientname}.ovpn${NC}"
        
        # Track result
        EXISTING_CLIENTS+=("$clientname")
        ((EXISTING_COUNT++))
        audit_log "EXPORT" "$clientname" "EXISTING"
        
        # Security warning for re-export
        echo ""
        echo -e "${YELLOW}ℹ️  This is a re-export of an existing certificate${NC}"
        echo -e "   File location: users/${clientname}.ovpn"
        echo ""
        return 0
    fi
    
    log "Creating certificate for client: $clientname"
    
    # Generate certificate
    # Note: Non-interactive scripts always use 'nopass' since passphrases require TTY interaction
    if $VERBOSE; then
        if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
            docker-compose run --rm openvpn easyrsa --batch build-client-full "$clientname" nopass
        else
            docker exec "$CONTAINER_NAME" bash -c "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH && cd /etc/openvpn && /usr/local/bin/easyrsa --batch build-client-full $clientname nopass"
        fi
    else
        if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
            docker-compose run --rm openvpn easyrsa --batch build-client-full "$clientname" nopass > /dev/null 2>&1
        else
            docker exec "$CONTAINER_NAME" bash -c "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH && cd /etc/openvpn && /usr/local/bin/easyrsa --batch build-client-full $clientname nopass" > /dev/null 2>&1
        fi
    fi
    
    if [[ "$PASSPHRASE_MODE" == "without" ]]; then
        log_warn "Certificate created without passphrase"
    else
        log_warn "Certificate created without passphrase (use -n flag for batch mode)"
    fi
    
    # Verify certificate was created
    if ! verify_certificate "$clientname"; then
        log_error "Certificate verification failed for $clientname"
        return 1
    fi
    log "✓ Certificate verified"
    
    # Export configuration
    log "Exporting configuration for client: $clientname"
    mkdir -p users
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose run --rm openvpn ovpn_getclient "$clientname" > "users/${clientname}.ovpn"
    else
        docker exec "$CONTAINER_NAME" /usr/local/bin/ovpn_getclient "$clientname" > "users/${clientname}.ovpn"
    fi
    
    # Verify .ovpn file was created
    if ! verify_ovpn_file "users/${clientname}.ovpn"; then
        log_error ".ovpn file creation failed for $clientname"
        FAILED_CLIENTS+=("$clientname")
        ((FAILED_COUNT++))
        audit_log "CREATE" "$clientname" "FAILED_EXPORT"
        return 1
    fi
    
    log "✓ Successfully created ${GREEN}users/${clientname}.ovpn${NC}"
    
    # Track successful creation
    CREATED_CLIENTS+=("$clientname")
    ((CREATED_COUNT++))
    audit_log "CREATE" "$clientname" "SUCCESS"
    
    # Check certificate expiry
    local days_until_expiry=$(check_expiry_warning "$clientname")
    if [[ -n "$days_until_expiry" ]]; then
        echo ""
        if [[ $days_until_expiry -le 0 ]]; then
            echo -e "${RED}⚠️  ALERT: Certificate has already EXPIRED!${NC}"
        elif [[ $days_until_expiry -lt 7 ]]; then
            echo -e "${RED}⚠️  ALERT: Certificate expires in $days_until_expiry days!${NC}"
        else
            echo -e "${YELLOW}⚠️  Certificate expires in $days_until_expiry days${NC}"
        fi
        echo ""
    fi
    
    # Security warnings
    echo ""
    echo -e "${YELLOW}┌────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC}          ${RED}⚠️  SECURITY WARNINGS${NC}                  ${YELLOW}│${NC}"
    echo -e "${YELLOW}├────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC} • File contains PRIVATE KEYS - keep secure!   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC} • Do NOT commit to version control            ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC} • Do NOT send via email or unencrypted        ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC} • Transfer via: SSH, GPG, encrypted storage   ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC} • Delete after client confirms receipt        ${YELLOW}│${NC}"
    echo -e "${YELLOW}├────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC} Recommended actions:                          ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}   chmod 600 users/${clientname}.ovpn              ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}   scp users/${clientname}.ovpn user@remote:/path/ ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}   rm users/${clientname}.ovpn                     ${YELLOW}│${NC}"
    echo -e "${YELLOW}└────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Function to display operation summary
show_summary() {
    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}      ${GREEN}✓ OPERATION SUMMARY${NC}                   ${BLUE}│${NC}"
    echo -e "${BLUE}├─────────────────────────────────────────────┤${NC}"
    
    if [[ $CREATED_COUNT -gt 0 ]]; then
        echo -e "${BLUE}│${NC} Created:  ${GREEN}${CREATED_COUNT}${NC}                                 ${BLUE}│${NC}"
        for client in "${CREATED_CLIENTS[@]}"; do
            echo -e "${BLUE}│${NC}   ✓ ${client}                                ${BLUE}│${NC}"
        done
    fi
    
    if [[ $EXISTING_COUNT -gt 0 ]]; then
        echo -e "${BLUE}│${NC} Re-exported:  ${YELLOW}${EXISTING_COUNT}${NC}                        ${BLUE}│${NC}"
        for client in "${EXISTING_CLIENTS[@]}"; do
            echo -e "${BLUE}│${NC}   ↻ ${client}                                ${BLUE}│${NC}"
        done
    fi
    
    if [[ $FAILED_COUNT -gt 0 ]]; then
        echo -e "${BLUE}│${NC} Failed:  ${RED}${FAILED_COUNT}${NC}                                ${BLUE}│${NC}"
        for client in "${FAILED_CLIENTS[@]}"; do
            echo -e "${BLUE}│${NC}   ✗ ${client}                                ${BLUE}│${NC}"
        done
    fi
    
    echo -e "${BLUE}├─────────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${NC} Total: $((CREATED_COUNT + EXISTING_COUNT + FAILED_COUNT))                                    ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────┘${NC}"
    
    if [[ -n "$ENABLE_AUDIT" ]] && [[ "$ENABLE_AUDIT" == "true" ]]; then
        log "Audit log: $AUDIT_LOG"
    fi
    echo ""
}

# Function to interactive mode
interactive_mode() {
    echo -e "\n${GREEN}=== OpenVPN Client Creation (Interactive Mode) ===${NC}"
    echo "Enter client names (one per line). Type 'done' when finished:"
    echo ""
    
    local clients=()
    while true; do
        read -p "Client name (or 'done'): " clientname
        
        if [[ "$clientname" == "done" ]]; then
            break
        fi
        
        if [[ -z "$clientname" ]]; then
            log_warn "Client name cannot be empty"
            continue
        fi
        
        clients+=("$clientname")
    done
    
    if [[ ${#clients[@]} -eq 0 ]]; then
        log_error "No clients specified"
        exit 1
    fi
    
    # Confirm passphrase mode
    read -p "Create clients with passphrases? (y/n, default: y): " use_pass
    if [[ "$use_pass" == "n" || "$use_pass" == "N" ]]; then
        PASSPHRASE_MODE="without"
        log_warn "Creating without passphrases (not recommended)"
    fi
    
    # Create all clients
    echo ""
    for client in "${clients[@]}"; do
        create_client "$client"
        echo ""
    done
    
    # Display operation summary
    show_summary
}

# Main script
main() {
    # Parse arguments
    local clients=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -n|--no-pass)
                PASSPHRASE_MODE="without"
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
            -l|--log)
                AUDIT_LOG="$2"
                ENABLE_AUDIT=true
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                clients+=("$1")
                shift
                ;;
        esac
    done
    
    # Auto-detect docker-compose vs plain docker if not specified
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if ! command -v docker-compose &> /dev/null; then
            log_warn "docker-compose not found. Attempting to use plain docker with container: $CONTAINER_NAME"
            USE_DOCKER_COMPOSE=false
        else
            # Change to project root directory for docker-compose
            cd "$(dirname "$0")/.." || exit 1
        fi
    fi
    
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        exit 1
    fi
    
    # Check if container is running
    check_container
    
    # If no clients specified, use interactive mode
    if [[ ${#clients[@]} -eq 0 ]]; then
        interactive_mode
        return 0
    fi
    
    # Confirm settings
    echo ""
    log "Creating ${#clients[@]} client(s)"
    log "Passphrase mode: $PASSPHRASE_MODE"
    echo ""
    
    # Create all clients
    for client in "${clients[@]}"; do
        create_client "$client"
        echo ""
    done
    
    # Display operation summary
    show_summary
    
    # Next steps
    log "Next steps:"
    log "1. Distribute the .ovpn files from users/ folder to clients securely"
    log "2. Clients can import them into OpenVPN Connect app"
    log "3. To revoke a certificate: ./scripts/revoke-clients.sh <clientname>"
    echo ""
}

# Run main function
main "$@"
