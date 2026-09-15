#!/bin/bash

##############################################################################
# OpenVPN Certificate Renewal Script  
# Renew client certificates that are expiring soon
##############################################################################
#
# EXAMPLES:
#
#   # Show certificates expiring in 30 days
#   ./scripts/renew-clients.sh
#
#   # Renew specific client
#   ./scripts/renew-clients.sh alice
#
#   # Force renew (ignore expiry date)
#   ./scripts/renew-clients.sh -f alice
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
VERBOSE=false
CONTAINER_NAME="openvpn"
USE_DOCKER_COMPOSE=true
DAYS_WARNING=30
FORCE_RENEW=false
AUDIT_LOG=""
ENABLE_AUDIT=false

# Track results
RENEWED_COUNT=0
FAILED_COUNT=0
declare -a RENEWED_CLIENTS
declare -a FAILED_CLIENTS
declare -a EXPIRING_CLIENTS

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

# Function to display usage
usage() {
    cat << EOF
Usage: ./scripts/$0 [OPTIONS] [CLIENT_NAME]

Renew client certificates that are expiring soon or manually renew specific clients.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -f, --force             Force renewal regardless of expiry date
    -d, --days NUM          Warning threshold in days (default: 30)
    -c, --container NAME    Container name (for plain docker, default: openvpn)
    -l, --log FILE          Log operations to audit file

EXAMPLES:
    # List certificates expiring in 30 days
    ./scripts/$0

    # Renew specific client
    ./scripts/$0 alice

    # Show certificates expiring in 7 days
    ./scripts/$0 -d 7

    # Force renew alice
    ./scripts/$0 -f alice
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

# Function to get certificate expiry days
get_expiry_days() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        local enddate=$(docker-compose exec openvpn openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    else
        local enddate=$(docker exec "$CONTAINER_NAME" openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    fi
    
    if [[ -z "$enddate" ]]; then
        echo ""
        return
    fi
    
    local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$enddate" "+%s" 2>/dev/null || echo "")
    if [[ -z "$expiry_epoch" ]]; then
        echo ""
        return
    fi
    
    local now_epoch=$(date "+%s")
    echo "$(( (expiry_epoch - now_epoch) / 86400 ))"
}

# Function to find all client certificates
list_all_clients() {
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn ls /etc/openvpn/pki/issued/ 2>/dev/null | grep -v "^server" | sed 's/.crt$//' || echo ""
    else
        docker exec "$CONTAINER_NAME" ls /etc/openvpn/pki/issued/ 2>/dev/null | grep -v "^server" | sed 's/.crt$//' || echo ""
    fi
}

# Function to renew a single client
renew_client() {
    local clientname=$1
    local force=$2
    
    # Validate client name
    if [[ ! $clientname =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid client name: $clientname"
        FAILED_CLIENTS+=("$clientname")
        ((FAILED_COUNT++))
        return 1
    fi
    
    # Check if certificate exists
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if ! docker-compose exec openvpn test -f "/etc/openvpn/pki/issued/${clientname}.crt" > /dev/null 2>&1; then
            log_error "Certificate not found for client: $clientname"
            FAILED_CLIENTS+=("$clientname")
            ((FAILED_COUNT++))
            audit_log "RENEW" "$clientname" "NOT_FOUND"
            return 1
        fi
    else
        if ! docker exec "$CONTAINER_NAME" test -f "/etc/openvpn/pki/issued/${clientname}.crt" > /dev/null 2>&1; then
            log_error "Certificate not found for client: $clientname"
            FAILED_CLIENTS+=("$clientname")
            ((FAILED_COUNT++))
            audit_log "RENEW" "$clientname" "NOT_FOUND"
            return 1
        fi
    fi
    
    # Check expiry unless forcing
    if [[ "$force" != "true" ]]; then
        local days_left=$(get_expiry_days "$clientname")
        if [[ -n "$days_left" ]] && [[ $days_left -gt $DAYS_WARNING ]]; then
            log_warn "Certificate for $clientname expires in $days_left days (not yet in renewal window)"
            return 1
        fi
    fi
    
    log "Renewing certificate for client: $clientname"
    
    # Revoke old certificate
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose run --rm openvpn easyrsa --batch revoke "$clientname" > /dev/null 2>&1 || true
    else
        docker exec "$CONTAINER_NAME" bash -c "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH && cd /etc/openvpn && /usr/local/bin/easyrsa --batch revoke $clientname" > /dev/null 2>&1 || true
    fi
    
    log "Revoking old certificate"
    
    # Generate new certificate
    if [[ "$VERBOSE" == "true" ]]; then
        if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
            docker-compose run --rm openvpn easyrsa --batch --no-inline build-client-full "$clientname" nopass
        else
            docker exec "$CONTAINER_NAME" bash -c "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH && cd /etc/openvpn && /usr/local/bin/easyrsa --batch --no-inline build-client-full $clientname nopass"
        fi
    else
        if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
            docker-compose run --rm openvpn easyrsa --batch --no-inline build-client-full "$clientname" nopass > /dev/null 2>&1
        else
            docker exec "$CONTAINER_NAME" bash -c "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH && cd /etc/openvpn && /usr/local/bin/easyrsa --batch --no-inline build-client-full $clientname nopass" > /dev/null 2>&1
        fi
    fi
    
    log "Generating new certificate"
    
    # Export configuration
    mkdir -p users
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose run --rm openvpn ovpn_getclient "$clientname" > "users/${clientname}.ovpn"
    else
        docker exec "$CONTAINER_NAME" /usr/local/bin/ovpn_getclient "$clientname" > "users/${clientname}.ovpn"
    fi
    
    log "✓ Successfully renewed ${GREEN}users/${clientname}.ovpn${NC}"
    
    RENEWED_CLIENTS+=("$clientname")
    ((RENEWED_COUNT++))
    audit_log "RENEW" "$clientname" "SUCCESS"
    
    # Security warning
    echo ""
    echo -e "${YELLOW}⚠️  Updated configuration saved to: ${clientname}.ovpn${NC}"
    echo -e "   Distribute securely to client: chmod 600 ${clientname}.ovpn && scp ..."
    echo ""
}

# Function to display operation summary
show_summary() {
    echo ""
    echo -e "${GREEN}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│${NC}      ${GREEN}✓ RENEWAL SUMMARY${NC}                     ${GREEN}│${NC}"
    echo -e "${GREEN}├─────────────────────────────────────────────┤${NC}"
    
    if [[ $RENEWED_COUNT -gt 0 ]]; then
        echo -e "${GREEN}│${NC} Renewed:  ${GREEN}${RENEWED_COUNT}${NC}                               ${GREEN}│${NC}"
        for client in "${RENEWED_CLIENTS[@]}"; do
            echo -e "${GREEN}│${NC}   ✓ ${client}                                ${GREEN}│${NC}"
        done
    fi
    
    if [[ $FAILED_COUNT -gt 0 ]]; then
        echo -e "${GREEN}│${NC} Failed:  ${RED}${FAILED_COUNT}${NC}                                ${GREEN}│${NC}"
        for client in "${FAILED_CLIENTS[@]}"; do
            echo -e "${GREEN}│${NC}   ✗ ${client}                                ${GREEN}│${NC}"
        done
    fi
    
    echo -e "${GREEN}├─────────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}│${NC} Total: $((RENEWED_COUNT + FAILED_COUNT))                                    ${GREEN}│${NC}"
    echo -e "${GREEN}└─────────────────────────────────────────────┘${NC}"
    
    if [[ -n "$ENABLE_AUDIT" ]] && [[ "$ENABLE_AUDIT" == "true" ]]; then
        log "Audit log: $AUDIT_LOG"
    fi
    echo ""
}

# Main function
main() {
    # Parse arguments
    local clients=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE_RENEW=true
                shift
                ;;
            -d|--days)
                DAYS_WARNING="$2"
                shift 2
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
    
    # Check if container is running
    check_container
    
    # If specific clients provided, renew them
    if [[ ${#clients[@]} -gt 0 ]]; then
        echo ""
        log "Renewing ${#clients[@]} client certificate(s)"
        echo ""
        
        for client in "${clients[@]}"; do
            renew_client "$client" "$FORCE_RENEW"
            echo ""
        done
        
        show_summary
        return 0
    fi
    
    # Otherwise, find and list expiring certificates
    log "Checking for certificates expiring in $DAYS_WARNING days..."
    echo ""
    
    local all_clients=$(list_all_clients)
    
    if [[ -z "$all_clients" ]]; then
        log_warn "No client certificates found"
        echo ""
        exit 0
    fi
    
    echo -e "${BLUE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}   Certificates Expiring in $DAYS_WARNING Days          ${BLUE}│${NC}"
    echo -e "${BLUE}├─────────────────────────────────────────────┤${NC}"
    
    local found_any=false
    for client in $all_clients; do
        local days_left=$(get_expiry_days "$client")
        
        if [[ -n "$days_left" ]] && [[ $days_left -le $DAYS_WARNING ]]; then
            found_any=true
            
            if [[ $days_left -le 0 ]]; then
                echo -e "${BLUE}│${NC} ${RED}✗ $client${NC}${BLUE} (EXPIRED - ${days_left} days)${NC}      ${BLUE}│${NC}"
                EXPIRING_CLIENTS+=("$client")
            elif [[ $days_left -lt 7 ]]; then
                echo -e "${BLUE}│${NC} ${YELLOW}⚠ $client${NC}${BLUE} (EXPIRING - ${days_left} days)${NC}     ${BLUE}│${NC}"
                EXPIRING_CLIENTS+=("$client")
            else
                echo -e "${BLUE}│${NC} ${GREEN}↻ $client${NC}${BLUE} (RENEW SOON - ${days_left} days)${NC}  ${BLUE}│${NC}"
                EXPIRING_CLIENTS+=("$client")
            fi
        fi
    done
    
    if [[ "$found_any" == "false" ]]; then
        echo -e "${BLUE}│${NC} ${GREEN}No certificates expiring soon${NC}            ${BLUE}│${NC}"
    fi
    
    echo -e "${BLUE}└─────────────────────────────────────────────┘${NC}"
    echo ""
    
    if [[ ${#EXPIRING_CLIENTS[@]} -gt 0 ]]; then
        log "To renew, run:"
        log "  ./scripts/renew-clients.sh ${EXPIRING_CLIENTS[0]}"
        echo ""
    fi
}

# Run main function
main "$@"
