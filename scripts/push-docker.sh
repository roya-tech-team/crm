#!/bin/bash

# Frappe CRM Docker Push Script
# This script pushes a Docker image to Docker Hub

set -e  # Exit on error

# Configuration
IMAGE_TAG="${IMAGE_TAG:-artisthaa/crm:latest}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}📤 Pushing Frappe CRM Docker Image to Docker Hub${NC}"
echo ""
echo "Configuration:"
echo "  Image Tag: $IMAGE_TAG"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if image exists locally
IMAGE_NAME=$(echo "$IMAGE_TAG" | cut -d: -f1)
if ! docker images | grep -q "^${IMAGE_NAME}"; then
    echo -e "${RED}❌ Image $IMAGE_TAG not found locally!${NC}"
    echo ""
    echo "Please build the image first using:"
    echo "  bash scripts/build-docker.sh"
    exit 1
fi

# Check if user is logged in to Docker Hub
if ! docker info 2>&1 | grep -q "Username"; then
    echo -e "${YELLOW}⚠️  Not logged in to Docker Hub${NC}"
    echo "Please log in first using: docker login"
    echo ""
    read -p "Do you want to log in now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker login
    else
        echo "Exiting. Please log in and try again."
        exit 1
    fi
fi

echo -e "${BLUE}📤 Pushing Docker image (this may take 5-15 minutes for large images)...${NC}"
echo ""

# Push the image
docker push "$IMAGE_TAG"

PUSH_EXIT_CODE=$?

if [ $PUSH_EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Docker image pushed successfully!${NC}"
    echo ""
    echo "Image: $IMAGE_TAG"
    echo ""
    echo "📋 Verify at: https://hub.docker.com/r/${IMAGE_NAME}"
    echo ""
else
    echo ""
    echo -e "${RED}❌ Docker push failed with exit code $PUSH_EXIT_CODE${NC}"
    exit $PUSH_EXIT_CODE
fi
