# Docker Build Optimization Guide

## Why Docker Builds Are Slow

The Frappe CRM Docker build process is slow (10-20 minutes) because it performs many heavy operations:

### 1. **System Dependencies Installation**
- Installing system packages (apt/yum)
- Setting up Python runtime environment
- Installing Node.js and npm/yarn
- Installing build tools and compilers

### 2. **Framework Installation**
- Cloning Frappe framework from GitHub
- Installing Python dependencies (pip install) - can be 100+ packages
- Installing Node.js dependencies (yarn install) - can be 1000+ packages
- Compiling native extensions

### 3. **Application Installation**
- Cloning CRM app from GitHub
- Installing app-specific Python dependencies
- Installing app-specific Node.js dependencies
- Building frontend assets (Vite/webpack compilation)

### 4. **Image Layers**
- Each step creates a new layer
- Layers are cached, but if any layer changes, all subsequent layers must rebuild
- The layered Containerfile structure means many sequential steps

## Optimizations Added to the Script

### 1. **BuildKit Enabled**
```bash
export DOCKER_BUILDKIT=1
```
- Modern build engine with better caching
- Parallel layer processing
- More efficient layer storage

### 2. **Cache Configuration**
- **Inline Cache**: Cache metadata embedded in the image
  - `CACHE_TO=type=inline`
  - Automatically reused on next build
  - No separate cache image needed

- **Registry Cache** (optional): Separate cache image
  - `CACHE_TO=type=registry,ref=${IMAGE_TAG}-cache,mode=max`
  - Better for CI/CD pipelines
  - Can be shared across builds

### 3. **Cache-From Strategy**
- Uses previous image as cache source if available
- Automatically detects existing images in registry
- Reuses unchanged layers from previous builds

### 4. **Buildx Builder**
- Ensures buildx builder is properly configured
- Better multi-platform support
- Improved cache handling

## Expected Build Times

### First Build (No Cache)
- **Time**: 15-25 minutes
- **Reason**: Everything must be downloaded and compiled

### Subsequent Builds (With Cache)
- **Time**: 2-5 minutes (if only app code changed)
- **Time**: 5-10 minutes (if dependencies changed)
- **Time**: 10-15 minutes (if framework version changed)

## Additional Optimization Tips

### 1. **Use Local Development Build**
For faster iteration during development:
```bash
PUSH_IMAGE=false USE_CACHE=true ./scripts/build-and-push-docker.sh
```

### 2. **Build Only When Needed**
- Only rebuild when code or dependencies change
- Use `.dockerignore` to exclude unnecessary files
- Keep dependency files (requirements.txt, package.json) stable

### 3. **Use Multi-Stage Builds** (if modifying Containerfile)
- Separate build and runtime stages
- Only include necessary files in final image

### 4. **CI/CD Optimization**
- Use registry cache for shared builds
- Build on dedicated build servers with faster CPUs
- Use parallel builds for multiple platforms

## Troubleshooting Slow Builds

### Check Cache Usage
```bash
docker buildx du
```

### Clear Cache (if needed)
```bash
docker builder prune
```

### Monitor Build Progress
The script uses `BUILDKIT_PROGRESS=plain` for detailed output showing which layers are cached.

### Verify BuildKit is Active
```bash
docker buildx version
```

## Current Script Features

✅ Syntax validated
✅ BuildKit enabled
✅ Cache support (inline)
✅ Buildx integration
✅ Error handling
✅ Progress output
✅ Configurable via environment variables
