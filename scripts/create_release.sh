#!/bin/bash
# Helper script to create a FasterBASIC release
#
# Usage:
#   bash scripts/create_release.sh [version]
#
# Examples:
#   bash scripts/create_release.sh 2.0.0
#   bash scripts/create_release.sh          # prompts for version

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== FasterBASIC Release Helper ===${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "README.md" ] || [ ! -d "zig_compiler" ]; then
    echo -e "${RED}Error: Must be run from the FasterBASIC project root${NC}"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    echo "Please commit or stash your changes before creating a release."
    exit 1
fi

# Get the current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo -e "${YELLOW}Warning: You are on branch '$BRANCH', not 'main'${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get version from user or command line
if [ -z "$1" ]; then
    echo "Enter version number (e.g., 1.0.0):"
    read VERSION
else
    VERSION="$1"
fi

# Validate version format
if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Version must be in format X.Y.Z (e.g., 1.0.0)${NC}"
    exit 1
fi

TAG="v$VERSION"

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag '$TAG' already exists${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Creating release:${NC}"
echo "  Version: $VERSION"
echo "  Tag:     $TAG"
echo "  Branch:  $BRANCH"
echo ""

# Get release notes
echo "Enter release notes (press Ctrl-D when done):"
RELEASE_NOTES=$(cat)

if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="Release $VERSION"
fi

echo ""
echo -e "${YELLOW}Release notes:${NC}"
echo "$RELEASE_NOTES"
echo ""

# Build and test before releasing
echo ""
echo -e "${BLUE}Building and testing...${NC}"
echo ""

if [ -x "zig_compiler/zig-out/bin/fbc" ]; then
    echo -e "${GREEN}✓ fbc binary found${NC}"
else
    echo -e "${YELLOW}Building fbc...${NC}"
    cd zig_compiler && zig build -Doptimize=ReleaseFast && cd ..
    if [ -x "zig_compiler/zig-out/bin/fbc" ]; then
        echo -e "${GREEN}✓ fbc built successfully${NC}"
    else
        echo -e "${RED}✗ Failed to build fbc${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}Running JIT batch tests...${NC}"
if zig_compiler/zig-out/bin/fbc --batch-jit zig_compiler/tests/batch_test --timeout 30 2>&1; then
    echo -e "${GREEN}✓ JIT batch tests passed${NC}"
else
    echo -e "${RED}✗ JIT batch tests failed${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# Confirm
read -p "Create release? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Create annotated tag
echo ""
echo -e "${BLUE}Creating tag...${NC}"
git tag -a "$TAG" -m "$RELEASE_NOTES"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Tag '$TAG' created locally${NC}"
else
    echo -e "${RED}✗ Failed to create tag${NC}"
    exit 1
fi

# Push tag
echo ""
echo -e "${BLUE}Pushing tag to GitHub...${NC}"
git push origin "$TAG"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Tag pushed to GitHub${NC}"
else
    echo -e "${RED}✗ Failed to push tag${NC}"
    echo "You can manually push with: git push origin $TAG"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Release Created Successfully! ===${NC}"
echo ""
echo "GitHub Actions will now:"
echo "  1. Build fbc for macOS ARM64 (Zig 0.15)"
echo "  2. Run unit tests (zig build test)"
echo "  3. Run JIT batch tests (--batch-jit)"
echo "  4. Run AOT end-to-end tests"
echo "  5. Run NEON/array expression tests"
echo "  6. Package and create a GitHub Release"
echo ""
echo "Monitor progress at:"
echo -e "${BLUE}https://github.com/albanread/FasterBASIC/actions${NC}"
echo ""
echo "Release will be available at:"
echo -e "${BLUE}https://github.com/albanread/FasterBASIC/releases/tag/$TAG${NC}"
echo ""
echo "To delete this release (if needed):"
echo "  git tag -d $TAG"
echo "  git push origin :refs/tags/$TAG"
echo ""
