# OpenVPN Server - Built from OpenVPN 2.7.7 Source + EasyRSA
# Base: Debian 13-slim
#
# Multi-stage build:
#   Stage 1 - Build OpenSSL, OpenVPN and prepare EasyRSA
#   Stage 2 - Minimal runtime image
#
# OpenSSL is built separately so OpenVPN uses the requested OpenSSL version.

ARG OPENVPN_VERSION=2.7.7
ARG EASYRSA_VERSION=3.2.6
ARG OPENSSL_VERSION=3.6.4

# ============================================================================
# Stage 1: Build OpenVPN and prepare EasyRSA
# ============================================================================

FROM debian:13-slim AS builder

ARG OPENVPN_VERSION
ARG EASYRSA_VERSION
ARG OPENSSL_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------------------------------
# Build dependencies
# ----------------------------------------------------------------------------

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        libssl-dev \
        liblz4-dev \
        libcap-ng-dev \
        libnl-genl-3-dev \
        liblzo2-dev \
        libpkcs11-helper1-dev \
        libpam-dev \
        iproute2 \
        openssl \
        ca-certificates \
        procps \
        curl; \
    rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------------------------------
# Source archives
#
# Local archives placed in source/ are preferred.
#
# Expected:
#   source/openssl-${OPENSSL_VERSION}.tar.gz
#   source/openvpn-${OPENVPN_VERSION}.tar.gz
# ----------------------------------------------------------------------------

COPY source/ /tmp/source/

# ============================================================================
# Build OpenSSL
# ============================================================================

WORKDIR /tmp

RUN set -eux; \
    if [ -f "source/openssl-${OPENSSL_VERSION}.tar.gz" ]; then \
        echo "Using local OpenSSL ${OPENSSL_VERSION} source"; \
        cp \
            "source/openssl-${OPENSSL_VERSION}.tar.gz" \
            "openssl-${OPENSSL_VERSION}.tar.gz"; \
    else \
        echo "Downloading OpenSSL ${OPENSSL_VERSION}"; \
        curl -fsSL \
            "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
            -o "openssl-${OPENSSL_VERSION}.tar.gz"; \
    fi; \
    tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz"; \
    cd "openssl-${OPENSSL_VERSION}"; \
    echo "Configuring OpenSSL ${OPENSSL_VERSION}"; \
    CFLAGS="-O3" \
    CXXFLAGS="-O3" \
    ./Configure linux-generic64 \
        --prefix=/usr/local \
        --openssldir=/etc/ssl \
        shared \
        no-tests \
        no-docs; \
    echo "Compiling OpenSSL ${OPENSSL_VERSION}"; \
    make -j"$(nproc)"; \
    echo "Installing OpenSSL ${OPENSSL_VERSION}"; \
    make DESTDIR=/install install; \
    cd /; \
    rm -rf \
        "/tmp/openssl-${OPENSSL_VERSION}" \
        "/tmp/openssl-${OPENSSL_VERSION}.tar.gz"; \
    echo "OpenSSL ${OPENSSL_VERSION} compiled successfully"

# ============================================================================
# Build OpenVPN
# ============================================================================

WORKDIR /tmp

RUN set -eux; \
    if [ -f "source/openvpn-${OPENVPN_VERSION}.tar.gz" ]; then \
        echo "Using local OpenVPN ${OPENVPN_VERSION} source"; \
        cp \
            "source/openvpn-${OPENVPN_VERSION}.tar.gz" \
            "openvpn-${OPENVPN_VERSION}.tar.gz"; \
    else \
        echo "Downloading OpenVPN ${OPENVPN_VERSION}"; \
        curl -fsSL \
            "https://github.com/OpenVPN/openvpn/releases/download/v${OPENVPN_VERSION}/openvpn-${OPENVPN_VERSION}.tar.gz" \
            -o "openvpn-${OPENVPN_VERSION}.tar.gz"; \
    fi; \
    tar -xzf "openvpn-${OPENVPN_VERSION}.tar.gz"; \
    cd "openvpn-${OPENVPN_VERSION}"; \
    echo "Generating OpenVPN build system"; \
    autoreconf -i; \
    echo "Configuring OpenVPN ${OPENVPN_VERSION}"; \
    PKG_CONFIG_PATH=/install/usr/local/lib/pkgconfig \
    LD_LIBRARY_PATH=/install/usr/local/lib:/install/usr/local/lib64 \
    ./configure \
        --prefix=/usr/local \
        --sysconfdir=/etc \
        --with-openssl=/install/usr/local \
        --enable-lzo \
        --enable-lz4 \
        --enable-ssl \
        --enable-iproute2 \
        --enable-epoll \
        --enable-pf \
        --enable-pkcs11 \
        --enable-plugins \
        --enable-async-push; \
    echo "Compiling OpenVPN ${OPENVPN_VERSION}"; \
    make -j"$(nproc)"; \
    echo "Installing OpenVPN ${OPENVPN_VERSION}"; \
    make DESTDIR=/install install; \
    echo "OpenVPN build verification"; \
    /install/usr/local/sbin/openvpn --version; \
    cd /; \
    rm -rf \
        "/tmp/openvpn-${OPENVPN_VERSION}" \
        "/tmp/openvpn-${OPENVPN_VERSION}.tar.gz"; \
    echo "OpenVPN ${OPENVPN_VERSION} compiled successfully"

# ============================================================================
# Prepare EasyRSA
# ============================================================================

WORKDIR /tmp

RUN set -eux; \
    echo "Downloading EasyRSA ${EASYRSA_VERSION}"; \
    curl -fsSL \
        "https://github.com/OpenVPN/easy-rsa/archive/refs/tags/v${EASYRSA_VERSION}.tar.gz" \
        -o easy-rsa.tar.gz; \
    tar -xzf easy-rsa.tar.gz; \
    mkdir -p /install/usr/local/easyrsa; \
    cp -a \
        "easy-rsa-${EASYRSA_VERSION}/." \
        /install/usr/local/easyrsa/; \
    chmod +x \
        /install/usr/local/easyrsa/easyrsa3/easyrsa; \
    rm -rf \
        "/tmp/easy-rsa-${EASYRSA_VERSION}" \
        /tmp/easy-rsa.tar.gz

# ============================================================================
# Runtime directories and commands
# ============================================================================

RUN set -eux; \
    mkdir -p \
        /install/etc/openvpn \
        /install/var/log/openvpn \
        /install/usr/local/bin \
        /install/usr/local/share/openvpn; \
    rm -f /install/usr/local/bin/easyrsa; \
    ln -s \
        /usr/local/easyrsa/easyrsa3/easyrsa \
        /install/usr/local/bin/easyrsa

# ----------------------------------------------------------------------------
# Helper scripts
# ----------------------------------------------------------------------------

COPY bin/ /install/usr/local/bin/

# ----------------------------------------------------------------------------
# Default OpenVPN configuration
#
# entrypoint.sh installs this configuration to:
#   /etc/openvpn/openvpn.conf
#
# only when the configuration does not already exist.
# ----------------------------------------------------------------------------

COPY conf/openvpn.conf.default \
    /install/usr/local/share/openvpn/openvpn.conf.default

# ----------------------------------------------------------------------------
# Make scripts executable
# ----------------------------------------------------------------------------

RUN set -eux; \
    chmod +x /install/usr/local/bin/ovpn_*; \
    chmod +x /install/usr/local/bin/entrypoint.sh; \
    chmod +x /install/usr/local/bin/init-pki; \
    chmod +x /install/usr/local/bin/create-clients; \
    chmod +x /install/usr/local/bin/revoke-clients; \
    chmod +x /install/usr/local/bin/list-clients; \
    chmod +x /install/usr/local/bin/status; \
    chmod +x /install/usr/local/bin/renew-clients; \
    chmod +x /install/usr/local/bin/backup-pki

# ----------------------------------------------------------------------------
# Remove source archives before leaving builder
#
# Keep /tmp/source until both OpenSSL and OpenVPN builds are complete.
# ----------------------------------------------------------------------------

RUN rm -rf /tmp/source

# ============================================================================
# Stage 2: Runtime image
# ============================================================================

FROM debian:13-slim

ARG OPENVPN_VERSION
ARG EASYRSA_VERSION
ARG OPENSSL_VERSION

ENV DEBIAN_FRONTEND=noninteractive

LABEL maintainer="OpenVPN Contributors"
LABEL description="OpenVPN Server v${OPENVPN_VERSION} with EasyRSA v${EASYRSA_VERSION} and OpenSSL v${OPENSSL_VERSION}"
LABEL version="${OPENVPN_VERSION}"

# ============================================================================
# Runtime dependencies
# ============================================================================
#
# Keep this list limited to packages required by:
#   - OpenVPN
#   - EasyRSA
#   - networking/NAT
#   - PKCS#11 support
#   - helper scripts
#
# Do NOT manually modify /var/lib/dpkg/status.
# ============================================================================

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        liblzo2-2 \
        liblz4-1 \
        libpam0g \
        libpcsclite1 \
        libpkcs11-helper1 \
        iproute2 \
        iptables \
        netcat-openbsd \
        gpg; \
    apt-get clean; \
    rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*

# ============================================================================
# Copy compiled software and scripts
# ============================================================================

COPY --from=builder /install/ /

# ============================================================================
# OpenVPN runtime directories
# ============================================================================

RUN set -eux; \
    mkdir -p \
        /etc/openvpn \
        /var/log/openvpn; \
    chmod 755 \
        /etc/openvpn \
        /var/log/openvpn

# ============================================================================
# Custom OpenSSL runtime library configuration
# ============================================================================

RUN set -eux; \
    printf '%s\n' \
        '/usr/local/lib' \
        '/usr/local/lib64' \
        > /etc/ld.so.conf.d/openvpn-openssl.conf; \
    ldconfig

# ============================================================================
# Runtime verification
#
# Verify:
#   1. OpenVPN starts and reports the expected version.
#   2. OpenSSL reports the expected version.
#   3. OpenVPN links against the custom OpenSSL libraries.
# ============================================================================

RUN set -eux; \
    export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64; \
    echo "========================================"; \
    echo "OpenVPN version"; \
    echo "========================================"; \
    openvpn --version; \
    echo; \
    echo "========================================"; \
    echo "OpenSSL version"; \
    echo "========================================"; \
    openssl version; \
    echo; \
    echo "========================================"; \
    echo "OpenVPN OpenSSL linkage"; \
    echo "========================================"; \
    ldd /usr/local/sbin/openvpn | \
        grep -E 'libssl|libcrypto'; \
    echo; \
    echo "========================================"; \
    echo "EasyRSA version"; \
    echo "========================================"; \
    easyrsa --version

# ============================================================================
# Environment
# ============================================================================

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
ENV OPENSSL_DIR=/usr/local

# ============================================================================
# Entrypoint
# ============================================================================

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["ovpn_run"]