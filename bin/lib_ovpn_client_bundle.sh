# Shared helper for building a client's .ovpn connection file.
# Sourced by ovpn_create_clients and ovpn_renew_clients - not meant to
# be run directly (no shebang/exec bit; entrypoint.sh never dispatches
# to it).
#
# Requires EASYRSA_PKI to already be exported by the caller.

# Where finished .ovpn files go. Not every deployment mounts this to a
# host directory (the source repo's own local docker-compose.yml
# doesn't), so create it defensively - worst case it just lives inside
# the container until the next `docker cp`.
OVPN_USERS_DIR="/opt/users"
mkdir -p "$OVPN_USERS_DIR"

# Server endpoint clients should connect to. Comes from the .env file
# (loaded into the container via docker-compose's env_file:).
OVPN_SERVER_HOST="${VPN_IP:-}"
OVPN_SERVER_PORT="${VPN_PORT:-1194}"
if [ -z "$OVPN_SERVER_HOST" ]; then
    echo "⚠️  VPN_IP is not set in .env - using a placeholder in the generated .ovpn file(s)."
    echo "   Edit .env, set VPN_IP to this server's public IP or hostname, and re-run"
    echo "   create-clients/renew-clients (or just replace the 'remote' line by hand)."
    OVPN_SERVER_HOST="YOUR_SERVER_IP_OR_HOSTNAME"
fi

# Build one client's .ovpn from its issued cert/key plus the CA and
# tls-crypt key, matching the ciphers/TLS settings used server-side in
# conf/openvpn.conf.default. Overwrites any existing file for the same
# client name - used after both first issuance and renewal.
build_ovpn_file() {
    client="$1"
    out_file="${OVPN_USERS_DIR}/${client}.ovpn"

    ca_crt="${EASYRSA_PKI}/ca.crt"
    client_crt="${EASYRSA_PKI}/issued/${client}.crt"
    client_key="${EASYRSA_PKI}/private/${client}.key"
    ta_key="${EASYRSA_PKI}/ta.key"

    for f in "$ca_crt" "$client_crt" "$client_key" "$ta_key"; do
        [ -f "$f" ] || { echo "❌ ERROR: expected file missing: $f"; return 1; }
    done

    {
        echo "client"
        echo "dev tun"
        echo "proto udp"
        echo "remote ${OVPN_SERVER_HOST} ${OVPN_SERVER_PORT}"
        echo "resolv-retry infinite"
        echo "nobind"
        echo "persist-key"
        echo "persist-tun"
        echo "remote-cert-tls server"
        echo "cipher AES-256-GCM"
        echo "auth SHA256"
        echo "tls-version-min 1.2"
        echo "data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305"
        echo "data-ciphers-fallback AES-256-GCM"
        echo "verb 3"
        echo "mute 20"
        echo ""
        echo "<ca>"
        cat "$ca_crt"
        echo "</ca>"
        echo ""
        echo "<cert>"
        # issued/<client>.crt is openssl's `-text` dump followed by the
        # actual PEM block - inline configs only want the PEM block.
        sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$client_crt"
        echo "</cert>"
        echo ""
        echo "<key>"
        cat "$client_key"
        echo "</key>"
        echo ""
        echo "<tls-crypt>"
        cat "$ta_key"
        echo "</tls-crypt>"
    } > "$out_file"

    chmod 600 "$out_file"
}
