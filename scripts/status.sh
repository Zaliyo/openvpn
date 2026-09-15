#!/bin/bash

##############################################################################
# OpenVPN Status Check Script
# Display overall health and status of OpenVPN infrastructure
##############################################################################
#
# EXAMPLES:
#
#   # Quick status check
#   ./scripts/status.sh
#
#   # With details
#   ./scripts/status.sh -v
#
#   # With docker
#   ./scripts/status.sh -c my-vpn
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

Check overall health and status of OpenVPN infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Show additional details
    -c, --container NAME    Container name (for plain docker, default: openvpn)

EXAMPLES:
    # Quick status
    ./scripts/$0

    # Full details
    ./scripts/$0 -v
EOF
    exit 1
}

# Function to check if container is running
check_container_status() {
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        if docker-compose ps openvpn 2>/dev/null | grep -q "Up"; then
            echo "UP"
            # Check health
            if docker-compose ps openvpn | grep -q "healthy"; then
                echo "HEALTHY"
                return 0
            else
                echo "UP_UNHEALTHY"
                return 1
            fi
        else
            echo "DOWN"
            return 1
        fi
    else
        if docker ps | grep -q "$CONTAINER_NAME"; then
            echo "UP"
            return 0
        else
            echo "DOWN"
            return 1
        fi
    fi
}

# Function to check PKI initialization
check_pki_initialized() {
    local pki_path="/etc/openvpn/pki"
    local required_files=("ca.crt" "server.crt" "server.key" "dh.pem" "ta.key" "crl.pem")
    
    for file in "${required_files[@]}"; do
        if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
            if ! docker-compose exec openvpn test -f "$pki_path/$file" > /dev/null 2>&1; then
                echo "MISSING_$file"
                return 1
            fi
        else
            if ! docker exec "$CONTAINER_NAME" test -f "$pki_path/$file" > /dev/null 2>&1; then
                echo "MISSING_$file"
                return 1
            fi
        fi
    done
    
    echo "INITIALIZED"
    return 0
}

# Function to count clients
count_clients() {
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn bash -c 'ls /etc/openvpn/pki/issued/ 2>/dev/null | grep -v "^server" | wc -l' 2>/dev/null || echo "0"
    else
        docker exec "$CONTAINER_NAME" bash -c 'ls /etc/openvpn/pki/issued/ 2>/dev/null | grep -v "^server" | wc -l' 2>/dev/null || echo "0"
    fi
}

# Function to count revoked clients
count_revoked() {
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn bash -c 'openssl crl -in /etc/openvpn/pki/crl.pem -text -noout 2>/dev/null | grep "Subject:" | wc -l' 2>/dev/null || echo "0"
    else
        docker exec "$CONTAINER_NAME" bash -c 'openssl crl -in /etc/openvpn/pki/crl.pem -text -noout 2>/dev/null | grep "Subject:" | wc -l' 2>/dev/null || echo "0"
    fi
}

# Function to check certificate expiry
check_cert_expiry() {
    local cert_path=$1
    local days_warning=$2
    
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        local enddate=$(docker-compose exec openvpn openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    else
        local enddate=$(docker exec "$CONTAINER_NAME" openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    fi
    
    if [[ -z "$enddate" ]]; then
        return 1
    fi
    
    local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$enddate" "+%s" 2>/dev/null || echo "")
    if [[ -z "$expiry_epoch" ]]; then
        return 1
    fi
    
    local now_epoch=$(date "+%s")
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    if [[ $days_left -lt $days_warning ]]; then
        echo "$days_left"
        return 0
    fi
    
    return 1
}

# Function to check OpenVPN version
get_openvpn_version() {
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn /usr/local/sbin/openvpn --version 2>/dev/null | head -1 || echo "Unknown"
    else
        docker exec "$CONTAINER_NAME" /usr/local/sbin/openvpn --version 2>/dev/null | head -1 || echo "Unknown"
    fi
}

# Function to check OpenSSL version
get_openssl_version() {
    if [[ "$USE_DOCKER_COMPOSE" == "true" ]]; then
        docker-compose exec openvpn /usr/local/bin/openssl version 2>/dev/null || echo "Unknown"
    else
        docker exec "$CONTAINER_NAME" /usr/local/bin/openssl version 2>/dev/null || echo "Unknown"
    fi
}

# Main function
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
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}     OpenVPN Infrastructure Status${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
    
    # Container status
    echo -ne "${BLUE}Container Status:${NC}          "
    CONTAINER_STATUS=$(check_container_status)
    if [[ "$CONTAINER_STATUS" == "UP" ]] || [[ "$CONTAINER_STATUS" == "HEALTHY" ]]; then
        echo -e "${GREEN}✓ $CONTAINER_STATUS${NC}"
    elif [[ "$CONTAINER_STATUS" == "UP_UNHEALTHY" ]]; then
        echo -e "${YELLOW}⚠ $CONTAINER_STATUS${NC}"
    else
        echo -e "${RED}✗ $CONTAINER_STATUS${NC}"
        log "Container not running - cannot check other components"
        echo ""
        exit 1
    fi
    
    # PKI status
    echo -ne "${BLUE}PKI Initialization:${NC}        "
    PKI_STATUS=$(check_pki_initialized)
    if [[ "$PKI_STATUS" == "INITIALIZED" ]]; then
        echo -e "${GREEN}✓ $PKI_STATUS${NC}"
    else
        echo -e "${RED}✗ $PKI_STATUS${NC}"
    fi
    
    # Client statistics
    echo -ne "${BLUE}Active Clients:${NC}            "
    ACTIVE_COUNT=$(count_clients)
    echo -e "${GREEN}$ACTIVE_COUNT${NC}"
    
    echo -ne "${BLUE}Revoked Clients:${NC}           "
    REVOKED_COUNT=$(count_revoked)
    echo -e "${YELLOW}$REVOKED_COUNT${NC}"
    
    # Verbose mode
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo -e "${BLUE}Version Information:${NC}"
        echo -n "  OpenVPN: "
        get_openvpn_version
        echo -n "  OpenSSL: "
        get_openssl_version
        
        # Certificate expiry check
        echo ""
        echo -e "${BLUE}Certificate Expiry:${NC}"
        
        SERVER_EXPIRY=$(check_cert_expiry "/etc/openvpn/pki/server.crt" 30)
        if [[ -n "$SERVER_EXPIRY" ]]; then
            echo -e "  Server cert: ${RED}Expires in $SERVER_EXPIRY days${NC}"
        else
            echo -e "  Server cert: ${GREEN}OK${NC}"
        fi
        
        CA_EXPIRY=$(check_cert_expiry "/etc/openvpn/pki/ca.crt" 30)
        if [[ -n "$CA_EXPIRY" ]]; then
            echo -e "  CA cert: ${RED}Expires in $CA_EXPIRY days${NC}"
        else
            echo -e "  CA cert: ${GREEN}OK${NC}"
        fi
    fi
    
    echo ""
    
    # Summary
    if [[ "$CONTAINER_STATUS" == "HEALTHY" ]] && [[ "$PKI_STATUS" == "INITIALIZED" ]]; then
        echo -e "${GREEN}✓ All systems operational${NC}"
    else
        echo -e "${YELLOW}⚠ Some components need attention${NC}"
    fi
    
    echo ""
}

# Run main function
main "$@"
