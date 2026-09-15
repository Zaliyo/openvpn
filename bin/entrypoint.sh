#!/bin/bash
# OpenVPN Entrypoint
# Handles script routing and environment setup

set -e

# Prioritize compiled OpenSSL 3.6.4 over system libraries
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export helper functions and variables
export OPENVPN_DIR="/etc/openvpn"
export EASYRSA_DIR="${OPENVPN_DIR}/easy-rsa"
export EASYRSA="/usr/local/bin/easyrsa"
export EASYRSA_PKI="${OPENVPN_DIR}/pki"

# Create easy-rsa symlink if it doesn't exist
if [[ ! -d "${EASYRSA_DIR}" && ! -L "${EASYRSA_DIR}" ]]; then
    mkdir -p "${EASYRSA_DIR}"
    cd "${EASYRSA_DIR}"
    /usr/local/bin/easyrsa --batch init-pki || true
fi

# Handle commands
case "$1" in
    ovpn_run)
        exec /usr/local/bin/ovpn_run
        ;;
    ovpn_genconfig)
        exec /usr/local/bin/ovpn_genconfig "${@:2}"
        ;;
    ovpn_initpki)
        exec /usr/local/bin/ovpn_initpki
        ;;
    ovpn_getclient)
        exec /usr/local/bin/ovpn_getclient "${@:2}"
        ;;
    ovpn_revokeclient)
        exec /usr/local/bin/ovpn_revokeclient "${@:2}"
        ;;
    easyrsa)
        exec /usr/local/bin/easyrsa "${@:2}"
        ;;
    *)
        # If no special command, pass everything to the command
        exec "$@"
        ;;
esac
