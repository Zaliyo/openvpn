#!/bin/bash
set -e

# OpenVPN Server Entrypoint Script
# Routes to different commands based on arguments

case "${1:-ovpn_run}" in
    ovpn_run)
        # Start OpenVPN server
        /usr/local/sbin/openvpn /etc/openvpn/openvpn.conf
        ;;
    easyrsa)
        # EasyRSA commands
        shift
        /usr/local/bin/easyrsa "$@"
        ;;
    create-clients)
        # Create new VPN client
        shift
        /usr/local/bin/ovpn_create_clients "$@"
        ;;
    revoke-clients)
        # Revoke VPN client certificate
        shift
        /usr/local/bin/ovpn_revoke_clients "$@"
        ;;
    list-clients)
        # List all VPN clients
        /usr/local/bin/ovpn_list_clients
        ;;
    status)
        # Check server status
        /usr/local/bin/ovpn_status
        ;;
    renew-clients)
        # Renew client certificate
        shift
        /usr/local/bin/ovpn_renew_clients "$@"
        ;;
    backup-pki)
        # Backup PKI (certificates, keys, CRL)
        /usr/local/bin/ovpn_backup_pki
        ;;
    *)
        echo "OpenVPN Server - Available commands:"
        echo "  ovpn_run               - Start OpenVPN server (default)"
        echo "  easyrsa <args>         - EasyRSA PKI management"
        echo "  create-clients <name>  - Create new VPN client"
        echo "  revoke-clients <name>  - Revoke VPN client certificate"
        echo "  list-clients           - List all VPN clients"
        echo "  status                 - Check server status"
        echo "  renew-clients <name>   - Renew client certificate"
        echo "  backup-pki             - Backup PKI (encrypted)"
        echo ""
        echo "Examples:"
        echo "  docker exec openvpn create-clients alice"
        echo "  docker exec openvpn list-clients"
        echo "  docker exec openvpn status"
        exit 1
        ;;
esac
