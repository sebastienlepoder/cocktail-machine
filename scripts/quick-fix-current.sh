#!/bin/bash

# Quick fix script for current broken installation
# Run this on the Pi to fix the most critical issues

echo "==================================================="
echo "🔧 Cocktail Machine Quick Fix Script"
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

# 1. Fix nginx configuration issue
print_step "1. Fixing nginx configuration..."
print_info "Removing broken symlinks..."
sudo rm -f /etc/nginx/sites-enabled/sites-available
sudo rm -f /etc/nginx/sites-enabled/default

print_info "Creating proper symlink..."
sudo ln -sf /etc/nginx/sites-available/cocktail-machine /etc/nginx/sites-enabled/cocktail-machine

print_info "Testing nginx configuration..."
if sudo nginx -t 2>/dev/null; then
    print_status "Nginx configuration fixed"
else
    print_error "Nginx config still has issues - checking further..."
    sudo nginx -t
fi

# 2. Create missing cocktail images
print_step "2. Creating missing cocktail images..."
sudo mkdir -p /opt/webroot/src/assets

# Create simple text-based placeholders
print_info "Creating mojito.jpg..."
echo "🍹 Mojito Placeholder Image" | sudo tee /opt/webroot/src/assets/mojito.jpg > /dev/null

print_info "Creating old-fashioned.jpg..."
echo "🥃 Old Fashioned Placeholder Image" | sudo tee /opt/webroot/src/assets/old-fashioned.jpg > /dev/null

print_info "Creating whiskey-sour.jpg..."
echo "🍋 Whiskey Sour Placeholder Image" | sudo tee /opt/webroot/src/assets/whiskey-sour.jpg > /dev/null

# Set proper permissions
sudo chown www-data:www-data /opt/webroot/src/assets/*.jpg
sudo chmod 644 /opt/webroot/src/assets/*.jpg

print_status "Cocktail images created"

# 3. Fix mosquitto permissions
print_step "3. Fixing mosquitto permissions..."
if [ -d "/home/$USER/cocktail-machine/mosquitto" ]; then
    print_info "Fixing ownership..."
    sudo chown -R $USER:$USER /home/$USER/cocktail-machine/
    
    print_info "Setting permissions..."
    chmod -R 755 /home/$USER/cocktail-machine/mosquitto/
    
    print_status "Mosquitto permissions fixed"
else
    print_info "Mosquitto directory not found, skipping..."
fi

# 4. Restart nginx
print_step "4. Restarting nginx..."
sudo systemctl stop nginx 2>/dev/null
sudo pkill nginx 2>/dev/null || true
sleep 2

if sudo systemctl start nginx; then
    print_status "Nginx started successfully"
else
    print_error "Failed to start nginx via systemctl, trying direct start..."
    if sudo nginx; then
        print_status "Nginx started directly"
    else
        print_error "Failed to start nginx - check logs with: sudo journalctl -u nginx"
    fi
fi

# 5. Restart Docker containers
print_step "5. Restarting Docker containers..."
cd /home/$USER/cocktail-machine 2>/dev/null || {
    print_error "Cocktail machine directory not found"
    exit 1
}

if command -v docker-compose &> /dev/null; then
    docker-compose restart
    print_status "Docker containers restarted"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose restart
    print_status "Docker containers restarted"
else
    print_error "Docker compose not available"
fi

# 6. Test services
print_step "6. Testing services..."

print_info "Testing nginx..."
if curl -s http://localhost >/dev/null 2>&1; then
    print_status "Nginx is responding"
else
    print_error "Nginx not responding"
fi

print_info "Testing nginx health check..."
if curl -s http://localhost/health | grep -q "healthy"; then
    print_status "Health check working"
else
    print_error "Health check not working"
fi

print_info "Testing Node-RED..."
if curl -s http://localhost:1880 >/dev/null 2>&1; then
    print_status "Node-RED is responding"
else
    print_error "Node-RED not responding"
fi

# 7. Show current status
print_step "7. Current status..."
echo "Services:"
echo "  • Nginx: $(pgrep nginx >/dev/null && echo 'Running' || echo 'Not running')"
echo "  • Docker: $(pgrep dockerd >/dev/null && echo 'Running' || echo 'Not running')"

echo "Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "Docker not accessible"

echo "Files:"
echo "  • Dashboard: $([ -f /opt/webroot/index.html ] && echo 'Present' || echo 'Missing')"
echo "  • Cocktail images: $(ls /opt/webroot/src/assets/*.jpg 2>/dev/null | wc -l) files"

print_step "8. Recommendations..."
echo "If issues persist:"
echo "  1. Run the debug script: curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-machine-dev/main/scripts/debug-installation.sh | bash"
echo "  2. Check nginx logs: sudo tail -20 /var/log/nginx/error.log"
echo "  3. Check container logs: docker logs cocktail-nodered"
echo "  4. Reboot the system: sudo reboot"

echo
echo "==================================================="
echo "🔧 Quick fix completed!"
echo "==================================================="
