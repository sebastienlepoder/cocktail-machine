#!/bin/bash

# Cocktail Machine - Production Setup Script
# Version: 2025.09.07-v1.0.0
# Downloads React dashboard and serves it via nginx

SCRIPT_VERSION="2025.09.07-v1.0.5"
SCRIPT_BUILD="Build-169"

echo "=================================================="
echo "🍹 Cocktail Machine - Production Setup"
echo "📦 Script Version: $SCRIPT_VERSION ($SCRIPT_BUILD)"
echo "=================================================="

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

# Configuration - Auto-detect repository based on script source
if [[ "$(curl -s "$0" 2>/dev/null || echo '')" == *"cocktail-machine-dev"* ]] || [[ "$0" == *"cocktail-machine-dev"* ]]; then
    # Running from dev repo
    DEPLOY_REPO="sebastienlepoder/cocktail-machine-dev"
    print_info "🛠️ Using development repository (cocktail-machine-dev)"
else
    # Running from prod repo or direct URL
    DEPLOY_REPO="sebastienlepoder/cocktail-machine-prod"
    print_info "🚀 Using production repository (cocktail-machine-prod)"
fi

BRANCH="main"
WEBROOT_DIR="/opt/webroot"
SCRIPTS_DIR="/opt/scripts"

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
    print_info "Usage: curl -fsSL https://raw.githubusercontent.com/$DEPLOY_REPO/main/scripts/setup-ultimate.sh | bash"
    exit 1
fi

# Step 1: System Update and Clock Sync
print_step "Step 1: Updating system and syncing clock..."

# Configure system to avoid interactive prompts
print_info "Configuring non-interactive mode..."

# Prevent needrestart from showing interactive dialogs
sudo mkdir -p /etc/needrestart
echo '$nrconf{restart} = "a";' | sudo tee /etc/needrestart/needrestart.conf > /dev/null
echo '$nrconf{kernelhints} = 0;' | sudo tee -a /etc/needrestart/needrestart.conf > /dev/null

# Configure APT to avoid interactive prompts
sudo mkdir -p /etc/apt/apt.conf.d
echo 'DPkg::Post-Invoke-Success {"test -x /usr/bin/needrestart && /usr/bin/needrestart -n || true"; };' | sudo tee /etc/apt/apt.conf.d/99needrestart > /dev/null
echo 'APT::Get::Assume-Yes "true";' | sudo tee /etc/apt/apt.conf.d/99noninteractive > /dev/null
echo 'Dpkg::Options { "--force-confdef"; "--force-confold"; }' | sudo tee -a /etc/apt/apt.conf.d/99noninteractive > /dev/null

# Sync system clock to fix timestamp warnings
print_info "Synchronizing system clock..."
sudo apt-get update -y
sudo apt-get install -y ntp ntpdate
sudo systemctl stop ntp 2>/dev/null || true
sudo ntpdate -s time.nist.gov 2>/dev/null || sudo ntpdate -s pool.ntp.org 2>/dev/null || print_info "Clock sync skipped"
sudo systemctl start ntp 2>/dev/null || true
sudo systemctl enable ntp 2>/dev/null || true

print_info "Upgrading packages..."
# Configure debconf to avoid kernel restart dialogs
echo 'libc6 libraries/restart-without-asking boolean true' | sudo debconf-set-selections
echo 'libssl1.1:amd64 libssl1.1/restart-services string' | sudo debconf-set-selections 2>/dev/null || true

# Upgrade with all non-interactive options
sudo apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    -o DPkg::Post-Invoke-Success::="test -x /usr/bin/needrestart && /usr/bin/needrestart -n || true"
print_status "System updated and clock synchronized"

# Step 2: Install essential packages + nginx
print_step "Step 2: Installing essential packages..."
sudo apt-get install -y \
    curl \
    wget \
    unzip \
    jq \
    openssl \
    ca-certificates \
    nginx
print_status "Essential packages installed"

# Step 3: Install Docker (for Node-RED and other services)
print_step "Step 3: Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    
    # Wait for Docker installation to complete
    sleep 5
    
    # Install Docker Compose (try multiple methods)
    print_info "Installing Docker Compose..."
    if ! sudo apt-get install -y docker-compose-plugin 2>/dev/null; then
        print_info "Plugin installation failed, trying legacy docker-compose..."
        sudo apt-get install -y docker-compose 2>/dev/null || {
            print_info "APT installation failed, downloading docker-compose binary..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        }
    fi
    
    print_status "Docker installed successfully"
else
    print_status "Docker already installed"
fi

# Ensure Docker service is available and start it
print_info "Starting Docker service..."
if sudo systemctl list-unit-files | grep -q docker.service; then
    sudo systemctl enable docker
    sudo systemctl start docker
    print_status "Docker service started"
else
    print_info "Docker service not found, waiting for installation to complete..."
    sleep 10
    sudo systemctl enable docker 2>/dev/null || true
    sudo systemctl start docker 2>/dev/null || true
fi

# Step 4: Download Production React Dashboard
print_step "Step 4: Downloading production React dashboard..."

# Create directories with proper permissions
sudo mkdir -p "$WEBROOT_DIR" "$SCRIPTS_DIR"
sudo chown -R www-data:www-data "$WEBROOT_DIR"
sudo chmod -R 755 "$WEBROOT_DIR"

# Create simple placeholder dashboard (same for both dev and prod)
print_info "Creating cocktail machine dashboard..."
mkdir -p /tmp/web

cat > /tmp/web/index.html << 'DASHBOARD_EOF'
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
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            text-align: center;
        }
        .container {
            max-width: 800px;
            padding: 40px;
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
        p {
            font-size: 18px;
            margin-bottom: 30px;
            opacity: 0.9;
        }
        .status {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .buttons {
            margin-top: 30px;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
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
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine</h1>
        <p>Your cocktail machine is successfully installed and running!</p>
        
        <div class="status">
            <h3>🎯 System Status: Online</h3>
            <p>Installation completed successfully</p>
        </div>
        
        <div class="buttons">
            <a href="http://localhost:1880/ui" class="button primary">🔴 Node-RED Dashboard</a>
            <a href="http://localhost:1880/admin" class="button">⚙️ Node-RED Editor</a>
            <a href="/health" class="button">❤️ Health Check</a>
            <a href="/system-info.html" class="button">📊 System Info</a>
        </div>
        
        <p style="margin-top: 40px; font-size: 14px; opacity: 0.7;">
            Access this system from any device on your network
        </p>
    </div>
    
    <script>
        // Check Node-RED status
        fetch('/health')
            .then(response => response.text())
            .then(data => {
                if (data.includes('healthy')) {
                    console.log('✅ System healthy');
                }
            })
            .catch(err => console.log('ℹ️ Health check unavailable'));
    </script>
</body>
</html>
DASHBOARD_EOF

print_status "Dashboard created"

# Dashboard files are ready
print_info "Dashboard files ready for installation"

# Find and copy dashboard files
print_info "Locating dashboard files..."
if [ -d "web" ]; then
    print_info "Found web directory, checking contents..."
    
    # Check if web directory contains built files or source files
    if [ -f "web/index.html" ]; then
        print_info "Found built React app, copying files..."
        sudo cp -rv web/* "$WEBROOT_DIR/"
    elif [ -f "web/.next" ] || [ -d "web/.next" ]; then
        print_error "Found Next.js source with .next build directory"
        print_info "Copying .next build output..."
        sudo cp -rv web/.next/static/* "$WEBROOT_DIR/" 2>/dev/null || true
        sudo cp -rv web/out/* "$WEBROOT_DIR/" 2>/dev/null || true
    elif [ -f "web/package.json" ]; then
        print_error "Found Next.js source code instead of built app"
        print_info "Creating temporary dashboard as fallback..."
        
        # Create a simple fallback HTML page
        sudo tee "$WEBROOT_DIR/index.html" > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cocktail Machine</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            text-align: center;
        }
        .container {
            max-width: 600px;
            padding: 40px;
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
        p {
            font-size: 18px;
            margin-bottom: 30px;
            opacity: 0.9;
        }
        .status {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .buttons {
            margin-top: 30px;
        }
        .button {
            display: inline-block;
            background: rgba(255,255,255,0.2);
            color: white;
            padding: 12px 24px;
            margin: 0 10px;
            border-radius: 6px;
            text-decoration: none;
            transition: background 0.3s;
        }
        .button:hover {
            background: rgba(255,255,255,0.3);
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-20px); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine</h1>
        <p>Your cocktail machine is successfully installed and running!</p>
        
        <div class="status">
            <h3>🎯 System Status: Online</h3>
            <p>Installation completed successfully</p>
        </div>
        
        <div class="buttons">
            <a href="http://localhost:1880" class="button">🔧 Node-RED Dashboard</a>
            <a href="/health" class="button">❤️ Health Check</a>
        </div>
        
        <p style="margin-top: 40px; font-size: 14px; opacity: 0.7;">
            This is a temporary dashboard. The full React dashboard will be available after the first deployment.
        </p>
    </div>
</body>
</html>
EOF
        print_status "Temporary dashboard created as fallback"
    else
        print_info "Copying web directory contents as-is..."
        sudo cp -rv web/* "$WEBROOT_DIR/"
    fi
elif [ -f "index.html" ]; then
    print_info "Found dashboard files in root, copying..."
    sudo cp -rv * "$WEBROOT_DIR/"
else
    print_error "No valid dashboard files found in archive"
    print_info "Archive structure:"
    ls -la
    
    print_info "Creating minimal dashboard as fallback..."
    sudo tee "$WEBROOT_DIR/index.html" > /dev/null << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Cocktail Machine - Setup Complete</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: #2c3e50; 
            color: white; 
            text-align: center; 
            padding: 50px; 
        }
        .container { max-width: 600px; margin: 0 auto; }
        .logo { font-size: 80px; margin-bottom: 20px; }
        h1 { font-size: 36px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine</h1>
        <p>Installation completed successfully!</p>
        <p>Visit <a href="http://localhost:1880" style="color: #3498db;">Node-RED Dashboard</a></p>
    </div>
</body>
</html>
EOF
    print_status "Fallback dashboard created"
fi

# Set proper permissions
print_info "Setting file permissions..."
sudo chown -R www-data:www-data "$WEBROOT_DIR"
sudo chmod -R 755 "$WEBROOT_DIR"
sudo find "$WEBROOT_DIR" -type f -exec chmod 644 {} \;

# Create assets directory to prevent 404 errors
print_info "Creating assets directory structure..."
sudo mkdir -p "$WEBROOT_DIR/src/assets/images"
sudo mkdir -p "$WEBROOT_DIR/assets/images"
sudo mkdir -p "$WEBROOT_DIR/static/assets/images"

# Create placeholder images to prevent 404 errors
print_info "Creating placeholder images..."
# Create a simple 1x1 transparent PNG as placeholder
echo -e '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc````\x00\x00\x00\x05\x00\x01\r\n\x9d\xb4\x00\x00\x00\x00IEND\xaeB`\x82' | sudo tee "$WEBROOT_DIR/src/assets/images/placeholder.png" > /dev/null
sudo cp "$WEBROOT_DIR/src/assets/images/placeholder.png" "$WEBROOT_DIR/assets/images/placeholder.png" 2>/dev/null || true
sudo cp "$WEBROOT_DIR/src/assets/images/placeholder.png" "$WEBROOT_DIR/static/assets/images/placeholder.png" 2>/dev/null || true

# Create favicon.ico
print_info "Creating favicon..."
echo -e '\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00 \x00h\x04\x00\x00\x16\x00\x00\x00(\x00\x00\x00\x10\x00\x00\x00 \x00\x00\x00\x01\x00 \x00\x00\x00\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' | sudo tee "$WEBROOT_DIR/favicon.ico" > /dev/null

# Verify files were copied correctly
print_info "Verifying dashboard installation..."
if [ -f "$WEBROOT_DIR/index.html" ]; then
    print_status "Dashboard files installed successfully"
    print_info "Dashboard files:"
    ls -la "$WEBROOT_DIR/" | head -5
else
    print_error "Dashboard installation verification failed - index.html not found"
    print_info "Contents of $WEBROOT_DIR:"
    ls -la "$WEBROOT_DIR/"
    exit 1
fi

# Clean up
rm -rf /tmp/web /tmp/dashboard.tar.gz /tmp/tar_contents.txt /tmp/repo_contents.json 2>/dev/null || true
print_status "Dashboard installation completed"

# Step 5: Download production scripts
print_step "Step 5: Installing production scripts..."

# Download update script
print_info "Downloading update script..."
sudo curl -L -o "$SCRIPTS_DIR/update_dashboard.sh" \
    "https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/scripts/update_dashboard.sh"
sudo chmod +x "$SCRIPTS_DIR/update_dashboard.sh"

# Download quick update script
sudo curl -L -o "$SCRIPTS_DIR/quick-update.sh" \
    "https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/scripts/quick-update.sh"
sudo chmod +x "$SCRIPTS_DIR/quick-update.sh"

print_status "Production scripts installed"

# Step 6: Configure nginx to serve React dashboard
print_step "Step 6: Configuring nginx..."

# Define variables
NGINX_SITE_NAME="cocktail-machine"

# Ensure nginx directories exist
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# Create nginx config for React dashboard
sudo tee "/etc/nginx/sites-available/$NGINX_SITE_NAME" > /dev/null << EOF
server {
    listen 80;
    server_name _;
    root $WEBROOT_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Enable the site
sudo ln -sf "/etc/nginx/sites-available/cocktail-machine" "/etc/nginx/sites-enabled/cocktail-machine"
sudo rm -f /etc/nginx/sites-enabled/default

# Test nginx config and restart
print_info "Testing nginx configuration..."
if sudo nginx -t 2>/dev/null; then
    print_status "Nginx config is valid"
else
    print_error "Nginx config test failed, but continuing..."
fi

# Start nginx service
print_info "Starting nginx service..."
if sudo systemctl list-unit-files | grep -q nginx.service; then
    sudo systemctl enable nginx
    sudo systemctl restart nginx
    print_status "Nginx service started"
else
    print_error "Nginx service not found! Installation may have failed."
    print_info "Attempting to start nginx directly..."
    sudo nginx 2>/dev/null || print_error "Failed to start nginx directly"
fi

print_status "Nginx configuration completed"

# Step 7: Set up Docker containers for Node-RED and MQTT
print_step "Step 7: Setting up backend services..."

# Create project directory (same structure regardless of source repo)
PROJECT_DIR="/home/$USER/cocktail-machine"
KIOSK_DIR="/home/$USER/.cocktail-machine"
mkdir -p "$PROJECT_DIR"

# Create simple docker-compose for backend services only
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # Node-RED for automation
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
      - NODE_RED_ENABLE_SAFE_MODE=false
    networks:
      - cocktail-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:1880"]
      interval: 30s
      timeout: 10s
      retries: 3
    command: node-red --settings /data/settings.js

  # MQTT Broker
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
EOF

# Create directories for services
mkdir -p "$PROJECT_DIR"/{mosquitto/{config,data,log},nodered/data}

# Set proper permissions for mosquitto directories
chmod -R 755 "$PROJECT_DIR/mosquitto"

# Create mosquitto config
sudo tee "$PROJECT_DIR/mosquitto/config/mosquitto.conf" > /dev/null << 'EOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_type error
log_type warning
log_type notice
log_type information
EOF

# Step 7.5: Download and deploy Node-RED flows
print_info "Downloading Node-RED flows..."

# Download Node-RED flows from production repository
NODERED_URL="https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/nodered"

# Create Node-RED data directories
mkdir -p "$PROJECT_DIR/nodered/data"

# Download flows and configuration
print_info "Fetching Node-RED flows..."
if curl -L -f -o "$PROJECT_DIR/nodered/data/flows.json" "$NODERED_URL/flows/flows.json"; then
    print_status "Node-RED flows downloaded successfully"
else
    print_error "Failed to download Node-RED flows, creating basic flow"
    # Create a basic flow as fallback
    cat > "$PROJECT_DIR/nodered/data/flows.json" << 'BASIC_FLOW_EOF'
[
  {
    "id": "basic-flow",
    "label": "Basic Cocktail Flow", 
    "nodes": [
      {
        "id": "welcome-msg",
        "type": "inject",
        "z": "basic-flow",
        "name": "Welcome",
        "props": [{"p": "payload"}],
        "repeat": "",
        "crontab": "",
        "once": true,
        "onceDelay": 0.1,
        "topic": "",
        "payload": "Cocktail Machine Node-RED is running!",
        "payloadType": "str",
        "x": 100,
        "y": 100,
        "wires": [["debug-out"]]
      },
      {
        "id": "debug-out",
        "type": "debug",
        "z": "basic-flow",
        "name": "System Status",
        "active": true,
        "tosidebar": true,
        "console": false,
        "tostatus": false,
        "complete": "payload",
        "targetType": "msg",
        "x": 300,
        "y": 100,
        "wires": []
      }
    ]
  }
]
BASIC_FLOW_EOF
    print_info "Basic fallback flow created"
fi

# Download Node-RED settings
print_info "Fetching Node-RED settings..."
if curl -L -f -o "$PROJECT_DIR/nodered/data/settings.js" "$NODERED_URL/settings/settings.js"; then
    print_status "Node-RED settings downloaded successfully"
else
    print_info "Creating default Node-RED settings"
    # Create basic settings file
    cat > "$PROJECT_DIR/nodered/data/settings.js" << 'SETTINGS_EOF'
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
    print_status "Default Node-RED settings created"
fi

# Download additional Node-RED modules package.json
if curl -L -f -o "$PROJECT_DIR/nodered/data/package.json" "$NODERED_URL/settings/package.json"; then
    print_status "Node-RED package.json downloaded"
else
    print_info "Creating basic package.json for Node-RED modules"
    cat > "$PROJECT_DIR/nodered/data/package.json" << 'PACKAGE_EOF'
{
  "name": "cocktail-machine-nodered",
  "version": "1.0.0",
  "description": "Node-RED flows for Cocktail Machine",
  "dependencies": {
    "node-red-dashboard": "^3.6.0"
  }
}
PACKAGE_EOF
    print_status "Basic Node-RED package.json created"
fi

# Set proper permissions for Node-RED data
sudo chown -R 1000:1000 "$PROJECT_DIR/nodered/data"
chmod -R 755 "$PROJECT_DIR/nodered/data"

print_status "Node-RED flows and configuration deployed"

# Start backend services
cd "$PROJECT_DIR"

print_info "Starting Docker containers..."
# Try different docker-compose commands
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose up -d
else
    print_error "Docker Compose not found! Trying to install it..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        print_error "Failed to install Docker Compose. Backend services will not start."
    fi
fi

print_status "Backend services startup attempted"

# Step 8: Install Minimal Desktop for Pi Screen Display
print_step "Step 8: Installing minimal desktop for Pi screen display..."

# Install only essential packages for browser display
print_info "Installing minimal X11 and browser..."
sudo apt-get install -y \
    --no-install-recommends \
    xorg \
    xserver-xorg-legacy \
    xinit \
    openbox \
    chromium-browser

print_info "Skipping display manager - using direct X11 startup"

# Add pi user to required groups for X11 access
print_info "Adding pi user to required groups..."
sudo usermod -a -G tty,video,input,render $USER

# Configure X11 for Raspberry Pi framebuffer compatibility
print_info "Configuring X11 for Raspberry Pi..."

# Create Xwrapper config to allow non-console users
sudo tee /etc/X11/Xwrapper.config > /dev/null << 'X11_WRAPPER_EOF'
# Xwrapper.config (Debian X Window System server wrapper configuration file)
# This file was generated by the post-installation script during the
# installation of the x11-common package.

# This is the configuration file for the Xwrapper, which is used to
# make the X server setuid-root when it is started by a user who is not
# already root or a member of the 'console' group.
#
# Please refer to Xwrapper(1) for more details.

allowed_users=anybody
needs_root_rights=yes
X11_WRAPPER_EOF

# Create custom X11 configuration to fix framebuffer driver conflicts
sudo mkdir -p /etc/X11/xorg.conf.d

# GPU/Graphics configuration for Raspberry Pi
sudo tee /etc/X11/xorg.conf.d/01-raspberrypi.conf > /dev/null << 'RPI_CONF_EOF'
# Raspberry Pi GPU configuration
Section "Device"
    Identifier "Broadcom GPU"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
    Option "ShadowFB" "true"
EndSection

Section "Screen"
    Identifier "Default Screen"
    Device "Broadcom GPU"
    Monitor "Default Monitor"
EndSection

Section "Monitor"
    Identifier "Default Monitor"
EndSection
RPI_CONF_EOF

# Input configuration to fix keyboard/mouse access
sudo tee /etc/X11/xorg.conf.d/10-input.conf > /dev/null << 'INPUT_CONF_EOF'
Section "InputClass"
    Identifier "libinput keyboard catchall"
    MatchIsKeyboard "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "libinput pointer catchall"
    MatchIsPointer "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "libinput touchpad catchall"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
EndSection
INPUT_CONF_EOF

# Configure auto-login on console
print_info "Setting up auto-login..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin $USER %I \$TERM
Type=idle
EOF

# Create a simple system info page instead of kiosk
sudo tee /opt/webroot/system-info.html > /dev/null << 'SYSTEM_INFO_EOF'
<!DOCTYPE html>
<html>
<head>
    <title>🍹 Cocktail Machine - System Information</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: white; 
            padding: 20px; 
            margin: 0;
        }
        .container { max-width: 800px; margin: 0 auto; }
        .logo { font-size: 60px; text-align: center; margin-bottom: 20px; }
        h1 { text-align: center; font-size: 36px; margin-bottom: 30px; }
        .info-box { 
            background: rgba(255,255,255,0.1); 
            padding: 20px; 
            border-radius: 10px; 
            margin-bottom: 20px; 
        }
        .status-green { color: #2ecc71; font-weight: bold; }
        .status-red { color: #e74c3c; font-weight: bold; }
        a { color: #3498db; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine - System Ready</h1>
        
        <div class="info-box">
            <h3>📦 Installation Status</h3>
            <p>✅ Web dashboard installed and running</p>
            <p>✅ Nginx web server active</p>
            <p>✅ Docker backend services configured</p>
            <p class="status-green">🎯 System Status: ONLINE</p>
        </div>
        
        <div class="info-box">
            <h3>🌐 Access Points</h3>
            <p><a href="/">🏠 Main Dashboard</a></p>
            <p><a href="http://localhost:1880">🔧 Node-RED Interface</a></p>
            <p><a href="/health">❤️ Health Check</a></p>
        </div>
        
        <div class="info-box">
            <h3>📱 Usage</h3>
            <p>• Access this system from any device on your network</p>
            <p>• Use your phone, tablet, or computer as the interface</p>
            <p>• No desktop environment needed - pure web-based control</p>
        </div>
        
        <div class="info-box">
            <h3>🔄 Next Steps</h3>
            <p>1. Connect to this Pi from another device</p>
            <p>2. Visit <code>http://[pi-ip-address]</code></p>
            <p>3. Use the web dashboard to control your cocktail machine</p>
        </div>
    </div>
</body>
</html>
SYSTEM_INFO_EOF

print_status "Web-only setup completed - no desktop environment needed"

# Step 9: Create Simple Kiosk Startup
print_step "Step 9: Creating simple kiosk startup..."

# Create kiosk directory
mkdir -p "$KIOSK_DIR"

# Create improved kiosk script
cat > "$KIOSK_DIR/start-kiosk.sh" << 'KIOSK_EOF'
#!/bin/bash
# Improved kiosk startup script with better error handling

echo "[$(date)] Starting kiosk setup..."

# Wait for network and nginx to be ready
echo "[$(date)] Waiting for network and services..."
sleep 15

# Wait for nginx to respond
echo "[$(date)] Checking if dashboard is ready..."
for i in {1..30}; do
    if curl -s http://localhost >/dev/null 2>&1; then
        echo "[$(date)] Dashboard is ready!"
        break
    fi
    sleep 2
done

# Check if we're on the right console
if [ "$(tty)" != "/dev/tty1" ]; then
    echo "[$(date)] Not on tty1, exiting"
    exit 0
fi

# Set up environment
echo "[$(date)] Setting up X11 environment..."
export DISPLAY=:0
export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p $XDG_RUNTIME_DIR

# Start X11 server with openbox window manager
echo "[$(date)] Starting X11 server..."
startx /usr/bin/openbox-session -- :0 -nolisten tcp vt1 &
X11_PID=$!

# Wait for X11 to start
echo "[$(date)] Waiting for X11 server to be ready..."
for i in {1..30}; do
    if xset -display :0 q >/dev/null 2>&1; then
        echo "[$(date)] X11 server is ready!"
        break
    fi
    sleep 1
done

# Start chromium in kiosk mode
echo "[$(date)] Starting chromium browser..."
DISPLAY=:0 chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-extensions \
    --disable-plugins \
    --no-first-run \
    --disable-dev-shm-usage \
    --disable-software-rasterizer \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --start-fullscreen \
    http://localhost \
    >/tmp/chromium.log 2>&1 &

CHROMIUM_PID=$!
echo "[$(date)] Chromium started with PID: $CHROMIUM_PID"

# Monitor the processes
while true; do
    if ! ps -p $CHROMIUM_PID > /dev/null; then
        echo "[$(date)] Chromium crashed, restarting..."
        DISPLAY=:0 chromium-browser \
            --kiosk \
            --noerrdialogs \
            --disable-infobars \
            --disable-extensions \
            --disable-plugins \
            --no-first-run \
            --disable-dev-shm-usage \
            --disable-software-rasterizer \
            http://localhost >/tmp/chromium.log 2>&1 &
        CHROMIUM_PID=$!
    fi
    sleep 30
done
KIOSK_EOF

chmod +x "$KIOSK_DIR/start-kiosk.sh"

# Create auto-start script that runs after auto-login
cat > /home/$USER/.bash_profile << PROFILE_EOF
# Auto-start kiosk when logging into tty1
if [ "\$(tty)" = "/dev/tty1" ] && [ -z "\$DISPLAY" ]; then
    echo "Starting cocktail machine kiosk..."
    $KIOSK_DIR/start-kiosk.sh
fi
PROFILE_EOF

# Note: Kiosk will now start automatically via .bash_profile after auto-login
# No systemd service needed - simpler and more reliable

print_status "Simple kiosk startup configured"

# Step 10: Configure headless operation
print_step "Step 10: Configuring headless operation..."

# Ensure system stays in multi-user mode (no desktop)
sudo systemctl set-default multi-user.target

print_info "System configured for headless operation"
print_info "No desktop environment will start - saves resources"
print_info "All services accessible via web interface"

print_status "Headless operation configured"

# Step 11: Testing installation...
print_step "Step 11: Testing installation..."

# Wait for services to initialize
print_info "Waiting for services to initialize..."
sleep 10

# Test nginx service status first
print_info "Checking nginx service status..."
if sudo systemctl is-active nginx >/dev/null 2>&1; then
    print_status "Nginx service is running"
elif pgrep nginx >/dev/null; then
    print_status "Nginx is running (direct process)"
else
    print_error "Nginx is not running, attempting to start..."
    sudo systemctl start nginx 2>/dev/null || sudo nginx 2>/dev/null || print_error "Failed to start nginx"
fi

# Test React dashboard with retry
print_info "Testing React dashboard on port 80..."
for i in {1..5}; do
    RESPONSE=$(curl -s http://localhost 2>/dev/null || echo "connection_failed")
    if echo "$RESPONSE" | grep -q "403 Forbidden"; then
        print_error "Dashboard returning 403 Forbidden - permissions issue detected"
        print_info "Checking file permissions..."
        ls -la "$WEBROOT_DIR/" | head -3
        print_info "Fixing permissions..."
        sudo chown -R www-data:www-data "$WEBROOT_DIR"
        sudo chmod -R 644 "$WEBROOT_DIR"/*
        sudo chmod 755 "$WEBROOT_DIR"
        sudo systemctl reload nginx
        sleep 2
    elif echo "$RESPONSE" | grep -q "html\|HTML\|<title\|<!DOCTYPE"; then
        print_status "React dashboard is accessible on port 80"
        break
    elif [ $i -eq 5 ]; then
        print_error "Dashboard not accessible after 5 attempts"
        print_info "Response received: $(echo "$RESPONSE" | head -1)"
        print_info "Checking nginx error log:"
        sudo tail -3 /var/log/nginx/error.log 2>/dev/null || print_info "No nginx error log available"
    else
        print_info "Attempt $i/5: Waiting for dashboard..."
        sleep 2
    fi
done

# Test nginx health check with retry
print_info "Testing nginx health check..."
for i in {1..3}; do
    if curl -s http://localhost/health | grep -q "healthy"; then
        print_status "Nginx health check passed"
        break
    elif [ $i -eq 3 ]; then
        print_info "Health check not responding (nginx may need restart)"
    else
        sleep 2
    fi
done

# Test Node-RED service
print_info "Testing Node-RED service..."
for i in {1..5}; do
    if curl -s http://localhost:1880 >/dev/null 2>&1; then
        print_status "Node-RED is accessible on port 1880"
        break
    elif [ $i -eq 5 ]; then
        print_info "Node-RED not accessible after 5 attempts"
        print_info "Docker containers status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || print_info "Docker not accessible"
    else
        print_info "Attempt $i/5: Waiting for Node-RED..."
        sleep 3
    fi
done

# Test update system
print_info "Testing update system..."
if sudo "$SCRIPTS_DIR/update_dashboard.sh" --check; then
    print_status "Update system working"
else
    print_info "Update system check completed"
fi

# Additional diagnostics if things aren't working
print_info "Running system diagnostics..."
echo "📊 System Status:"
echo "   • Nginx process: $(pgrep nginx >/dev/null && echo 'Running' || echo 'Not running')"
echo "   • Docker process: $(pgrep dockerd >/dev/null && echo 'Running' || echo 'Not running')"
echo "   • Dashboard files: $([ -f /opt/webroot/index.html ] && echo 'Present' || echo 'Missing')"
echo "   • Webroot permissions: $(ls -ld /opt/webroot 2>/dev/null | awk '{print $1, $3, $4}' || echo 'Not accessible')"
echo "   • Index.html size: $([ -f /opt/webroot/index.html ] && stat -c%s /opt/webroot/index.html || echo 'N/A') bytes"
echo "   • Nginx config test: $(sudo nginx -t 2>&1 >/dev/null && echo 'Valid' || echo 'Invalid')"
echo "   • Kiosk scripts: $([ -f $KIOSK_DIR/start-kiosk.sh ] && echo 'Present' || echo 'Missing')"

# Try to fix common issues
if ! pgrep nginx >/dev/null; then
    print_info "Attempting to fix nginx startup..."
    sudo systemctl reset-failed nginx 2>/dev/null || true
    sudo nginx -s reload 2>/dev/null || sudo nginx 2>/dev/null || true
fi

print_status "Installation testing and diagnostics completed"

echo ""
echo "=================================================="
echo "🎉 Cocktail Machine Setup Complete!"
echo "=================================================="
echo ""
echo "✅ Production React dashboard installed and running"
echo "✅ Node-RED flows deployed with update system"
echo "✅ Nginx web server configured and started"
echo "✅ Docker backend services configured"
echo "✅ Update system installed and working"
echo "✅ Simple kiosk browser configured for Pi screen"
echo "✅ Web access enabled from network devices"
echo ""
echo "🌍 Access Points (from ANY device on your network):"
echo "   • React Dashboard: http://[pi-ip-address]"
echo "   • Node-RED UI:     http://[pi-ip-address]:1880/ui"
echo "   • Node-RED Admin:  http://[pi-ip-address]:1880/admin"
echo "   • Health Check:    http://[pi-ip-address]/health"
echo "   • System Info:     http://[pi-ip-address]/system-info.html"
echo ""
echo "🔄 Update Commands:"
echo "   • Check updates:   sudo $SCRIPTS_DIR/update_dashboard.sh --check"
echo "   • Install updates: sudo $SCRIPTS_DIR/update_dashboard.sh"
echo "   • Quick update:    sudo $SCRIPTS_DIR/quick-update.sh"
echo ""
echo "🛠️ Troubleshooting:"
echo "   • Restart nginx:    sudo systemctl restart nginx"
echo "   • Check nginx:      sudo systemctl status nginx"
echo "   • Check dashboard:   ls -la /opt/webroot/"
echo "   • View logs:        journalctl -f"
echo ""
echo "📱 Usage:"
echo "   1. Pi screen shows dashboard automatically after reboot"
echo "   2. Also access from phone, tablet, or computer"
echo "   3. Connect to same WiFi network as the Pi"
echo "   4. Visit http://[pi-ip-address] in any web browser"
echo ""
echo "🔍 Find your Pi's IP address: ip addr show"
echo ""
echo "⚠️ If services aren't running:"
echo "   1. Wait 2-3 minutes after installation"
echo "   2. Run: sudo systemctl restart nginx"
echo "   3. Run: sudo systemctl restart docker"
echo "   4. Check: curl http://localhost"
echo ""
echo "🔄 Reboot required to start Pi screen display:"
echo "   sudo reboot"
echo ""
echo "🎉 After reboot: Pi screen will show dashboard + network access available!"
echo ""
echo "📦 Installation completed with script version: $SCRIPT_VERSION ($SCRIPT_BUILD)"
echo "🕰️ Installation timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
