#!/bin/bash
set -e

# OpenVPN Server Entrypoint Script
# Routes to different commands based on arguments

case "${1:-ovpn_run}" in
    ovpn_run)
        # Start OpenVPN server
        # Check if PKI is initialized
        if [ ! -f "/etc/openvpn/pki/ca.crt" ] || [ ! -f "/etc/openvpn/pki/issued/server.crt" ]; then
            echo "❌ ERROR: PKI not initialized!"
            echo ""
            echo "Initialize PKI first with:"
            echo "  docker exec openvpn easyrsa init-pki"
            echo "  docker exec openvpn easyrsa build-ca nopass"
            echo "  docker exec openvpn easyrsa gen-req server nopass"
            echo "  docker exec openvpn easyrsa sign-req server server"
            echo "  docker exec openvpn easyrsa gen-dh"
            echo "  docker exec openvpn gen-key ta"
            echo ""
            echo "Or use convenience command:"
            echo "  docker exec openvpn ovpn_init_pki"
            echo ""
            echo "⏳ Container waiting for PKI initialization..."
            # Keep container alive
            tail -f /dev/null
        fi
        
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
    init-pki)
        # Initialize PKI (first-time setup)
        /usr/local/bin/ovpn_init_pki
        ;;
    *)
        echo "OpenVPN Server - Available commands:"
        echo "  ovpn_run               - Start OpenVPN server (default)"
        echo "  init-pki               - Initialize PKI (first-time setup only)"
        echo "  easyrsa <args>         - EasyRSA PKI management"
        echo "  create-clients <name>  - Create new VPN client"
        echo "  revoke-clients <name>  - Revoke VPN client certificate"
        echo "  list-clients           - List all VPN clients"
        echo "  status                 - Check server status"
        echo "  renew-clients <name>   - Renew client certificate"
        echo "  backup-pki             - Backup PKI (encrypted)"
        echo ""
        echo "First-time setup:"
        echo "  docker exec openvpn init-pki"
        echo ""
        echo "Then create clients:"
        echo "  docker exec openvpn create-clients alice"
        echo "  docker exec openvpn create-clients bob charlie"
        echo ""
        echo "Manage clients:"
        echo "  docker exec openvpn list-clients"
        echo "  docker exec openvpn revoke-clients baduser"
        echo "  docker exec openvpn status"
        exit 1
        ;;
esac
