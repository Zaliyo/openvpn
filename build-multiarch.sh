#!/bin/bash
# Multi-architecture Docker build script for OpenVPN
# Builds and pushes images for both amd64 and arm64 architectures

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="${1:-zaliyo/openvpn}"
VERSION="${2:-2.7.7}"
PUSH="${3:-true}"

# Print header
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Multi-Architecture Docker Build Script   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Repository:  $IMAGE_NAME"
echo "  Version:     $VERSION"
echo "  Platforms:   linux/amd64, linux/arm64"
echo "  Push:        $PUSH"
echo ""

# Verify buildx is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed${NC}"
    exit 1
fi

# Extract OpenVPN version from Dockerfile
DOCKERFILE_VERSION=$(grep "^ARG OPENVPN_VERSION=" Dockerfile | cut -d'=' -f2)
if [ -z "$DOCKERFILE_VERSION" ]; then
    echo -e "${RED}✗ Could not extract OPENVPN_VERSION from Dockerfile${NC}"
    exit 1
fi

# Override with extracted version if not specified
if [ "$VERSION" = "2.7.7" ]; then
    VERSION=$DOCKERFILE_VERSION
fi

# Check if buildx is available
if ! docker buildx version &> /dev/null; then
    echo -e "${RED}✗ Docker buildx is not available${NC}"
    echo "  Install it with: docker buildx create --name multiarch --driver docker-container"
    exit 1
fi

# Build
echo -e "${BLUE}Building Docker image for multiple architectures...${NC}"
echo ""

BUILD_CMD="docker buildx build"
BUILD_CMD="$BUILD_CMD --platform linux/amd64,linux/arm64"
BUILD_CMD="$BUILD_CMD --tag $IMAGE_NAME:$VERSION"
BUILD_CMD="$BUILD_CMD --tag $IMAGE_NAME:latest"

if [ "$PUSH" = "true" ]; then
    BUILD_CMD="$BUILD_CMD --push"
else
    echo -e "${BLUE}Note: Using --load (single architecture only)${NC}"
    BUILD_CMD="$BUILD_CMD --load"
fi

BUILD_CMD="$BUILD_CMD -f Dockerfile"
BUILD_CMD="$BUILD_CMD ."

eval "$BUILD_CMD"

echo ""
echo -e "${GREEN}✓ Build complete!${NC}"
echo ""
echo -e "${GREEN}Image Information:${NC}"
echo "  Repository:  $IMAGE_NAME"
echo "  Tag:         $VERSION (latest)"
echo "  Platforms:   ✓ linux/amd64, ✓ linux/arm64"
echo ""

if [ "$PUSH" = "true" ]; then
    echo -e "${GREEN}✓ Image pushed to Docker Hub!${NC}"
    echo ""
    echo -e "${BLUE}Pull the image with:${NC}"
    echo "  docker pull $IMAGE_NAME:$VERSION"
    echo "  docker pull $IMAGE_NAME:latest"
else
    echo -e "${BLUE}Note: Image not pushed (--load was used)${NC}"
    echo "To push, run: docker push $IMAGE_NAME:$VERSION"
fi

echo ""
