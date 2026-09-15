# GitHub Actions CI/CD

This project uses GitHub Actions to automatically build and push multi-architecture Docker images to Docker Hub.

## Setup

### 1. Add Docker Hub Secrets

Go to your GitHub repository settings and add these secrets:

- **`DOCKER_USERNAME`** - Your Docker Hub username
- **`DOCKER_PASSWORD`** - Your Docker Hub Personal Access Token (not your password!)

**To create a Docker Hub Personal Access Token:**
1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Name it (e.g., "GitHub Actions")
4. Copy the token and add it to GitHub Secrets

### 2. Enable GitHub Actions

Workflows are in `.github/workflows/`:
- **`docker-build.yml`** - Builds and pushes multi-arch images on push to main

## Workflow Features

The `docker-build.yml` workflow:

- ✅ Builds for **linux/amd64** and **linux/arm64**
- ✅ Pushes to Docker Hub automatically
- ✅ Tags images as `2.7.7` and `latest`
- ✅ Updates Docker Hub repository description
- ✅ Caches layers for faster builds
- ✅ Adds OCI metadata labels

## Triggers

The workflow runs when:
1. Code is pushed to `main` branch
2. Changes include: `Dockerfile`, `bin/**`, `source/**`, or the workflow file itself
3. Manual trigger via "Actions" tab in GitHub

## Local Alternative: Manual Build Script

For local testing or if you prefer manual builds:

```bash
# Make script executable
chmod +x build-multiarch.sh

# Build and push (default)
./build-multiarch.sh

# Build with custom repository
./build-multiarch.sh myusername/openvpn

# Build with custom version
./build-multiarch.sh myusername/openvpn 2.7.8

# Build without pushing (--load)
./build-multiarch.sh zaliyo/openvpn 2.7.7 false
```

## Monitoring Builds

### In GitHub:
1. Go to **Actions** tab in your repository
2. Click on **"Build Multi-Arch Docker Image"** workflow
3. View build logs and status

### Docker Hub:
After successful build, images will appear at:
- `docker pull zaliyo/openvpn:2.7.7`
- `docker pull zaliyo/openvpn:latest`

## Build Cache

The workflow uses GitHub Actions cache to speed up subsequent builds. Cache is stored for:
- Layer cache (reused across builds)
- Registry cache (Docker Hub)

## Troubleshooting

### Build fails with "unauthorized"
- Check `DOCKER_USERNAME` and `DOCKER_PASSWORD` secrets
- Verify Personal Access Token is valid and not expired
- Ensure token has push permissions

### Build times out
- Reduce parallel builds or increase timeout in workflow
- Check available GitHub Actions minutes

### Images not appearing on Docker Hub
- Verify push step succeeded in workflow logs
- Check Docker Hub account for API rate limits
- Ensure repository is public or token has repo access

## Security

- Secrets are encrypted and not logged
- Workflow only pushes on success
- Docker images are scanned with Docker Scout
- OCI metadata labels included for traceability

## Future Enhancements

Potential workflow improvements:
- [ ] Scan with Docker Scout and gate on vulnerabilities
- [ ] Run tests before building
- [ ] Generate SBOM (Software Bill of Materials)
- [ ] Create GitHub releases
- [ ] Send notifications on build status
