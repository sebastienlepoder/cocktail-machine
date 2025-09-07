#!/bin/bash
# Quick Update Script for Cocktail Machine
# This script installs/updates the main update system

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_step() { echo -e "${BLUE}►${NC} $1"; }

# Configuration
DEPLOY_REPO=${DEPLOY_REPO:-"sebastienlepoder/cocktail-machine-prod"}
BRANCH=${BRANCH:-"main"}
SCRIPTS_DIR="/opt/scripts"

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    print_info "Please run: sudo $0"
    exit 1
fi

print_step "🍹 Cocktail Machine - Quick Update Setup"

# Create scripts directory
print_step "Creating scripts directory..."
mkdir -p "$SCRIPTS_DIR"

# Download the main update script
print_step "Downloading update script..."
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/scripts/update_dashboard.sh"

if command -v curl >/dev/null 2>&1; then
    curl -L -o "$SCRIPTS_DIR/update_dashboard.sh" "$UPDATE_SCRIPT_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$SCRIPTS_DIR/update_dashboard.sh" "$UPDATE_SCRIPT_URL"
else
    print_error "Neither curl nor wget is available"
    print_info "Please install curl or wget and try again"
    exit 1
fi

# Make it executable
chmod +x "$SCRIPTS_DIR/update_dashboard.sh"

print_status "Update script installed successfully!"

# Test the script
print_step "Testing update script..."
if "$SCRIPTS_DIR/update_dashboard.sh" --check; then
    print_status "Update script is working correctly!"
else
    print_info "Update check completed (this is normal for first run)"
fi

print_status "Setup completed!"
print_info ""
print_info "🎉 Your update system is now ready!"
print_info ""
print_info "You can now:"
print_info "• Use Node-RED dashboard Updates tab"
print_info "• Run: sudo /opt/scripts/update_dashboard.sh"
print_info "• Check for updates: sudo /opt/scripts/update_dashboard.sh --check"
print_info ""
print_info "The update script will automatically:"
print_info "✓ Download updates from the production repository"
print_info "✓ Create backups before updating"
print_info "✓ Install new dashboard versions"
print_info "✓ Restart web services"
print_info "✓ Verify installations"
