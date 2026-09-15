#!/bin/bash
set -e

# OpenVPN Server Entrypoint Script
# Routes to different commands based on arguments

case "${1:-ovpn_run}" in
    ovpn_run)
        # Install a default server config on first-ever startup if none
        # exists yet. Deployments that only persist a subdirectory of
        # /etc/openvpn (e.g. its pki/ subfolder) never populate
        # openvpn.conf themselves, and this image doesn't bake one into
        # /etc/openvpn directly (that path may be entirely unmounted, or
        # mounted elsewhere) - so without this, ovpn_run below has no
        # config to start with. Never overwrites an existing file, so
        # any customization the operator makes to openvpn.conf persists
        # across restarts.
        if [ ! -f "/etc/openvpn/openvpn.conf" ]; then
            echo "⚙️  No openvpn.conf found - installing the default configuration..."
            mkdir -p /etc/openvpn
            cp /usr/local/share/openvpn/openvpn.conf.default /etc/openvpn/openvpn.conf
        fi

        # Auto-initialize PKI on first-ever startup if it doesn't exist yet.
        # Safe to run on every boot: ovpn_init_pki itself no-ops (and exits 0)
        # once ca.crt is already present, so restarts are unaffected.
        if [ ! -f "/etc/openvpn/pki/ca.crt" ] || [ ! -f "/etc/openvpn/pki/issued/server.crt" ]; then
            echo "⚙️  PKI not found - running first-time initialization..."
            echo ""
            # entrypoint.sh runs with `set -e`; don't let a failed init here
            # kill the script before we've had a chance to report it below.
            /usr/local/bin/ovpn_init_pki || true

            if [ ! -f "/etc/openvpn/pki/ca.crt" ] || [ ! -f "/etc/openvpn/pki/issued/server.crt" ]; then
                echo ""
                echo "❌ ERROR: PKI initialization failed - see the output above."
                echo "Fix the underlying issue, then either:"
                echo "  docker exec openvpn init-pki"
                echo "or restart the container to retry automatically:"
                echo "  docker restart openvpn"
                echo ""
                echo "⏳ Container waiting - OpenVPN will not start without a PKI."
                # Keep container alive so `docker exec` / logs remain usable
                tail -f /dev/null
            fi

            echo ""
            echo "✅ PKI ready - starting OpenVPN server."
            echo "💡 Create your first client with: docker exec openvpn create-clients alice"
            echo ""
        fi

        # Start OpenVPN server
        exec /usr/local/sbin/openvpn /etc/openvpn/openvpn.conf
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
