#!/bin/bash
# Cocktail Machine Dashboard Update Script
# Downloads and installs dashboard updates from the production repository

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - can be overridden by environment variables
DEPLOY_REPO=${DEPLOY_REPO:-"sebastienlepoder/cocktail-machine-prod"}
BRANCH=${BRANCH:-"main"}
WEBROOT=${WEBROOT:-"/opt/webroot"}
BACKUP_DIR=${BACKUP_DIR:-"/opt/backup"}
SCRIPTS_DIR=${SCRIPTS_DIR:-"/opt/scripts"}
SERVICE_NAME=${SERVICE_NAME:-"cocktail-machine-dev"}

# Create directories if they don't exist
mkdir -p "$WEBROOT" "$BACKUP_DIR" "$SCRIPTS_DIR"

# Logging functions
print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_step() { echo -e "${BLUE}►${NC} $1"; }

# Function to get current installed version
get_current_version() {
    if [ -f "$WEBROOT/VERSION" ]; then
        cat "$WEBROOT/VERSION"
    else
        echo "v0.0.0"
    fi
}

# Function to get latest available version
get_latest_version() {
    local versions_url="https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/web/versions.json"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s "$versions_url" | jq -r '.dashboard.latest' 2>/dev/null || echo "unknown"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$versions_url" | jq -r '.dashboard.latest' 2>/dev/null || echo "unknown"
    else
        print_error "Neither curl nor wget is available"
        return 1
    fi
}

# Function to compare versions (simple string comparison for our format)
version_greater() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -n1)" != "$1" ]
}

# Function to create backup
create_backup() {
    local current_version="$1"
    local backup_name="dashboard_backup_${current_version}_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    print_step "Creating backup: $backup_name"
    
    if [ -d "$WEBROOT" ] && [ "$(find "$WEBROOT" -mindepth 1 -type f | wc -l)" -gt 0 ]; then
        mkdir -p "$backup_path"
        cp -r "$WEBROOT/." "$backup_path/"
        print_status "Backup created at $backup_path"
        
        # Keep only last 5 backups
        cd "$BACKUP_DIR"
        ls -t dashboard_backup_* 2>/dev/null | tail -n +6 | xargs -r rm -rf
        print_info "Cleaned old backups (keeping last 5)"
    else
        print_info "No existing files to backup"
    fi
}

# Function to download and extract update
download_and_extract() {
    local version="$1"
    local temp_dir=$(mktemp -d)
    local archive_url="https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/web.tar.gz"
    
    print_step "Downloading update package..."
    
    cd "$temp_dir"
    
    if command -v curl >/dev/null 2>&1; then
        curl -L -o web.tar.gz "$archive_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O web.tar.gz "$archive_url"
    else
        print_error "Neither curl nor wget is available"
        rm -rf "$temp_dir"
        return 1
    fi
    
    if [ ! -f "web.tar.gz" ] || [ ! -s "web.tar.gz" ]; then
        print_error "Failed to download update package"
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_step "Extracting update package..."
    tar -xzf web.tar.gz
    
    if [ ! -d "web" ]; then
        print_error "Invalid package format - no web directory found"
        rm -rf "$temp_dir"
        return 1
    fi
    
    print_step "Installing update..."
    
    # Clear webroot and install new files
    rm -rf "$WEBROOT"/*
    cp -r web/* "$WEBROOT/"
    
    # Also copy to Docker web directory if it exists
    DOCKER_WEB_DIR="/home/pi/cocktail-machine-dev/web"
    if [ -d "$DOCKER_WEB_DIR" ]; then
        print_info "Updating Docker web directory"
        rm -rf "$DOCKER_WEB_DIR"/*
        cp -r web/* "$DOCKER_WEB_DIR/"
        chown -R pi:pi "$DOCKER_WEB_DIR" 2>/dev/null || true
        chmod -R 755 "$DOCKER_WEB_DIR"
        
        # Restart Docker web container if docker-compose is available
        if [ -f "/home/pi/cocktail-machine-dev/deployment/docker-compose.yml" ]; then
            print_info "Restarting Docker web container"
            cd /home/pi/cocktail-machine-dev/deployment
            docker-compose restart web-dashboard 2>/dev/null || true
        fi
    fi
    
    # Set proper permissions for webroot
    chown -R www-data:www-data "$WEBROOT" 2>/dev/null || true
    chmod -R 755 "$WEBROOT"
    
    print_status "Update extracted and installed"
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Function to restart web services
restart_services() {
    print_step "Restarting web services..."
    
    # Try different service restart methods
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx
            print_status "Nginx reloaded"
        fi
        
        if systemctl is-active --quiet apache2; then
            systemctl reload apache2
            print_status "Apache reloaded"
        fi
        
        # Restart Docker services if they exist
        if [ -f ~/cocktail-machine-dev/deployment/docker-compose.yml ]; then
            cd ~/cocktail-machine-dev/deployment
            docker-compose restart web-dashboard 2>/dev/null || true
            print_info "Docker services restarted"
        fi
        
    else
        # Fallback for systems without systemctl
        /etc/init.d/nginx reload 2>/dev/null || true
        /etc/init.d/apache2 reload 2>/dev/null || true
    fi
    
    print_status "Services restarted"
}

# Function to verify installation
verify_installation() {
    local expected_version="$1"
    
    print_step "Verifying installation..."
    
    if [ ! -f "$WEBROOT/VERSION" ]; then
        print_error "VERSION file not found after installation"
        return 1
    fi
    
    local installed_version=$(cat "$WEBROOT/VERSION")
    
    if [ "$installed_version" = "$expected_version" ]; then
        print_status "Installation verified - version $installed_version"
        return 0
    else
        print_error "Version mismatch: expected $expected_version, got $installed_version"
        return 1
    fi
}

# Function to send update notification
send_notification() {
    local message="$1"
    
    # Send MQTT notification if mosquitto_pub is available
    if command -v mosquitto_pub >/dev/null 2>&1; then
        mosquitto_pub -h localhost -t "cocktail/system/update" -m "{\"status\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}" 2>/dev/null || true
    fi
    
    # Log to syslog
    logger -t cocktail-update "$message"
}

# Main update function
perform_update() {
    local target_version="$1"
    local current_version=$(get_current_version)
    
    print_info "Current version: $current_version"
    print_info "Target version: $target_version"
    
    if [ "$current_version" = "$target_version" ]; then
        print_status "Already up to date!"
        return 0
    fi
    
    # Create backup
    create_backup "$current_version"
    
    # Download and install update
    if download_and_extract "$target_version"; then
        if verify_installation "$target_version"; then
            restart_services
            send_notification "Update completed successfully to $target_version"
            print_status "Update completed successfully!"
            print_info "Updated from $current_version to $target_version"
            return 0
        else
            print_error "Installation verification failed"
            return 1
        fi
    else
        print_error "Update installation failed"
        return 1
    fi
}

# Function to check for updates
check_updates() {
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    print_info "Current version: $current_version"
    print_info "Latest version: $latest_version"
    
    if [ "$latest_version" = "unknown" ]; then
        print_error "Unable to check for updates"
        return 1
    fi
    
    if [ "$current_version" = "$latest_version" ]; then
        print_status "System is up to date"
        return 1  # No updates available
    else
        print_info "Update available: $current_version → $latest_version"
        return 0  # Updates available
    fi
}

# Function to display help
show_help() {
    cat << EOF
Cocktail Machine Dashboard Update Script

Usage: $0 [options] [version]

Options:
    -c, --check         Check for updates without installing
    -h, --help          Show this help message
    -f, --force         Force update even if versions match
    
Arguments:
    version            Specific version to install (optional)
                      If not specified, installs latest version

Environment Variables:
    DEPLOY_REPO        GitHub repository (default: sebastienlepoder/cocktail-machine-prod)
    BRANCH             Branch to use (default: main)
    WEBROOT            Web root directory (default: /opt/webroot)
    BACKUP_DIR         Backup directory (default: /opt/backup)
    
Examples:
    $0                              # Update to latest version
    $0 v2025.09.07-abc123f         # Update to specific version
    $0 --check                     # Check for updates only
    $0 --force                     # Force update

EOF
}

# Main script execution
main() {
    local check_only=false
    local force_update=false
    local target_version=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check)
                check_only=true
                shift
                ;;
            -f|--force)
                force_update=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                target_version="$1"
                shift
                ;;
        esac
    done
    
    # Ensure we're running as root for system operations
    if [ "$EUID" -ne 0 ] && [ -w "/opt" ]; then
        print_error "This script requires root privileges"
        print_info "Please run with: sudo $0 $*"
        exit 1
    fi
    
    print_step "Cocktail Machine Dashboard Update"
    print_info "Repository: $DEPLOY_REPO"
    
    # Install required tools if missing
    if ! command -v jq >/dev/null 2>&1; then
        print_step "Installing required tools..."
        apt-get update -qq
        apt-get install -y jq
    fi
    
    if [ "$check_only" = true ]; then
        check_updates
        exit $?
    fi
    
    # Determine target version
    if [ -z "$target_version" ]; then
        target_version=$(get_latest_version)
        if [ "$target_version" = "unknown" ]; then
            print_error "Unable to determine latest version"
            exit 1
        fi
    fi
    
    # Check if update is needed (unless forced)
    if [ "$force_update" = false ]; then
        current_version=$(get_current_version)
        if [ "$current_version" = "$target_version" ]; then
            print_status "Already up to date ($current_version)"
            exit 0
        fi
    fi
    
    # Perform the update
    if perform_update "$target_version"; then
        print_status "Update completed successfully!"
        exit 0
    else
        print_error "Update failed!"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
