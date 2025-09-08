#!/bin/bash

# Comprehensive fix for black screen dashboard and Node-RED issues
echo "==================================================="
echo "🔧 Fixing Dashboard Black Screen & Node-RED Issues"
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
PROJECT_DIR="/home/$USER/cocktail-machine"

print_step "1. Diagnosing dashboard black screen issue"

print_info "Checking dashboard files..."
echo "Files in webroot:"
ls -la "$WEBROOT_DIR/" 2>/dev/null || echo "Webroot directory not accessible"

print_info "Checking index.html content..."
if [ -f "$WEBROOT_DIR/index.html" ]; then
    echo "File exists, size: $(stat -c%s "$WEBROOT_DIR/index.html") bytes"
    echo "First 10 lines of index.html:"
    head -10 "$WEBROOT_DIR/index.html"
    
    # Check if it's a proper HTML file
    if head -5 "$WEBROOT_DIR/index.html" | grep -q "<!DOCTYPE\|<html\|<HTML"; then
        print_status "index.html appears to be valid HTML"
    else
        print_error "index.html doesn't look like proper HTML"
        echo "Content:"
        cat "$WEBROOT_DIR/index.html"
    fi
else
    print_error "index.html not found!"
fi

print_info "Checking nginx configuration and status..."
echo "Nginx status: $(systemctl is-active nginx 2>/dev/null || echo 'inactive')"
echo "Nginx process: $(pgrep nginx >/dev/null && echo 'running' || echo 'not running')"

print_info "Testing nginx response..."
RESPONSE=$(curl -s http://localhost 2>/dev/null || echo "connection_failed")
echo "Response length: ${#RESPONSE} characters"
if [ ${#RESPONSE} -lt 50 ]; then
    echo "Response content: $RESPONSE"
fi

print_step "2. Fixing dashboard issues"

# Check if we got the wrong files
print_info "Checking if downloaded files are correct..."
if [ -f "$WEBROOT_DIR/index.html" ] && [ -s "$WEBROOT_DIR/index.html" ]; then
    if grep -q "versions.json\|dashboard-version.json" "$WEBROOT_DIR/index.html"; then
        print_error "It looks like we downloaded metadata files instead of the actual dashboard!"
        print_info "Let's try to get the real dashboard files..."
        
        # Try to download the actual built dashboard
        cd /tmp
        rm -rf dashboard_fix
        mkdir dashboard_fix
        cd dashboard_fix
        
        print_info "Attempting to download actual dashboard from releases..."
        # Try different approaches to get the real dashboard
        
        # Method 1: Check for built dashboard in releases
        RELEASES_URL="https://api.github.com/repos/sebastienlepoder/cocktail-machine-dev/releases/latest"
        if curl -s "$RELEASES_URL" | grep -q "browser_download_url"; then
            print_info "Found releases, looking for dashboard package..."
            PACKAGE_URL=$(curl -s "$RELEASES_URL" | jq -r '.assets[] | select(.name | contains("dashboard")) | .browser_download_url' | head -1)
            if [ "$PACKAGE_URL" != "null" ] && [ -n "$PACKAGE_URL" ]; then
                print_info "Downloading: $PACKAGE_URL"
                if curl -L -o dashboard.tar.gz "$PACKAGE_URL" && tar -xzf dashboard.tar.gz; then
                    if [ -f "index.html" ] && grep -q "<html\|<!DOCTYPE" "index.html"; then
                        print_info "Found proper HTML dashboard, installing..."
                        sudo cp -v * "$WEBROOT_DIR/"
                        print_status "Dashboard updated from release package"
                    fi
                fi
            fi
        fi
        
        # Method 2: Try to get from web packages directory
        if ! grep -q "<html\|<!DOCTYPE" "$WEBROOT_DIR/index.html" 2>/dev/null; then
            print_info "Trying to download from web packages..."
            PACKAGES_URL="https://api.github.com/repos/sebastienlepoder/cocktail-machine-dev/contents/web/packages"
            if curl -s "$PACKAGES_URL" | jq -r '.[].download_url' | head -1 | grep -q "http"; then
                PACKAGE_URL=$(curl -s "$PACKAGES_URL" | jq -r '.[] | select(.name | contains("dashboard")) | .download_url' | head -1)
                if [ "$PACKAGE_URL" != "null" ] && [ -n "$PACKAGE_URL" ]; then
                    print_info "Downloading package: $PACKAGE_URL"
                    if curl -L -o package.tar.gz "$PACKAGE_URL" && tar -xzf package.tar.gz; then
                        if [ -f "index.html" ] && grep -q "<html\|<!DOCTYPE" "index.html"; then
                            sudo cp -v * "$WEBROOT_DIR/"
                            print_status "Dashboard updated from packages"
                        fi
                    fi
                fi
            fi
        fi
        
        cd /
        rm -rf /tmp/dashboard_fix
    fi
fi

# If still no proper dashboard, create a working temporary one
if ! grep -q "<html\|<!DOCTYPE" "$WEBROOT_DIR/index.html" 2>/dev/null; then
    print_info "Creating a working temporary dashboard..."
    sudo tee "$WEBROOT_DIR/index.html" > /dev/null << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🍹 Cocktail Machine</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            max-width: 800px;
            padding: 40px;
            text-align: center;
        }
        .logo {
            font-size: 120px;
            margin-bottom: 30px;
            animation: float 3s ease-in-out infinite;
        }
        h1 {
            font-size: 48px;
            margin-bottom: 20px;
            font-weight: 300;
        }
        .status {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .buttons {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-top: 30px;
        }
        .button {
            display: block;
            background: rgba(255,255,255,0.2);
            color: white;
            padding: 15px 20px;
            border-radius: 8px;
            text-decoration: none;
            transition: all 0.3s;
            border: 2px solid rgba(255,255,255,0.3);
        }
        .button:hover {
            background: rgba(255,255,255,0.3);
            transform: translateY(-2px);
        }
        .primary {
            background: rgba(255,107,107,0.3);
            border-color: #ff6b6b;
        }
        .primary:hover {
            background: rgba(255,107,107,0.5);
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-20px); }
        }
        .info { margin-top: 20px; font-size: 14px; opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine Dashboard</h1>
        <p>Your cocktail machine control system</p>
        
        <div class="status">
            <h3>🎯 System Status</h3>
            <p id="status">Checking services...</p>
        </div>
        
        <div class="buttons">
            <a href="http://localhost:1880/ui" class="button primary">🔴 Node-RED Dashboard</a>
            <a href="http://localhost:1880/admin" class="button">⚙️ Node-RED Editor</a>
            <a href="/health" class="button">❤️ Health Check</a>
            <a href="javascript:location.reload()" class="button">🔄 Refresh</a>
        </div>
        
        <div class="info">
            <p>This is a working dashboard. Your full dashboard will be available after proper deployment.</p>
            <p>IP Address: <span id="ip">Loading...</span></p>
        </div>
    </div>
    
    <script>
        // Check services status
        function checkServices() {
            fetch('/health')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('status').innerHTML = '✅ Web server is running';
                })
                .catch(err => {
                    document.getElementById('status').innerHTML = '⚠️ Checking services...';
                });
                
            fetch('http://localhost:1880')
                .then(response => {
                    if (response.ok) {
                        document.getElementById('status').innerHTML += '<br>✅ Node-RED is running';
                    }
                })
                .catch(err => {
                    document.getElementById('status').innerHTML += '<br>❌ Node-RED not accessible';
                });
        }
        
        // Get IP address
        fetch('http://httpbin.org/ip')
            .then(response => response.json())
            .then(data => {
                document.getElementById('ip').textContent = data.origin;
            })
            .catch(err => {
                document.getElementById('ip').textContent = 'Unable to determine';
            });
            
        // Check services on load
        setTimeout(checkServices, 1000);
        setInterval(checkServices, 30000); // Check every 30 seconds
    </script>
</body>
</html>
HTML_EOF
    print_status "Created working dashboard"
fi

print_step "3. Fixing Node-RED issues"

print_info "Checking Docker and Node-RED status..."
echo "Docker status: $(systemctl is-active docker 2>/dev/null || echo 'inactive')"

if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    echo "Container status:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not accessible"
    
    print_info "Checking Node-RED container logs..."
    if docker ps -a | grep -q "cocktail-nodered"; then
        echo "Last 10 lines of Node-RED logs:"
        docker logs cocktail-nodered --tail 10 2>/dev/null || echo "Cannot access container logs"
    else
        print_error "cocktail-nodered container not found"
    fi
    
    print_info "Attempting to restart Node-RED container..."
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose restart nodered 2>/dev/null || echo "Docker-compose restart failed"
    elif docker compose version >/dev/null 2>&1; then
        docker compose restart nodered 2>/dev/null || echo "Docker compose restart failed"
    else
        print_info "Trying direct docker restart..."
        docker restart cocktail-nodered 2>/dev/null || echo "Direct restart failed"
    fi
    
    print_info "Waiting for Node-RED to start..."
    sleep 10
    
    print_info "Testing Node-RED accessibility..."
    for i in {1..5}; do
        if curl -s http://localhost:1880 >/dev/null 2>&1; then
            print_status "Node-RED is now accessible!"
            break
        else
            echo "Attempt $i/5: Node-RED not ready yet..."
            sleep 3
        fi
    done
else
    print_error "Project directory $PROJECT_DIR not found"
    print_info "Need to recreate Node-RED setup..."
    
    # Recreate basic Node-RED setup
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    cat > docker-compose.yml << 'DOCKER_EOF'
version: '3.8'

services:
  nodered:
    image: nodered/node-red:latest
    container_name: cocktail-nodered
    restart: unless-stopped
    ports:
      - "1880:1880"
    volumes:
      - ./nodered/data:/data
    environment:
      - TZ=Europe/Paris
    networks:
      - cocktail-network

  mqtt:
    image: eclipse-mosquitto:latest
    container_name: cocktail-mqtt
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto/config:/mosquitto/config
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log
    networks:
      - cocktail-network

networks:
  cocktail-network:
    driver: bridge
DOCKER_EOF

    # Create directories and basic config
    mkdir -p mosquitto/{config,data,log} nodered/data
    
    # Create basic mosquitto config
    cat > mosquitto/config/mosquitto.conf << 'MQTT_EOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
MQTT_EOF

    # Set permissions
    sudo chown -R $USER:$USER "$PROJECT_DIR"
    sudo chown -R 1000:1000 "$PROJECT_DIR/nodered/data"
    
    print_info "Starting Docker containers..."
    if command -v docker-compose >/dev/null 2>&1; then
        docker-compose up -d
    elif docker compose version >/dev/null 2>&1; then
        docker compose up -d
    else
        print_error "Docker Compose not available"
    fi
fi

print_step "4. Final system checks and fixes"

print_info "Setting proper permissions..."
sudo chown -R www-data:www-data "$WEBROOT_DIR"
sudo chmod -R 755 "$WEBROOT_DIR"
sudo find "$WEBROOT_DIR" -type f -exec chmod 644 {} \;

print_info "Restarting nginx..."
sudo systemctl restart nginx
sleep 2

print_info "Final status check..."
echo "Services:"
echo "  • Nginx: $(systemctl is-active nginx 2>/dev/null || echo 'inactive')"
echo "  • Docker: $(systemctl is-active docker 2>/dev/null || echo 'inactive')"
echo "  • Dashboard: $(curl -s http://localhost >/dev/null 2>&1 && echo 'responding' || echo 'not responding')"
echo "  • Node-RED: $(curl -s http://localhost:1880 >/dev/null 2>&1 && echo 'responding' || echo 'not responding')"

print_info "Dashboard test:"
RESPONSE=$(curl -s http://localhost 2>/dev/null)
if echo "$RESPONSE" | grep -q "<html\|<!DOCTYPE"; then
    print_status "Dashboard is serving HTML content"
else
    print_error "Dashboard not serving proper HTML"
    echo "Response: ${RESPONSE:0:200}"
fi

echo
echo "==================================================="
echo "🔧 Fix attempt completed!"
echo "==================================================="
echo
echo "🌍 Try accessing your dashboard now:"
echo "   http://$(hostname -I | awk '{print $1}')"
echo
echo "🔴 Try accessing Node-RED:"
echo "   http://$(hostname -I | awk '{print $1}'):1880"
echo
echo "📋 If issues persist:"
echo "   1. Check: sudo systemctl status nginx"
echo "   2. Check: docker ps"
echo "   3. Check: curl -v http://localhost"
echo "   4. Check logs: sudo journalctl -f"
echo
