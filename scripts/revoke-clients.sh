#!/bin/bash

##############################################################################
# OpenVPN Client Revocation Script
# Automates the process of revoking OpenVPN client certificates
##############################################################################
#
# EXAMPLES:
#
#   # Revoke a single client
#   ./scripts/revoke-clients.sh alice
#
#   # Revoke multiple clients
#   ./scripts/revoke-clients.sh alice bob charlie
#
#   # Revoke with verbose output
#   ./scripts/revoke-clients.sh -v alice bob
#
#   # Interactive mode (prompts for client names)
#   ./scripts/revoke-clients.sh
#
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default settings
VERBOSE=false
CONTAINER_NAME="openvpn"  # Default container name
USE_DOCKER_COMPOSE=true
AUDIT_LOG=""  # Optional audit log file
ENABLE_AUDIT=false

# Track operation results for summary
REVOKED_COUNT=0
FAILED_COUNT=0
NOT_FOUND_COUNT=0
FAILED_CLIENTS=()
declare -a REVOKED_CLIENTS
declare -a NOT_FOUND_CLIENTS

# Function to display usage
usage() {
    cat << EOF
Usage: ./scripts/$0 [OPTIONS] CLIENT_NAME [CLIENT_NAME2 ...]

Revoke OpenVPN client certificates.

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

# Function to revoke a single client
revoke_client() {
    local clientname=$1
    
    # Validate client name
    if [[ ! $clientname =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid client name: $clientname (use only alphanumeric, underscore, and dash)"
        return 1
    fi
    
    # Check if certificate exists
    log "Checking if certificate exists for: $clientname"
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if ! docker-compose exec openvpn test -f "/etc/openvpn/pki/issued/${clientname}.crt" > /dev/null 2>&1; then
            log_error "Certificate not found for client: $clientname"
            NOT_FOUND_CLIENTS+=("$clientname")
            ((NOT_FOUND_COUNT++))
            audit_log "REVOKE" "$clientname" "NOT_FOUND"
            return 1
        fi
    else
        if ! docker exec "$CONTAINER_NAME" test -f "/etc/openvpn/pki/issued/${clientname}.crt" > /dev/null 2>&1; then
            log_error "Certificate not found for client: $clientname"
            NOT_FOUND_CLIENTS+=("$clientname")
            ((NOT_FOUND_COUNT++))
            audit_log "REVOKE" "$clientname" "NOT_FOUND"
            return 1
        fi
    fi
    
    log_warn "Revoking certificate for client: $clientname"
    
    # Revoke certificate
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if $VERBOSE; then
            docker-compose run --rm openvpn ovpn_revokeclient "$clientname"
        else
            docker-compose run --rm openvpn ovpn_revokeclient "$clientname" > /dev/null 2>&1
        fi
    else
        if $VERBOSE; then
            docker exec "$CONTAINER_NAME" /usr/local/bin/ovpn_revokeclient "$clientname"
        else
            docker exec "$CONTAINER_NAME" /usr/local/bin/ovpn_revokeclient "$clientname" > /dev/null 2>&1
        fi
    fi
    
    log "✓ Successfully revoked ${RED}${clientname}${NC} (connection blocked)"
    
    # Track successful revocation
    REVOKED_CLIENTS+=("$clientname")
    ((REVOKED_COUNT++))
    audit_log "REVOKE" "$clientname" "SUCCESS"
}

# Function to display operation summary
show_summary() {
    echo ""
    echo -e "${RED}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${RED}│${NC}      ${GREEN}✓ REVOCATION SUMMARY${NC}                  ${RED}│${NC}"
    echo -e "${RED}├─────────────────────────────────────────────┤${NC}"
    
    if [[ $REVOKED_COUNT -gt 0 ]]; then
        echo -e "${RED}│${NC} Revoked:  ${RED}${REVOKED_COUNT}${NC}                               ${RED}│${NC}"
        for client in "${REVOKED_CLIENTS[@]}"; do
            echo -e "${RED}│${NC}   ✓ ${client}                                ${RED}│${NC}"
        done
    fi
    
    if [[ $NOT_FOUND_COUNT -gt 0 ]]; then
        echo -e "${RED}│${NC} Not Found:  ${YELLOW}${NOT_FOUND_COUNT}${NC}                          ${RED}│${NC}"
        for client in "${NOT_FOUND_CLIENTS[@]}"; do
            echo -e "${RED}│${NC}   ✗ ${client}                                ${RED}│${NC}"
        done
    fi
    
    if [[ $FAILED_COUNT -gt 0 ]]; then
        echo -e "${RED}│${NC} Failed:  ${RED}${FAILED_COUNT}${NC}                                ${RED}│${NC}"
        for client in "${FAILED_CLIENTS[@]}"; do
            echo -e "${RED}│${NC}   ✗ ${client}                                ${RED}│${NC}"
        done
    fi
    
    echo -e "${RED}├─────────────────────────────────────────────┤${NC}"
    echo -e "${RED}│${NC} Total: $((REVOKED_COUNT + NOT_FOUND_COUNT + FAILED_COUNT))                                    ${RED}│${NC}"
    echo -e "${RED}└─────────────────────────────────────────────┘${NC}"
    
    if [[ -n "$ENABLE_AUDIT" ]] && [[ "$ENABLE_AUDIT" == "true" ]]; then
        log "Audit log: $AUDIT_LOG"
    fi
    echo ""
}

# Function to interactive mode
interactive_mode() {
    echo -e "\n${RED}=== OpenVPN Client Revocation (Interactive Mode) ===${NC}"
    echo "Enter client names to revoke (one per line). Type 'done' when finished:"
    echo ""
    
    local clients=()
    while true; do
        read -p "Client name to revoke (or 'done'): " clientname
        
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
        log_error "No clients specified for revocation"
        exit 1
    fi
    
    # Confirm revocation
    echo ""
    echo -e "${RED}WARNING: You are about to revoke the following certificates:${NC}"
    for client in "${clients[@]}"; do
        echo "  - $client"
    done
    echo ""
    read -p "Are you sure you want to revoke these clients? (type 'yes' to confirm): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Revocation cancelled"
        exit 0
    fi
    
    # Revoke all clients
    echo ""
    for client in "${clients[@]}"; do
        revoke_client "$client"
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
    log_warn "Revoking ${#clients[@]} client(s)"
    echo ""
    
    # Revoke all clients
    for client in "${clients[@]}"; do
        revoke_client "$client"
        echo ""
    done
    
    # Display operation summary
    show_summary
    
    log "These clients can NO LONGER connect to the VPN"
    log "To restore access, run: ./scripts/create-clients.sh <clientname>"
    echo ""
}

# Run main function
main "$@"
