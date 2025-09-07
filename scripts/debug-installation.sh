#!/bin/bash

# Debug script for Cocktail Machine installation issues
# Run this on the Pi to diagnose problems

echo "==================================================="
echo "🔍 Cocktail Machine Installation Diagnostics"
echo "==================================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() { echo -e "\n${BLUE}► $1${NC}"; }
print_info() { echo -e "${YELLOW}  $1${NC}"; }
print_good() { echo -e "${GREEN}  ✓ $1${NC}"; }
print_bad() { echo -e "${RED}  ✗ $1${NC}"; }

print_section "1. Nginx Configuration Issues"
print_info "Checking nginx sites configuration..."
echo "Sites-available directory:"
ls -la /etc/nginx/sites-available/
echo
echo "Sites-enabled directory:"
ls -la /etc/nginx/sites-enabled/
echo
echo "Current nginx configuration test:"
sudo nginx -t 2>&1 || true
echo

print_section "2. Dashboard Files Status"
print_info "Checking webroot directory..."
echo "Webroot contents:"
ls -la /opt/webroot/
echo
print_info "Checking for cocktail images..."
echo "src/assets directory:"
ls -la /opt/webroot/src/assets/ 2>/dev/null || echo "Directory does not exist"
echo "assets directory:"
ls -la /opt/webroot/assets/ 2>/dev/null || echo "Directory does not exist"
echo
print_info "Checking specific cocktail images..."
for img in mojito.jpg old-fashioned.jpg whiskey-sour.jpg; do
    if [ -f "/opt/webroot/src/assets/$img" ]; then
        print_good "/opt/webroot/src/assets/$img exists ($(stat -c%s /opt/webroot/src/assets/$img) bytes)"
    else
        print_bad "/opt/webroot/src/assets/$img missing"
    fi
done

print_section "3. Mosquitto Permission Issues"
print_info "Checking mosquitto directory permissions..."
echo "Mosquitto directory structure:"
ls -la /home/$USER/cocktail-machine/mosquitto/ 2>/dev/null || echo "Directory does not exist"
echo
echo "Mosquitto subdirectories:"
ls -la /home/$USER/cocktail-machine/mosquitto/*/ 2>/dev/null || true
echo
echo "Current user and groups:"
echo "User: $(whoami)"
echo "Groups: $(groups)"
echo "UID/GID: $(id)"

print_section "4. Docker and Node-RED Status"
print_info "Checking Docker containers..."
echo "Container status:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo
print_info "Node-RED container logs (last 20 lines):"
docker logs cocktail-nodered --tail 20 2>/dev/null || echo "Container not found or no logs"
echo
print_info "MQTT container logs (last 10 lines):"
docker logs cocktail-mqtt --tail 10 2>/dev/null || echo "Container not found or no logs"

print_section "5. System Process Status"
print_info "Checking running processes..."
echo "Nginx processes:"
pgrep -l nginx || echo "No nginx processes running"
echo
echo "Docker processes:"
pgrep -l docker || echo "No docker processes running"

print_section "6. Network and Port Status"
print_info "Checking port bindings..."
echo "Port 80 (nginx):"
sudo netstat -tlnp | grep :80 || echo "Port 80 not bound"
echo "Port 1880 (Node-RED):"
sudo netstat -tlnp | grep :1880 || echo "Port 1880 not bound"
echo "Port 1883 (MQTT):"
sudo netstat -tlnp | grep :1883 || echo "Port 1883 not bound"

print_section "7. File System and Permissions"
print_info "Checking webroot permissions..."
stat /opt/webroot/
echo
print_info "Checking cocktail-machine directory ownership..."
stat /home/$USER/cocktail-machine/ 2>/dev/null || echo "Directory does not exist"

print_section "8. Nginx Error Logs"
print_info "Recent nginx errors (last 10 lines):"
sudo tail -10 /var/log/nginx/error.log 2>/dev/null || echo "No nginx error log found"

print_section "9. System Resources"
print_info "Disk space:"
df -h /opt /home
echo
print_info "Memory usage:"
free -h

print_section "10. Quick Fixes to Try"
print_info "Suggested commands to run:"
echo "1. Fix nginx sites configuration:"
echo "   sudo rm -f /etc/nginx/sites-enabled/sites-available"
echo "   sudo ln -sf /etc/nginx/sites-available/cocktail-machine /etc/nginx/sites-enabled/"
echo
echo "2. Create missing cocktail images:"
echo "   sudo mkdir -p /opt/webroot/src/assets"
echo "   echo 'placeholder' | sudo tee /opt/webroot/src/assets/mojito.jpg"
echo "   echo 'placeholder' | sudo tee /opt/webroot/src/assets/old-fashioned.jpg"
echo "   echo 'placeholder' | sudo tee /opt/webroot/src/assets/whiskey-sour.jpg"
echo
echo "3. Fix mosquitto permissions:"
echo "   sudo chown -R $USER:$USER /home/$USER/cocktail-machine/"
echo
echo "4. Restart services:"
echo "   sudo systemctl restart nginx"
echo "   docker-compose -f /home/$USER/cocktail-machine/docker-compose.yml restart"

echo
echo "==================================================="
echo "🔍 Diagnostics Complete"
echo "==================================================="
