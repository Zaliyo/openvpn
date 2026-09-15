# OpenVPN Server - Built from Official OpenVPN 2.7.7 Source + EasyRSA
# Based on:
# - OpenVPN: https://github.com/OpenVPN/openvpn (source build)
# - EasyRSA: https://github.com/OpenVPN/easy-rsa (v${EASYRSA_VERSION})
# - Base: Debian 12-slim
# 
# Multi-stage build to minimize vulnerabilities by removing build tools and curl

ARG OPENVPN_VERSION=2.7.7
ARG EASYRSA_VERSION=3.2.6
ARG OPENSSL_VERSION=3.6.4

# ============================================================================
# Stage 1: Build OpenVPN and prepare EasyRSA
# ============================================================================
FROM debian:12-slim AS builder

ARG OPENVPN_VERSION
ARG EASYRSA_VERSION
ARG OPENSSL_VERSION

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
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
    curl \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Compile OpenSSL from source to patch CVE-2026-75803
# Use local source if available, otherwise download from GitHub
# ============================================================================
COPY source/ /tmp/source/

WORKDIR /tmp
RUN set -e && \
    if [ -f "source/openssl-${OPENSSL_VERSION}.tar.gz" ]; then \
        echo "✓ Using local OpenSSL ${OPENSSL_VERSION} source"; \
        mv source/openssl-${OPENSSL_VERSION}.tar.gz .; \
    else \
        echo "⬇ Downloading OpenSSL ${OPENSSL_VERSION} from GitHub..."; \
        curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
            -o openssl-${OPENSSL_VERSION}.tar.gz; \
    fi && \
    rm -rf source && \
    tar -xzf openssl-${OPENSSL_VERSION}.tar.gz && \
    cd openssl-${OPENSSL_VERSION} && \
    echo "🔨 Configuring OpenSSL ${OPENSSL_VERSION}..." && \
    CFLAGS="-O3" CXXFLAGS="-O3" ./Configure linux-generic64 \
        --prefix=/usr/local \
        --openssldir=/etc/ssl \
        shared \
        no-asm \
        no-tests \
        no-docs && \
    echo "🔨 Compiling OpenSSL ${OPENSSL_VERSION}..." && \
    make -j$(nproc) && \
    echo "📦 Installing OpenSSL ${OPENSSL_VERSION}..." && \
    make DESTDIR=/install install && \
    cd / && \
    rm -rf /tmp/openssl-* && \
    echo "✓ OpenSSL ${OPENSSL_VERSION} compiled successfully"

# ============================================================================
# Build OpenVPN from source (linked against OpenSSL ${OPENSSL_VERSION})
# Use local source if available, otherwise download from GitHub
# ============================================================================
WORKDIR /tmp
RUN set -e && \
    if [ -f "source/openvpn-${OPENVPN_VERSION}.tar.gz" ]; then \
        echo "✓ Using local OpenVPN ${OPENVPN_VERSION} source"; \
        mv source/openvpn-${OPENVPN_VERSION}.tar.gz .; \
    else \
        echo "⬇ Downloading OpenVPN ${OPENVPN_VERSION} from GitHub..."; \
        curl -fsSL "https://github.com/OpenVPN/openvpn/releases/download/v${OPENVPN_VERSION}/openvpn-${OPENVPN_VERSION}.tar.gz" \
            -o openvpn-${OPENVPN_VERSION}.tar.gz; \
    fi && \
    rm -rf source && \
    tar -xzf openvpn-${OPENVPN_VERSION}.tar.gz && \
    cd openvpn-${OPENVPN_VERSION} && \
    autoreconf -i && \
    PKG_CONFIG_PATH=/install/usr/local/lib/pkgconfig LD_LIBRARY_PATH=/install/usr/local/lib \
    ./configure \
        --prefix=/usr/local \
        --sysconfdir=/etc \
        --with-openssl=/install/usr/local \
        --enable-lzo \
        --enable-lz4 \
        --enable-ssl \
        --enable-crypto \
        --enable-iproute2 \
        --enable-epoll \
        --enable-pf \
        --enable-pkcs11 \
        --enable-plugins \
        --enable-async-push && \
    make -j$(nproc) && \
    make DESTDIR=/install install && \
    cd / && \
    rm -rf /tmp/openvpn* && \
    echo "✓ OpenVPN ${OPENVPN_VERSION} compiled successfully" && \
    /install/usr/local/sbin/openvpn --version

# Download and prepare EasyRSA
WORKDIR /tmp
RUN curl -fsSL "https://github.com/OpenVPN/easy-rsa/archive/refs/tags/v${EASYRSA_VERSION}.tar.gz" \
        -o easy-rsa.tar.gz && \
    tar -xzf easy-rsa.tar.gz && \
    mkdir -p /install/usr/local/easyrsa && \
    cp -r easy-rsa-${EASYRSA_VERSION}/* /install/usr/local/easyrsa/ && \
    chmod +x /install/usr/local/easyrsa/easyrsa3/easyrsa && \
    rm -rf /tmp/easy-rsa*

# Create config and log directories in builder
RUN mkdir -p /install/etc/openvpn /install/var/log/openvpn /install/usr/local/bin && \
    rm -f /install/usr/local/bin/easyrsa && \
    ln -sf /usr/local/easyrsa/easyrsa3/easyrsa /install/usr/local/bin/easyrsa

# Copy helper scripts to builder
COPY bin/ /install/usr/local/bin/

# Default OpenVPN server config. entrypoint.sh installs this to
# /etc/openvpn/openvpn.conf on first boot if that file is missing, so
# deployments that only mount a subdirectory (e.g. .../pki) for
# persisted cert data - and never touch /etc/openvpn itself - still
# get a working config out of the box, no manual host-side setup
# required.
RUN mkdir -p /install/usr/local/share/openvpn
COPY conf/openvpn.conf.default /install/usr/local/share/openvpn/openvpn.conf.default

# Make scripts executable in builder
RUN chmod +x /install/usr/local/bin/ovpn_* && \
    chmod +x /install/usr/local/bin/entrypoint.sh && \
    chmod +x /install/usr/local/bin/init-pki && \
    chmod +x /install/usr/local/bin/create-clients && \
    chmod +x /install/usr/local/bin/revoke-clients && \
    chmod +x /install/usr/local/bin/list-clients && \
    chmod +x /install/usr/local/bin/status && \
    chmod +x /install/usr/local/bin/renew-clients && \
    chmod +x /install/usr/local/bin/backup-pki

# ============================================================================
# Stage 2: Runtime image - minimal Debian with only essential packages
# ============================================================================
FROM debian:12-slim

ARG OPENVPN_VERSION
ARG EASYRSA_VERSION
ARG OPENSSL_VERSION

LABEL maintainer="OpenVPN Contributors"
LABEL description="OpenVPN Server v${OPENVPN_VERSION} with EasyRSA v${EASYRSA_VERSION} and OpenSSL v${OPENSSL_VERSION}"
LABEL version="${OPENVPN_VERSION}"

# Install ONLY essential runtime packages
# OpenSSL 3.6.4 comes from builder stage (LD_LIBRARY_PATH prioritizes it)
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    liblzo2-2 \
    liblz4-1 \
    libpam0g \
    libpcsclite1 \
    libpkcs11-helper1 \
    iproute2 \
    iptables \
    netcat-openbsd \
    && apt-get purge -y --allow-remove-essential perl perl-modules-5.36 perl-base \
    && apt-get autoremove -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && rm -rf /etc/perl /usr/lib/perl* /usr/share/perl* \
    && grep -v "^perl" /var/lib/dpkg/status > /var/lib/dpkg/status.new && mv /var/lib/dpkg/status.new /var/lib/dpkg/status \
    && sed -i '/^Package: perl/,/^$/d' /var/lib/dpkg/status

# Copy everything pre-built from builder stage
COPY --from=builder /install/ /

# Setup OpenVPN runtime environment
RUN mkdir -p /etc/openvpn /var/log/openvpn && \
    chmod 755 /etc/openvpn /var/log/openvpn && \
    echo "/usr/local/lib" > /etc/ld.so.conf.d/openvpn-openssl.conf && \
    echo "/usr/local/lib64" >> /etc/ld.so.conf.d/openvpn-openssl.conf && \
    ldconfig

# Set environment to use compiled OpenSSL
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
ENV OPENSSL_DIR=/usr/local

# Use entrypoint script with command routing
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["ovpn_run"]
