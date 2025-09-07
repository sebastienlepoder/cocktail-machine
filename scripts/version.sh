#!/bin/bash

# Version Management Script for Cocktail Machine Project
# Manages versions across all project components

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Get current version
get_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "1.0.0"
    fi
}

# Set version
set_version() {
    local new_version="$1"
    
    if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Version must be in format X.Y.Z (e.g., 1.0.0)"
        exit 1
    fi
    
    echo "$new_version" > "$VERSION_FILE"
    print_success "Version set to $new_version"
    update_all_components "$new_version"
}

# Bump version
bump_version() {
    local bump_type="$1"
    local current_version
    current_version=$(get_version)
    
    IFS='.' read -r -a version_parts <<< "$current_version"
    local major="${version_parts[0]}"
    local minor="${version_parts[1]}"
    local patch="${version_parts[2]}"
    
    case "$bump_type" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch")
            patch=$((patch + 1))
            ;;
        *)
            print_error "Bump type must be: major, minor, or patch"
            exit 1
            ;;
    esac
    
    local new_version="$major.$minor.$patch"
    echo "$new_version" > "$VERSION_FILE"
    print_success "Version bumped from $current_version to $new_version"
    update_all_components "$new_version"
}

# Update all components with new version
update_all_components() {
    local version="$1"
    local date_version="$(date +%Y.%m.%d)-v$version"
    local build_number="Build-$(printf "%03d" $(($(date +%s) % 1000)))"
    
    print_info "Updating component versions..."
    
    # Update setup scripts
    if [ -f "$PROJECT_ROOT/deployment/setup-ultimate.sh" ]; then
        sed -i "s/SCRIPT_VERSION=\"[^\"]*\"/SCRIPT_VERSION=\"$date_version\"/" "$PROJECT_ROOT/deployment/setup-ultimate.sh"
        sed -i "s/SCRIPT_BUILD=\"[^\"]*\"/SCRIPT_BUILD=\"$build_number\"/" "$PROJECT_ROOT/deployment/setup-ultimate.sh"
        print_success "Updated deployment/setup-ultimate.sh"
    fi
    
    if [ -f "$PROJECT_ROOT/scripts/setup-ultimate.sh" ]; then
        sed -i "s/SCRIPT_VERSION=\"[^\"]*\"/SCRIPT_VERSION=\"$date_version\"/" "$PROJECT_ROOT/scripts/setup-ultimate.sh"
        sed -i "s/SCRIPT_BUILD=\"[^\"]*\"/SCRIPT_BUILD=\"$build_number\"/" "$PROJECT_ROOT/scripts/setup-ultimate.sh"
        print_success "Updated scripts/setup-ultimate.sh"
    fi
    
    # Update web package.json
    if [ -f "$PROJECT_ROOT/web/package.json" ]; then
        jq ".version = \"$version\"" "$PROJECT_ROOT/web/package.json" > "$PROJECT_ROOT/web/package.json.tmp" && \
        mv "$PROJECT_ROOT/web/package.json.tmp" "$PROJECT_ROOT/web/package.json"
        print_success "Updated web/package.json"
    fi
    
    # Update Node-RED package.json
    if [ -f "$PROJECT_ROOT/node-red/settings/package.json" ]; then
        jq ".version = \"$version\"" "$PROJECT_ROOT/node-red/settings/package.json" > "$PROJECT_ROOT/node-red/settings/package.json.tmp" && \
        mv "$PROJECT_ROOT/node-red/settings/package.json.tmp" "$PROJECT_ROOT/node-red/settings/package.json"
        print_success "Updated node-red/settings/package.json"
    fi
    
    # Update web VERSION file with git commit hash if available
    if [ -f "$PROJECT_ROOT/web/VERSION" ]; then
        local commit_hash
        if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
            commit_hash=$(git rev-parse --short HEAD)
            echo "v$date_version-$commit_hash" > "$PROJECT_ROOT/web/VERSION"
        else
            echo "v$date_version" > "$PROJECT_ROOT/web/VERSION"
        fi
        print_success "Updated web/VERSION"
    fi
    
    print_success "All components updated to version $version"
}

# Show current versions across all components
show_versions() {
    print_info "Current project versions:"
    echo
    
    # Main version
    local main_version
    main_version=$(get_version)
    echo "📦 Project Version: $main_version"
    echo
    
    # Component versions
    echo "🔧 Component Versions:"
    
    if [ -f "$PROJECT_ROOT/deployment/setup-ultimate.sh" ]; then
        local script_version
        script_version=$(grep 'SCRIPT_VERSION=' "$PROJECT_ROOT/deployment/setup-ultimate.sh" | head -1 | cut -d'"' -f2)
        echo "  • Setup Script (deployment): $script_version"
    fi
    
    if [ -f "$PROJECT_ROOT/scripts/setup-ultimate.sh" ]; then
        local script_version
        script_version=$(grep 'SCRIPT_VERSION=' "$PROJECT_ROOT/scripts/setup-ultimate.sh" | head -1 | cut -d'"' -f2)
        echo "  • Setup Script (scripts): $script_version"
    fi
    
    if [ -f "$PROJECT_ROOT/web/package.json" ]; then
        local web_version
        web_version=$(jq -r '.version' "$PROJECT_ROOT/web/package.json")
        echo "  • Web Dashboard: $web_version"
    fi
    
    if [ -f "$PROJECT_ROOT/web/VERSION" ]; then
        local web_detailed_version
        web_detailed_version=$(cat "$PROJECT_ROOT/web/VERSION")
        echo "  • Web Deployment: $web_detailed_version"
    fi
    
    if [ -f "$PROJECT_ROOT/node-red/settings/package.json" ]; then
        local nodered_version
        nodered_version=$(jq -r '.version' "$PROJECT_ROOT/node-red/settings/package.json")
        echo "  • Node-RED: $nodered_version"
    fi
    
    echo
}

# Main script logic
case "${1:-}" in
    "get")
        get_version
        ;;
    "set")
        if [ -z "${2:-}" ]; then
            print_error "Please specify version (e.g., ./version.sh set 1.2.3)"
            exit 1
        fi
        set_version "$2"
        ;;
    "bump")
        if [ -z "${2:-}" ]; then
            print_error "Please specify bump type: major, minor, or patch"
            exit 1
        fi
        bump_version "$2"
        ;;
    "show"|"status")
        show_versions
        ;;
    "sync")
        local current_version
        current_version=$(get_version)
        update_all_components "$current_version"
        ;;
    *)
        echo "Cocktail Machine Version Manager"
        echo
        echo "Usage: $0 <command> [arguments]"
        echo
        echo "Commands:"
        echo "  get                    Get current project version"
        echo "  set <version>         Set project version (e.g., 1.2.3)"
        echo "  bump <type>           Bump version (major|minor|patch)"
        echo "  show                  Show all component versions"
        echo "  sync                  Sync all components to main version"
        echo
        echo "Examples:"
        echo "  $0 get                # Shows: 1.0.5"
        echo "  $0 set 1.1.0         # Sets version to 1.1.0"
        echo "  $0 bump patch        # 1.0.5 -> 1.0.6"
        echo "  $0 bump minor        # 1.0.5 -> 1.1.0"
        echo "  $0 bump major        # 1.0.5 -> 2.0.0"
        echo "  $0 show              # Lists all versions"
        echo "  $0 sync              # Updates all components"
        echo
        exit 1
        ;;
esac
