#!/bin/bash

# 환경변수 확인
if [ -z "$IMAGE_TAG" ]; then
    echo "Error: IMAGE_TAG environment variable is not set."
    exit 1
fi

FULL_IMAGE_NAME="${REGISTRY_URL:-test-stack}/${IMAGE_NAME:-app}"

echo "Checking image: $FULL_IMAGE_NAME:$IMAGE_TAG"

# 로컬 이미지 태그 목록 조회
AVAILABLE_TAGS=$(docker images --format "{{.Tag}}" "$FULL_IMAGE_NAME")

echo "Available Tags:"
echo "$AVAILABLE_TAGS"

# 태그 존재 여부 확인
if echo "$AVAILABLE_TAGS" | grep -q "^$IMAGE_TAG$"; then
    echo "✅ OK: Image tag '$IMAGE_TAG' found locally."
else
    echo "⚠️  WARNING: Image tag '$IMAGE_TAG' not found in local docker images!"
    echo "   Please make sure you have built the image with: docker compose build app"
fi
