#!/bin/bash

# Frappe CRM Docker Build Script
# This script builds a Docker image with the CRM app

set -e  # Exit on error

# Get the script directory and navigate to CRM root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-15}"
IMAGE_TAG="${IMAGE_TAG:-artisthaa/crm:latest}"
PLATFORM="${PLATFORM:-linux/amd64}"
FRAPPE_DOCKER_PATH="${FRAPPE_DOCKER_PATH:-../frappe-crm-deploy/frappe_docker}"
USE_CACHE="${USE_CACHE:-true}"
# Local cache directory (used with buildx --load; inline cache doesn't work with --load)
DOCKER_CACHE_DIR="${DOCKER_CACHE_DIR:-.docker-build-cache}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🐳 Building Frappe CRM Docker Image${NC}"
echo ""
echo "Configuration:"
echo "  Frappe Branch: $FRAPPE_BRANCH"
echo "  Image Tag: $IMAGE_TAG"
echo "  Platform: $PLATFORM"
echo "  Use Cache: $USE_CACHE"
echo "  Cache Dir: $DOCKER_CACHE_DIR (local; reused across builds)"
echo "  Frappe Docker Path: $FRAPPE_DOCKER_PATH"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Enable BuildKit for better caching and performance
export DOCKER_BUILDKIT=1
export BUILDKIT_PROGRESS=plain

# Check if Docker buildx is available
if ! docker buildx version &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker buildx not found. Using regular docker build...${NC}"
    USE_BUILDX=false
else
    USE_BUILDX=true
    # Use docker-container driver: required for cache-to/cache-from with --load.
    # Default 'docker' driver does not support cache export.
    BUILDX_BUILDER="crm-builder"
    if ! docker buildx ls | grep -q "$BUILDX_BUILDER"; then
        echo -e "${BLUE}📦 Creating buildx builder ($BUILDX_BUILDER, docker-container driver)...${NC}"
        docker buildx create --name "$BUILDX_BUILDER" --driver docker-container --use 2>/dev/null || true
    else
        docker buildx use "$BUILDX_BUILDER" 2>/dev/null || true
    fi
fi

# Determine CRM repo URL, branch, and commit from git (commit used for cache-busting)
cd "$CRM_ROOT" || exit 1
if [ -d ".git" ]; then
    CRM_REPO_URL=$(git remote get-url origin 2>/dev/null || echo "https://github.com/roya-tech-team/crm")
    CRM_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    CRM_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")
else
    CRM_REPO_URL="${CRM_REPO:-https://github.com/roya-tech-team/crm}"
    CRM_BRANCH="${CRM_BRANCH:-main}"
    CRM_COMMIT="${CRM_COMMIT:-}"
fi
# Fallback if no commit (e.g. not a git repo) — use timestamp so each build is distinct
if [ -z "$CRM_COMMIT" ]; then
    CRM_COMMIT="build-$(date +%s)"
fi

echo "  CRM Repo: $CRM_REPO_URL"
echo "  CRM Branch: $CRM_BRANCH"
echo "  CRM Commit: ${CRM_COMMIT:0:12} (cache-bust when code changes)"
echo ""

# Check if frappe_docker directory exists
FRAPPE_DOCKER_ABS=$(cd "$CRM_ROOT" && cd "$FRAPPE_DOCKER_PATH" 2>/dev/null && pwd || echo "")
if [ -z "$FRAPPE_DOCKER_ABS" ] || [ ! -d "$FRAPPE_DOCKER_ABS" ]; then
    echo -e "${YELLOW}⚠️  frappe_docker directory not found at: $FRAPPE_DOCKER_PATH${NC}"
    echo "Please set FRAPPE_DOCKER_PATH environment variable or ensure frappe_docker exists."
    exit 1
fi

# Absolute path for local build cache (build runs from frappe_docker)
CACHE_DIR_ABS="$CRM_ROOT/.docker-build-cache"
if [ -n "$DOCKER_CACHE_DIR" ] && [ "${DOCKER_CACHE_DIR#/}" != "$DOCKER_CACHE_DIR" ]; then
    CACHE_DIR_ABS="$DOCKER_CACHE_DIR"
elif [ -n "$DOCKER_CACHE_DIR" ]; then
    CACHE_DIR_ABS="$CRM_ROOT/$DOCKER_CACHE_DIR"
fi

# Create apps.json content. _cache_bust (commit SHA) invalidates Docker cache when
# code changes — only app layers rebuild; base layers stay cached. Push code first.
APPS_JSON="[{\"url\": \"$CRM_REPO_URL\",\"branch\": \"$CRM_BRANCH\",\"_cache_bust\": \"$CRM_COMMIT\"}]"
APPS_JSON_BASE64=$(echo -n "$APPS_JSON" | base64)

echo -e "${BLUE}📦 Preparing build context...${NC}"

# Navigate to frappe_docker directory
cd "$FRAPPE_DOCKER_ABS" || exit 1

# Build the image
echo -e "${BLUE}🔨 Building Docker image...${NC}"
echo "   (First build: 10–20 min; with cache, 2–5 min when only app code changes)"
echo ""

# Build arguments
BUILD_ARGS=(
    --platform "$PLATFORM"
    -f images/layered/Containerfile
    --build-arg FRAPPE_BRANCH="$FRAPPE_BRANCH"
    --build-arg APPS_JSON_BASE64="$APPS_JSON_BASE64"
    -t "$IMAGE_TAG"
)

# Add cache options
if [ "$USE_CACHE" = "true" ]; then
    if [ "$USE_BUILDX" = true ]; then
        # Cache-from: registry (reuse layers from last push) + local (reuse from previous builds)
        if docker manifest inspect "$IMAGE_TAG" &>/dev/null; then
            echo -e "${BLUE}📦 Using registry image as cache source...${NC}"
            BUILD_ARGS+=(--cache-from "type=registry,ref=$IMAGE_TAG")
        fi
        if [ -d "$CACHE_DIR_ABS" ]; then
            echo -e "${BLUE}📦 Using local cache ($CACHE_DIR_ABS)...${NC}"
            BUILD_ARGS+=(--cache-from "type=local,src=$CACHE_DIR_ABS")
        fi
        # Cache-to: local only (inline cache doesn't work with --load)
        BUILD_ARGS+=(--cache-to "type=local,dest=$CACHE_DIR_ABS,mode=max")
    fi
else
    echo -e "${YELLOW}⚠️  Cache disabled (USE_CACHE=false). Full rebuild.${NC}"
    BUILD_ARGS+=(--no-cache)
fi

if [ "$USE_BUILDX" = true ]; then
    # Use buildx with load for local use
    BUILD_ARGS+=(--load)
    docker buildx build "${BUILD_ARGS[@]}" .
else
    # Regular docker build (BuildKit still enabled via env var)
    docker build "${BUILD_ARGS[@]}" .
fi

BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Docker image built successfully!${NC}"
    echo ""
    echo "Image: $IMAGE_TAG"
    echo ""
    echo "📋 Useful commands:"
    echo "  View image:    docker images | grep $(echo $IMAGE_TAG | cut -d: -f1)"
    echo "  Run container: docker run -it $IMAGE_TAG bash"
    echo "  Push image:    bash scripts/push-docker.sh"
    echo ""
    echo "  Push uploads only layers not already in the registry (incremental)."
    echo "  Cache: commit SHA invalidates app layers only when code changes."
    echo ""
else
    echo ""
    echo -e "${RED}❌ Docker build failed with exit code $BUILD_EXIT_CODE${NC}"
    exit $BUILD_EXIT_CODE
fi
