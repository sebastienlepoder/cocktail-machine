#!/bin/bash

# Emergency dashboard restore script
# This will restore your actual web dashboard

echo "==================================================="
echo "🔄 Restoring Your Web Dashboard"
echo "==================================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_step() { echo -e "${BLUE}►${NC} $1"; }

WEBROOT_DIR="/opt/webroot"
DEPLOY_REPO="sebastienlepoder/cocktail-machine-dev"

print_step "1. Backing up current dashboard"
if [ -f "$WEBROOT_DIR/index.html" ]; then
    sudo cp "$WEBROOT_DIR/index.html" "$WEBROOT_DIR/index.html.backup"
    print_status "Current dashboard backed up"
fi

print_step "2. Trying to restore your web dashboard"

cd /tmp
rm -rf dashboard_restore
mkdir -p dashboard_restore
cd dashboard_restore

print_info "Method 1: Checking for dashboard release packages..."
DASHBOARD_URL="https://api.github.com/repos/$DEPLOY_REPO/releases/latest"

if curl -s "$DASHBOARD_URL" | jq -r '.assets[].name' | grep -q "dashboard"; then
    PACKAGE_URL=$(curl -s "$DASHBOARD_URL" | jq -r '.assets[] | select(.name | contains("dashboard")) | .browser_download_url' | head -1)
    print_info "Found dashboard package: $PACKAGE_URL"
    
    if curl -L -o dashboard.tar.gz "$PACKAGE_URL"; then
        print_info "Extracting dashboard..."
        tar -xzf dashboard.tar.gz
        
        if [ -f "index.html" ] || [ -d "dashboard" ]; then
            print_info "Installing dashboard files..."
            if [ -d "dashboard" ]; then
                sudo cp -rv dashboard/* "$WEBROOT_DIR/"
            else
                sudo cp -rv * "$WEBROOT_DIR/"
            fi
            print_status "Dashboard restored from release package!"
            RESTORED=true
        fi
    fi
fi

if [ "$RESTORED" != "true" ]; then
    print_info "Method 2: Downloading from web directory in repository..."
    
    WEB_URL="https://api.github.com/repos/$DEPLOY_REPO/contents/web"
    if curl -s "$WEB_URL" | jq -r '.[].name' | grep -q "html\|js\|css"; then
        print_info "Found web files in repository"
        
        # Create a list of files to download
        curl -s "$WEB_URL" | jq -r '.[] | select(.type == "file") | "\(.name),\(.download_url)"' > files_to_download.txt
        
        while IFS=',' read -r name url; do
            if [[ "$url" != "null" && "$name" =~ \.(html|js|css|json|ico|png|jpg|gif)$ ]]; then
                print_info "Downloading $name..."
                curl -L -o "$name" "$url"
            fi
        done < files_to_download.txt
        
        # Check if we got any files
        if [ "$(ls -A . | grep -E '\.(html|js|css)$')" ]; then
            print_info "Installing downloaded files..."
            sudo cp -v * "$WEBROOT_DIR/" 2>/dev/null || true
            print_status "Dashboard restored from repository!"
            RESTORED=true
        fi
    fi
fi

if [ "$RESTORED" != "true" ]; then
    print_info "Method 3: Downloading specific known dashboard files..."
    
    # List of common dashboard files to try
    FILES="index.html app.js app.css dashboard.html main.js main.css style.css"
    
    for file in $FILES; do
        FILE_URL="https://raw.githubusercontent.com/$DEPLOY_REPO/main/web/$file"
        print_info "Trying to download $file..."
        if curl -L -o "$file" "$FILE_URL" 2>/dev/null && [ -s "$file" ]; then
            print_info "Downloaded $file successfully"
            sudo cp "$file" "$WEBROOT_DIR/"
            RESTORED=true
        fi
    done
fi

if [ "$RESTORED" != "true" ]; then
    print_error "Could not restore your original dashboard automatically"
    print_info "Your dashboard backup is at: $WEBROOT_DIR/index.html.backup"
    print_info "You may need to manually deploy your dashboard"
    
    print_step "3. Available options:"
    echo "Option 1: Use the update script to get latest dashboard:"
    echo "  sudo /opt/scripts/update_dashboard.sh"
    echo
    echo "Option 2: Manual deployment from your web directory"
    echo "  Copy your built dashboard files to: $WEBROOT_DIR"
    echo
    echo "Option 3: Check if your dashboard is in the packages directory:"
    ls -la /opt/webroot/../packages/ 2>/dev/null || echo "  No packages directory found"
    
else
    print_step "3. Setting proper permissions"
    sudo chown -R www-data:www-data "$WEBROOT_DIR"
    sudo chmod -R 755 "$WEBROOT_DIR"
    sudo find "$WEBROOT_DIR" -type f -exec chmod 644 {} \;
    
    print_step "4. Restarting nginx"
    sudo systemctl restart nginx
    
    print_step "5. Testing dashboard"
    sleep 2
    if curl -s http://localhost | grep -q "html\|HTML"; then
        print_status "Dashboard is working!"
    else
        print_error "Dashboard may not be working properly"
    fi
fi

print_step "Current dashboard status:"
echo "Files in webroot:"
ls -la "$WEBROOT_DIR/" | head -10

echo "Testing dashboard accessibility:"
curl -s http://localhost | head -5

# Clean up
cd /
rm -rf /tmp/dashboard_restore

echo
echo "==================================================="
echo "🔄 Dashboard restore attempt completed"
echo "==================================================="

if [ "$RESTORED" = "true" ]; then
    echo "✅ Your dashboard should be restored!"
    echo "Visit: http://$(hostname -I | awk '{print $1}')"
else
    echo "❌ Could not automatically restore dashboard"
    echo "Please check the options listed above"
fi
