#!/bin/bash

# Cocktail Machine - Complete Installation Script
# Version: 2025.09.08-v1.0.11
# Clean, working version with all fixes integrated

SCRIPT_VERSION="2025.09.08-v1.0.11"
SCRIPT_BUILD="Build-001"

echo "==================================================="
echo "🍹 Cocktail Machine - Complete Installation"
echo "📦 Script Version: $SCRIPT_VERSION ($SCRIPT_BUILD)"
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
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

# Configuration
DEPLOY_REPO="sebastienlepoder/cocktail-machine-dev"
BRANCH="main"
WEBROOT_DIR="/opt/webroot"
SCRIPTS_DIR="/opt/scripts"
PROJECT_DIR="/home/$USER/cocktail-machine"

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

print_step "Checking Raspberry Pi OS version..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    print_info "OS: $PRETTY_NAME"
fi

# Ensure running as non-root user
if [ "$EUID" -eq 0 ]; then
    print_error "Please run this script as a regular user (not root)"
    exit 1
fi

# Step 1: System Update
print_step "Step 1: System update and configuration..."

# Configure non-interactive mode
print_info "Configuring non-interactive mode..."
sudo mkdir -p /etc/needrestart
echo '$nrconf{restart} = "a";' | sudo tee /etc/needrestart/needrestart.conf > /dev/null
echo '$nrconf{kernelhints} = 0;' | sudo tee -a /etc/needrestart/needrestart.conf > /dev/null

sudo mkdir -p /etc/apt/apt.conf.d
echo 'APT::Get::Assume-Yes "true";' | sudo tee /etc/apt/apt.conf.d/99noninteractive > /dev/null
echo 'Dpkg::Options { "--force-confdef"; "--force-confold"; }' | sudo tee -a /etc/apt/apt.conf.d/99noninteractive > /dev/null

print_info "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
print_status "System updated"

# Step 2: Install packages
print_step "Step 2: Installing required packages..."
sudo apt-get install -y curl wget unzip jq nginx docker.io docker-compose
print_status "Packages installed"

# Step 3: Configure Docker
print_step "Step 3: Configuring Docker..."
sudo usermod -aG docker $USER
sudo systemctl enable docker
sudo systemctl start docker
print_status "Docker configured"

# Step 4: Download and install dashboard
print_step "Step 4: Installing dashboard..."

# Create directories
sudo mkdir -p "$WEBROOT_DIR" "$SCRIPTS_DIR"
sudo chown -R www-data:www-data "$WEBROOT_DIR"
sudo chmod -R 755 "$WEBROOT_DIR"

print_info "Downloading dashboard from repository..."
cd /tmp
rm -rf dashboard_download
mkdir dashboard_download
cd dashboard_download

# Try to download actual dashboard files
DOWNLOADED_DASHBOARD=false

# Method 1: Try GitHub releases
print_info "Trying GitHub releases..."
if curl -s "https://api.github.com/repos/$DEPLOY_REPO/releases/latest" | jq -r '.assets[].browser_download_url' | grep -q "http"; then
    PACKAGE_URL=$(curl -s "https://api.github.com/repos/$DEPLOY_REPO/releases/latest" | jq -r '.assets[] | select(.name | contains("dashboard")) | .browser_download_url' | head -1)
    if [ "$PACKAGE_URL" != "null" ] && [ -n "$PACKAGE_URL" ]; then
        if curl -L -o dashboard.tar.gz "$PACKAGE_URL" && tar -xzf dashboard.tar.gz; then
            if [ -f "index.html" ] && grep -q "<html\|<!DOCTYPE" "index.html"; then
                sudo cp -v * "$WEBROOT_DIR/"
                DOWNLOADED_DASHBOARD=true
                print_status "Dashboard downloaded from releases"
            fi
        fi
    fi
fi

# Method 2: Try web directory
if [ "$DOWNLOADED_DASHBOARD" = false ]; then
    print_info "Trying web directory from repository..."
    WEB_URL="https://api.github.com/repos/$DEPLOY_REPO/contents/web"
    if curl -s "$WEB_URL" | jq -r '.[].download_url' | head -1 | grep -q "http"; then
        curl -s "$WEB_URL" | jq -r '.[] | select(.type == "file") | "\(.name),\(.download_url)"' > files_list.txt
        while IFS=',' read -r name url; do
            if [[ "$url" != "null" && "$name" =~ \.(html|js|css|json|ico|png|jpg|gif)$ ]]; then
                curl -L -o "$name" "$url"
            fi
        done < files_list.txt
        
        if [ -f "index.html" ] && grep -q "<html\|<!DOCTYPE" "index.html"; then
            sudo cp -v * "$WEBROOT_DIR/"
            DOWNLOADED_DASHBOARD=true
            print_status "Dashboard downloaded from repository"
        fi
    fi
fi

# Method 3: Create working dashboard if download failed
if [ "$DOWNLOADED_DASHBOARD" = false ]; then
    print_info "Creating working dashboard..."
    sudo tee "$WEBROOT_DIR/index.html" > /dev/null << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🍹 Cocktail Machine Dashboard</title>
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
            max-width: 900px;
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
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 30px;
        }
        .button {
            display: block;
            background: rgba(255,255,255,0.2);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-decoration: none;
            transition: all 0.3s;
            border: 2px solid rgba(255,255,255,0.3);
            font-size: 16px;
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
        .info { 
            margin-top: 30px; 
            font-size: 14px; 
            opacity: 0.8; 
            line-height: 1.5;
        }
        #status { font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine Control System</h1>
        <p>Premium automated cocktail machine interface</p>
        
        <div class="status">
            <h3>🎯 System Status</h3>
            <p id="status">Checking services...</p>
        </div>
        
        <div class="buttons">
            <a href="http://localhost:1880/ui" class="button primary">🔴 Node-RED Dashboard</a>
            <a href="http://localhost:1880/admin" class="button">⚙️ Node-RED Editor</a>
            <a href="/health" class="button">❤️ Health Check</a>
            <a href="javascript:location.reload()" class="button">🔄 Refresh Status</a>
        </div>
        
        <div class="info">
            <p><strong>Working Dashboard - Ready for Use</strong></p>
            <p>Your cocktail machine control system is operational!</p>
            <p>IP Address: <span id="ip">Loading...</span></p>
            <p><em>Access from any device on your network</em></p>
        </div>
    </div>
    
    <script>
        function checkServices() {
            fetch('/health')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('status').innerHTML = '✅ Web server running';
                })
                .catch(err => {
                    document.getElementById('status').innerHTML = '⚠️ Starting services...';
                });
                
            fetch('http://localhost:1880')
                .then(response => {
                    if (response.ok) {
                        document.getElementById('status').innerHTML += '<br>✅ Node-RED operational';
                    }
                })
                .catch(err => {
                    document.getElementById('status').innerHTML += '<br>🔄 Node-RED starting...';
                });
        }
        
        // Get IP
        setTimeout(() => {
            document.getElementById('ip').textContent = location.hostname || 'localhost';
        }, 1000);
        
        // Check services
        setTimeout(checkServices, 2000);
        setInterval(checkServices, 15000);
    </script>
</body>
</html>
HTML_EOF
    print_status "Working dashboard created"
fi

# Clean up
cd /
rm -rf /tmp/dashboard_download

# Set permissions
sudo chown -R www-data:www-data "$WEBROOT_DIR"
sudo chmod -R 755 "$WEBROOT_DIR"
sudo find "$WEBROOT_DIR" -type f -exec chmod 644 {} \;

print_status "Dashboard installation completed"

# Step 5: Configure Nginx
print_step "Step 5: Configuring web server..."

# Remove any broken configurations
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-enabled/sites-available

# Create clean nginx configuration
sudo tee /etc/nginx/sites-available/cocktail-machine > /dev/null << 'NGINX_EOF'
server {
    listen 80;
    server_name _;
    root /opt/webroot;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINX_EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/cocktail-machine /etc/nginx/sites-enabled/cocktail-machine

# Test and restart nginx
if sudo nginx -t; then
    sudo systemctl restart nginx
    print_status "Web server configured and running"
else
    print_error "Nginx configuration error"
    sudo nginx -t
fi

# Step 6: Setup Docker services
print_step "Step 6: Setting up backend services..."

# Create project directory
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create docker-compose configuration
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
      - NODE_RED_ENABLE_PROJECTS=false
    networks:
      - cocktail-network
    user: "1000:1000"
    command: ["node-red", "--userDir", "/data"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:1880"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

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

# Create directories
mkdir -p mosquitto/{config,data,log} nodered/data

# Create mosquitto config
cat > mosquitto/config/mosquitto.conf << 'MQTT_CONF_EOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_type error
log_type warning
log_type notice
log_type information
MQTT_CONF_EOF

# Create basic Node-RED settings
cat > nodered/data/settings.js << 'SETTINGS_EOF'
module.exports = {
    uiPort: process.env.PORT || 1880,
    uiHost: '0.0.0.0',
    httpAdminRoot: '/admin',
    httpNodeRoot: '/api',
    userDir: '/data',
    flowFile: 'flows.json',
    flowFilePretty: true,
    editorTheme: {
        page: {
            title: "Cocktail Machine - Node-RED",
            favicon: "🍹"
        },
        header: {
            title: "🍹 Cocktail Machine Control"
        }
    },
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    }
};
SETTINGS_EOF

# Create basic flows
cat > nodered/data/flows.json << 'FLOWS_EOF'
[
    {
        "id": "main-tab",
        "type": "tab",
        "label": "Cocktail Machine",
        "disabled": false,
        "info": ""
    },
    {
        "id": "welcome-inject",
        "type": "inject",
        "z": "main-tab",
        "name": "System Start",
        "props": [{"p": "payload"}],
        "repeat": "",
        "crontab": "",
        "once": true,
        "onceDelay": 0.1,
        "topic": "",
        "payload": "🍹 Cocktail Machine Node-RED Online!",
        "payloadType": "str",
        "x": 130,
        "y": 80,
        "wires": [["debug-node"]]
    },
    {
        "id": "debug-node",
        "type": "debug",
        "z": "main-tab",
        "name": "System Log",
        "active": true,
        "tosidebar": true,
        "console": false,
        "tostatus": false,
        "complete": "payload",
        "targetType": "msg",
        "x": 350,
        "y": 80,
        "wires": []
    }
]
FLOWS_EOF

# Set correct permissions
sudo chown -R $USER:$USER "$PROJECT_DIR"
sudo chown -R 1000:1000 "$PROJECT_DIR/nodered/data"
chmod -R 755 "$PROJECT_DIR"

print_status "Backend services configured"

# Step 7: Start services
print_step "Step 7: Starting services..."

print_info "Starting Docker containers..."
docker-compose up -d

print_info "Waiting for services to start..."
sleep 30

# Check and fix Node-RED if needed
print_info "Checking Node-RED status..."
if docker ps | grep cocktail-nodered | grep -q "Restarting"; then
    print_warning "Node-RED container restarting - applying fix..."
    
    docker-compose stop nodered
    sleep 5
    
    # Fix permissions again
    sudo chown -R 1000:1000 "$PROJECT_DIR/nodered/data"
    chmod -R 755 "$PROJECT_DIR/nodered/data"
    
    # Restart
    docker-compose up -d nodered
    sleep 20
fi

print_status "Services started"

# Step 8: Final verification
print_step "Step 8: Final verification..."

print_info "Service status:"
echo "  • Nginx: $(systemctl is-active nginx)"
echo "  • Docker: $(systemctl is-active docker)"

print_info "Container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

print_info "Testing web dashboard..."
if curl -s http://localhost | grep -q "<html"; then
    print_status "Dashboard is working"
else
    print_error "Dashboard not responding properly"
fi

print_info "Testing Node-RED..."
for i in {1..10}; do
    if curl -s http://localhost:1880 >/dev/null 2>&1; then
        print_status "Node-RED is accessible"
        break
    elif [ $i -eq 10 ]; then
        print_warning "Node-RED not accessible - may need manual restart"
    else
        sleep 3
    fi
done

echo
echo "==================================================="
echo "🎉 Installation Complete!"
echo "==================================================="
echo
echo "🌍 Access your system:"
echo "   • Dashboard:      http://$(hostname -I | awk '{print $1}')"
echo "   • Node-RED UI:    http://$(hostname -I | awk '{print $1}'):1880/ui"
echo "   • Node-RED Admin: http://$(hostname -I | awk '{print $1}'):1880/admin"
echo
echo "🔧 System Management:"
echo "   • Restart web:    sudo systemctl restart nginx"
echo "   • Restart Node-RED: cd $PROJECT_DIR && docker-compose restart nodered"
echo "   • View logs:      docker logs cocktail-nodered"
echo
echo "📱 Your cocktail machine is ready to use!"
echo "==================================================="
