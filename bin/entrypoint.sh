#!/bin/bash
set -e

# OpenVPN Server Entrypoint Script
# Routes to different commands based on arguments

# Set up the NAT and forwarding that VPN clients need to reach the internet.
# The server config pushes "redirect-gateway def1", so without this clients
# connect successfully and then have no connectivity at all. Requires
# NET_ADMIN on the container (see docker-compose.yml).
configure_vpn_network() {
    local VPN_NET OUT_IF SERVER_LINE

    # Derive the VPN subnet from the running config so operator edits to the
    # `server` directive are picked up instead of silently NATing the wrong net.
    SERVER_LINE=$(awk '$1 == "server" { print $2, $3; exit }' /etc/openvpn/openvpn.conf)
    if [ -n "$SERVER_LINE" ]; then
        VPN_NET=$(echo "$SERVER_LINE" | awk '{print $1"/"$2}')
    else
        VPN_NET="192.168.255.0/255.255.255.0"
    fi

    OUT_IF=$(ip route show default | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')
    if [ -z "$OUT_IF" ]; then
        echo "⚠️  Could not determine the outbound interface - skipping NAT setup."
        echo "   VPN clients will connect but will not have internet access."
        return 0
    fi

    echo "🌐 Configuring VPN network"
    echo "   VPN network : ${VPN_NET}"
    echo "   Outbound IF : ${OUT_IF}"

    # Don't let a read-only /proc/sys take down the whole entrypoint (set -e).
    # /proc/sys is read-only under Docker Desktop and some runtimes, but the
    # value is often already 1 there - so only complain if forwarding is really
    # off, otherwise this warns on a perfectly working setup.
    if ! sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
        if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
            echo "   IP forwarding : already enabled (could not write, value already 1)"
        else
            echo "⚠️  Could not enable net.ipv4.ip_forward and it is currently off -"
            echo "   VPN clients will not be routed. Add this to your compose service:"
            echo "     sysctls:"
            echo "       - net.ipv4.ip_forward=1"
        fi
    fi

    # -C first: this runs on every boot, and /etc/openvpn may be persisted
    # while the netfilter rules are not, so the rule must be re-added when
    # absent but never duplicated.
    if ! iptables -t nat -C POSTROUTING -s "$VPN_NET" -o "$OUT_IF" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s "$VPN_NET" -o "$OUT_IF" -j MASQUERADE
    fi

    if ! iptables -C FORWARD -i tun0 -o "$OUT_IF" -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -i tun0 -o "$OUT_IF" -j ACCEPT
    fi
    if ! iptables -C FORWARD -i "$OUT_IF" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -i "$OUT_IF" -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi
}

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

        # Safety net for PKIs created before openvpn.conf.default gained
        # `crl-verify`, and for deployments that persist only pki/ while
        # openvpn.conf is reinstalled fresh each boot: crl-verify on a missing
        # file is fatal at startup, so seed an empty CRL rather than crash-loop.
        if grep -qs "^crl-verify" /etc/openvpn/openvpn.conf && [ -f "/etc/openvpn/pki/ca.crt" ]; then
            crl_reason=""
            if [ ! -f "/etc/openvpn/pki/crl.pem" ]; then
                crl_reason="pki/crl.pem is missing"
            elif ! openssl crl -in /etc/openvpn/pki/crl.pem -noout \
                    -checkend 2592000 >/dev/null 2>&1; then
                # Expired, or expiring within 30 days. OpenVPN fails CLOSED on an
                # expired CRL - it rejects every new connection, not just revoked
                # ones - so refresh it here rather than let the server lock
                # everyone out on a date nobody is watching.
                crl_reason="pki/crl.pem is expired or expires within 30 days"
            fi

            if [ -n "$crl_reason" ]; then
                echo "⚙️  crl-verify is configured but ${crl_reason} - regenerating..."
                ( cd /etc/openvpn/pki \
                  && EASYRSA_PKI=/etc/openvpn/pki EASYRSA=/usr/local/easyrsa/easyrsa3 \
                     EASYRSA_CRL_DAYS=3650 /usr/local/bin/easyrsa --batch gen-crl ) || true
                chmod 644 /etc/openvpn/pki/crl.pem 2>/dev/null || true
            fi
        fi

        configure_vpn_network

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
        echo "  backup-pki             - Backup PKI (encrypted; set GPG_PASSPHRASE_FILE or GPG_PASSPHRASE)"
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
