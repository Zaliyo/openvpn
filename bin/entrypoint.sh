#!/bin/bash
set -e

# OpenVPN Server Entrypoint Script
# Routes to different commands based on arguments

# -----------------------------------------------------------------------------
# Configure VPN NAT and forwarding
# -----------------------------------------------------------------------------

configure_vpn_network() {
    local VPN_NET OUT_IF SERVER_IP NETMASK PREFIX

    # Derive the VPN subnet from the running configuration so operator edits
    # to the `server` directive are respected.
    SERVER_IP=$(awk '$1 == "server" { print $2; exit }' /etc/openvpn/openvpn.conf)
    NETMASK=$(awk '$1 == "server" { print $3; exit }' /etc/openvpn/openvpn.conf)

    if [ -n "$SERVER_IP" ] && [ -n "$NETMASK" ]; then
        # Convert dotted netmask to CIDR prefix.
        case "$NETMASK" in
            255.255.255.255) PREFIX=32 ;;
            255.255.255.254) PREFIX=31 ;;
            255.255.255.252) PREFIX=30 ;;
            255.255.255.248) PREFIX=29 ;;
            255.255.255.240) PREFIX=28 ;;
            255.255.255.224) PREFIX=27 ;;
            255.255.255.192) PREFIX=26 ;;
            255.255.255.128) PREFIX=25 ;;
            255.255.255.0)   PREFIX=24 ;;
            255.255.254.0)   PREFIX=23 ;;
            255.255.252.0)   PREFIX=22 ;;
            255.255.248.0)   PREFIX=21 ;;
            255.255.240.0)   PREFIX=20 ;;
            255.255.224.0)   PREFIX=19 ;;
            255.255.192.0)   PREFIX=18 ;;
            255.255.128.0)   PREFIX=17 ;;
            255.255.0.0)     PREFIX=16 ;;
            255.254.0.0)     PREFIX=15 ;;
            255.252.0.0)     PREFIX=14 ;;
            255.248.0.0)     PREFIX=13 ;;
            255.240.0.0)     PREFIX=12 ;;
            255.224.0.0)     PREFIX=11 ;;
            255.192.0.0)     PREFIX=10 ;;
            255.128.0.0)     PREFIX=9 ;;
            255.0.0.0)       PREFIX=8 ;;
            *)
                echo "⚠️  Unsupported OpenVPN netmask: ${NETMASK}"
                echo "   Skipping NAT setup."
                return 0
                ;;
        esac

        VPN_NET="${SERVER_IP}/${PREFIX}"
    else
        echo "⚠️  Could not determine VPN subnet from openvpn.conf."
        echo "   Using default VPN network: 192.168.255.0/24"
        VPN_NET="192.168.255.0/24"
    fi

    OUT_IF=$(ip route show default | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                    exit
                }
            }
        }
    ')

    if [ -z "$OUT_IF" ]; then
        echo "⚠️  Could not determine the outbound interface."
        echo "   Skipping NAT setup."
        echo "   VPN clients may connect but will not have internet access."
        return 0
    fi

    echo "🌐 Configuring VPN network"
    echo "   VPN network : ${VPN_NET}"
    echo "   Outbound IF : ${OUT_IF}"

    # -------------------------------------------------------------------------
    # Enable IPv4 forwarding
    # -------------------------------------------------------------------------

    if ! sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1; then
        if [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
            echo "   IP forwarding : already enabled (could not write, value already 1)"
        else
            echo "⚠️  Could not enable net.ipv4.ip_forward and it is currently off."
            echo "   Add this to the Docker Compose service:"
            echo "     sysctls:"
            echo "       - net.ipv4.ip_forward=1"
        fi
    else
        echo "   IP forwarding : enabled"
    fi

    # -------------------------------------------------------------------------
    # NAT VPN traffic
    # -------------------------------------------------------------------------

    if ! iptables -t nat -C POSTROUTING \
        -s "$VPN_NET" \
        -o "$OUT_IF" \
        -j MASQUERADE 2>/dev/null; then

        iptables -t nat -A POSTROUTING \
            -s "$VPN_NET" \
            -o "$OUT_IF" \
            -j MASQUERADE
    fi

    # -------------------------------------------------------------------------
    # Allow VPN -> Internet forwarding
    # -------------------------------------------------------------------------

    if ! iptables -C FORWARD \
        -i tun0 \
        -o "$OUT_IF" \
        -j ACCEPT 2>/dev/null; then

        iptables -A FORWARD \
            -i tun0 \
            -o "$OUT_IF" \
            -j ACCEPT
    fi

    # -------------------------------------------------------------------------
    # Allow Internet -> VPN return traffic
    # -------------------------------------------------------------------------

    if ! iptables -C FORWARD \
        -i "$OUT_IF" \
        -o tun0 \
        -m conntrack \
        --ctstate RELATED,ESTABLISHED \
        -j ACCEPT 2>/dev/null; then

        iptables -A FORWARD \
            -i "$OUT_IF" \
            -o tun0 \
            -m conntrack \
            --ctstate RELATED,ESTABLISHED \
            -j ACCEPT
    fi
}

# -----------------------------------------------------------------------------
# OpenVPN configuration migration
# -----------------------------------------------------------------------------

migrate_openvpn_config() {
    local CONFIG="/etc/openvpn/openvpn.conf"

    if [ ! -f "$CONFIG" ]; then
        return 0
    fi

    # -------------------------------------------------------------------------
    # OpenVPN 2.7 migration:
    #
    # topology net30 is deprecated for IPv4 server pools.
    #
    # Only replace the exact active directive. Do not overwrite or regenerate
    # the operator's entire configuration.
    # -------------------------------------------------------------------------

    if grep -qE \
        '^[[:space:]]*topology[[:space:]]+net30[[:space:]]*$' \
        "$CONFIG"; then

        echo "⚙️  Migrating OpenVPN topology: net30 -> subnet"

        sed -i \
            's/^[[:space:]]*topology[[:space:]]\+net30[[:space:]]*$/topology subnet/' \
            "$CONFIG"

        echo "✅ OpenVPN topology migrated to subnet."
    fi
}

# -----------------------------------------------------------------------------
# PKI / CRL handling
# -----------------------------------------------------------------------------

ensure_crl() {
    local CONFIG="/etc/openvpn/openvpn.conf"
    local CRL="/etc/openvpn/pki/crl.pem"
    local crl_reason=""

    # CRL verification is optional in the configuration. If it isn't enabled,
    # there is nothing to maintain here.
    if ! grep -qs \
        '^[[:space:]]*crl-verify[[:space:]]\+' \
        "$CONFIG"; then
        return 0
    fi

    # The CA must exist before EasyRSA can generate a CRL.
    if [ ! -f "/etc/openvpn/pki/ca.crt" ]; then
        echo "⚠️  CA certificate is not available; cannot generate CRL."
        return 0
    fi

    # -------------------------------------------------------------------------
    # Detect missing or soon-to-expire CRL.
    #
    # OpenVPN rejects new connections when an expired CRL is configured.
    # Refresh it when it is missing or expires within 30 days.
    # -------------------------------------------------------------------------

    if [ ! -f "$CRL" ]; then
        crl_reason="pki/crl.pem is missing"

    elif ! openssl crl \
        -in "$CRL" \
        -noout \
        -checkend 2592000 >/dev/null 2>&1; then

        crl_reason="pki/crl.pem is expired or expires within 30 days"
    fi

    if [ -z "$crl_reason" ]; then
        return 0
    fi

    echo "⚙️  ${crl_reason} - regenerating CRL..."

    if (
        cd /etc/openvpn/pki

        EASYRSA_PKI=/etc/openvpn/pki \
        EASYRSA=/usr/local/easyrsa/easyrsa3 \
        EASYRSA_CRL_DAYS="${EASYRSA_CRL_DAYS:-3650}" \
        /usr/local/bin/easyrsa --batch gen-crl
    ); then

        chmod 644 "$CRL"

        echo "✅ CRL regenerated successfully."
    else
        echo ""
        echo "❌ ERROR: Failed to generate CRL."
        echo "   CRL verification is enabled in openvpn.conf."
        echo "   OpenVPN will not be started."
        echo ""
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main command dispatcher
# -----------------------------------------------------------------------------

case "${1:-ovpn_run}" in

    # =========================================================================
    # Start OpenVPN
    # =========================================================================

    ovpn_run)

        # ---------------------------------------------------------------------
        # Install default configuration only when none exists.
        #
        # Existing configurations are deliberately preserved.
        # ---------------------------------------------------------------------

        if [ ! -f "/etc/openvpn/openvpn.conf" ]; then
            echo "⚙️  No openvpn.conf found."
            echo "   Installing default configuration..."

            mkdir -p /etc/openvpn

            cp \
                /usr/local/share/openvpn/openvpn.conf.default \
                /etc/openvpn/openvpn.conf

            echo "✅ Default OpenVPN configuration installed."
        fi

        # ---------------------------------------------------------------------
        # Migrate legacy configuration.
        # ---------------------------------------------------------------------

        migrate_openvpn_config

        # ---------------------------------------------------------------------
        # Initialize PKI on first startup.
        # ---------------------------------------------------------------------

        if [ ! -f "/etc/openvpn/pki/ca.crt" ] ||
           [ ! -f "/etc/openvpn/pki/issued/server.crt" ]; then

            echo "⚙️  PKI not found - running first-time initialization..."
            echo ""

            if ! /usr/local/bin/ovpn_init_pki; then
                echo ""
                echo "❌ ERROR: PKI initialization failed."
                echo ""
                echo "Fix the underlying issue, then either:"
                echo "  docker exec openvpn init-pki"
                echo "or restart the container:"
                echo "  docker restart openvpn"
                echo ""
                echo "⏳ Container waiting - OpenVPN will not start without a PKI."

                # Keep the container alive so docker exec and logs remain
                # available for troubleshooting.
                tail -f /dev/null
            fi

            echo ""
            echo "✅ PKI ready - starting OpenVPN server."
            echo "💡 Create your first client with:"
            echo "   docker exec openvpn create-clients alice"
            echo ""
        fi

        # ---------------------------------------------------------------------
        # Ensure CRL exists and is valid when crl-verify is configured.
        # ---------------------------------------------------------------------

        ensure_crl

        # ---------------------------------------------------------------------
        # Configure VPN forwarding and NAT.
        # ---------------------------------------------------------------------

        configure_vpn_network

        # ---------------------------------------------------------------------
        # Start OpenVPN.
        # ---------------------------------------------------------------------

        echo "🚀 Starting OpenVPN server..."

        exec /usr/local/sbin/openvpn \
            /etc/openvpn/openvpn.conf
        ;;

    # =========================================================================
    # EasyRSA
    # =========================================================================

    easyrsa)
        shift
        exec /usr/local/bin/easyrsa "$@"
        ;;

    # =========================================================================
    # Create VPN clients
    # =========================================================================

    create-clients)
        shift
        exec /usr/local/bin/ovpn_create_clients "$@"
        ;;

    # =========================================================================
    # Revoke VPN clients
    # =========================================================================

    revoke-clients)
        shift
        exec /usr/local/bin/ovpn_revoke_clients "$@"
        ;;

    # =========================================================================
    # List VPN clients
    # =========================================================================

    list-clients)
        exec /usr/local/bin/ovpn_list_clients
        ;;

    # =========================================================================
    # Server status
    # =========================================================================

    status)
        exec /usr/local/bin/ovpn_status
        ;;

    # =========================================================================
    # Renew VPN client
    # =========================================================================

    renew-clients)
        shift
        exec /usr/local/bin/ovpn_renew_clients "$@"
        ;;

    # =========================================================================
    # Backup PKI
    # =========================================================================

    backup-pki)
        exec /usr/local/bin/ovpn_backup_pki
        ;;

    # =========================================================================
    # Initialize PKI
    # =========================================================================

    init-pki)
        exec /usr/local/bin/ovpn_init_pki
        ;;

    # =========================================================================
    # Unknown command
    # =========================================================================

    *)
        echo "OpenVPN Server - Available commands:"
        echo ""
        echo "  ovpn_run"
        echo "      Start OpenVPN server (default)"
        echo ""
        echo "  init-pki"
        echo "      Initialize PKI (first-time setup)"
        echo ""
        echo "  easyrsa <args>"
        echo "      EasyRSA PKI management"
        echo ""
        echo "  create-clients <name> [name...]"
        echo "      Create VPN client certificates"
        echo ""
        echo "  revoke-clients <name>"
        echo "      Revoke a client certificate"
        echo ""
        echo "  list-clients"
        echo "      List VPN clients"
        echo ""
        echo "  status"
        echo "      Check OpenVPN server status"
        echo ""
        echo "  renew-clients <name>"
        echo "      Renew a client certificate"
        echo ""
        echo "  backup-pki"
        echo "      Backup PKI (encrypted; set GPG_PASSPHRASE_FILE"
        echo "      or GPG_PASSPHRASE)"
        echo ""
        echo "First-time setup:"
        echo "  docker exec openvpn init-pki"
        echo ""
        echo "Create clients:"
        echo "  docker exec openvpn create-clients alice"
        echo "  docker exec openvpn create-clients bob charlie"
        echo ""
        echo "Manage clients:"
        echo "  docker exec openvpn list-clients"
        echo "  docker exec openvpn revoke-clients baduser"
        echo "  docker exec openvpn status"
        echo ""

        exit 1
        ;;
esac