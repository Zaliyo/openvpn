#!/bin/bash

##############################################################################
# OpenVPN Client List Script
# Display all existing client certificates and their status
##############################################################################
#
# EXAMPLES:
#
#   # List all clients
#   ./scripts/list-clients.sh
#
#   # List with certificate details
#   ./scripts/list-clients.sh -v
#
#   # List with expiry dates
#   ./scripts/list-clients.sh -e
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
SHOW_EXPIRY=false
SHOW_DETAILS=false
CONTAINER_NAME="openvpn"
USE_DOCKER_COMPOSE=true

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
Usage: ./scripts/$0 [OPTIONS]

List all OpenVPN client certificates and their status.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Show certificate details (subject, issuer, etc)
    -e, --expiry            Show certificate expiry dates
    -d, --details           Show detailed cert info (fingerprint, serial, etc)
    -c, --container NAME    Container name (for plain docker, default: openvpn)

EXAMPLES:
    # Simple list
    ./scripts/$0

    # With expiry dates
    ./scripts/$0 -e

    # Full details
    ./scripts/$0 -v -e -d
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

# Function to get certificate info
get_cert_info() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if ! docker-compose exec openvpn test -f "$cert_path" 2>/dev/null; then
            return 1
        fi
    else
        if ! docker exec "$CONTAINER_NAME" test -f "$cert_path" 2>/dev/null; then
            return 1
        fi
    fi
    
    return 0
}

# Function to get expiry date
get_expiry_date() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2
    else
        docker exec "$CONTAINER_NAME" openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2
    fi
}

# Function to check if certificate is revoked
is_revoked() {
    local clientname=$1
    local crl_path="/etc/openvpn/pki/crl.pem"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if docker-compose exec openvpn openssl crl -in "$crl_path" -text -noout 2>/dev/null | grep -q "$clientname"; then
            echo "REVOKED"
        else
            echo "ACTIVE"
        fi
    else
        if docker exec "$CONTAINER_NAME" openssl crl -in "$crl_path" -text -noout 2>/dev/null | grep -q "$clientname"; then
            echo "REVOKED"
        else
            echo "ACTIVE"
        fi
    fi
}

# Function to get certificate fingerprint
get_fingerprint() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn openssl x509 -in "$cert_path" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2
    else
        docker exec "$CONTAINER_NAME" openssl x509 -in "$cert_path" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2
    fi
}

# Function to get certificate serial number
get_serial() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn openssl x509 -in "$cert_path" -noout -serial 2>/dev/null | cut -d= -f2
    else
        docker exec "$CONTAINER_NAME" openssl x509 -in "$cert_path" -noout -serial 2>/dev/null | cut -d= -f2
    fi
}

# Function to get key usage
get_key_usage() {
    local clientname=$1
    local cert_path="/etc/openvpn/pki/issued/${clientname}.crt"
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep "X509v3 Key Usage" -A 1 | tail -1 | xargs
    else
        docker exec "$CONTAINER_NAME" openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep "X509v3 Key Usage" -A 1 | tail -1 | xargs
    fi
}

# Main script
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -e|--expiry)
                SHOW_EXPIRY=true
                shift
                ;;
            -d|--details)
                SHOW_DETAILS=true
                shift
                ;;
            -c|--container)
                CONTAINER_NAME="$2"
                USE_DOCKER_COMPOSE=false
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
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
    
    # Get list of clients from PKI directory
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        CLIENTS=$(docker-compose exec openvpn ls /etc/openvpn/pki/issued/ 2>/dev/null | grep -v "server" | sed 's/.crt$//' || true)
    else
        CLIENTS=$(docker exec "$CONTAINER_NAME" ls /etc/openvpn/pki/issued/ 2>/dev/null | grep -v "server" | sed 's/.crt$//' || true)
    fi
    
    if [[ -z "$CLIENTS" ]]; then
        log_warn "No clients found"
        exit 0
    fi
    
    # Display header
    echo ""
    echo -e "${BLUE}=== OpenVPN Clients ===${NC}"
    echo ""
    
    # Display client list
    for client in $CLIENTS; do
        if get_cert_info "$client"; then
            STATUS=$(is_revoked "$client")
            
            if [[ "$STATUS" == "REVOKED" ]]; then
                STATUS_COLOR="${RED}${STATUS}${NC}"
            else
                STATUS_COLOR="${GREEN}${STATUS}${NC}"
            fi
            
            # Basic info
            printf "%-20s %b\n" "$client" "$STATUS_COLOR"
            
            # Expiry info
            if [[ "$SHOW_EXPIRY" == "true" ]]; then
                EXPIRY=$(get_expiry_date "$client")
                printf "  └─ Expires: %s\n" "$EXPIRY"
            fi
            
            # Verbose info
            if [[ "$VERBOSE" == "true" ]]; then
                if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
                    SUBJECT=$(docker-compose exec openvpn openssl x509 -in "/etc/openvpn/pki/issued/${client}.crt" -noout -subject 2>/dev/null | sed 's/subject=/  └─ Subject: /')
                else
                    SUBJECT=$(docker exec "$CONTAINER_NAME" openssl x509 -in "/etc/openvpn/pki/issued/${client}.crt" -noout -subject 2>/dev/null | sed 's/subject=/  └─ Subject: /')
                fi
                echo "$SUBJECT"
            fi
            
            # Detailed info
            if [[ "$SHOW_DETAILS" == "true" ]]; then
                FINGERPRINT=$(get_fingerprint "$client")
                SERIAL=$(get_serial "$client")
                KEY_USAGE=$(get_key_usage "$client")
                
                printf "  └─ Fingerprint (SHA256): %s\n" "$FINGERPRINT"
                printf "     Serial: %s\n" "$SERIAL"
                if [[ -n "$KEY_USAGE" ]]; then
                    printf "     Key Usage: %s\n" "$KEY_USAGE"
                fi
            fi
        fi
    done
    
    echo ""
    log "Total clients: $(echo "$CLIENTS" | wc -w)"
    echo ""
}

# Run main function
main "$@"
