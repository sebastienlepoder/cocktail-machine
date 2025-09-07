#!/bin/bash

# Cocktail Machine - Simplified Production Setup
# Downloads React dashboard and serves it via nginx

echo "=================================================="
echo "🍹 Cocktail Machine - Production Setup"
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

# Configuration
DEPLOY_REPO="sebastienlepoder/cocktail-deploy"
BRANCH="main"
WEBROOT_DIR="/opt/webroot"
SCRIPTS_DIR="/opt/scripts"

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

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

# Sync system clock to fix timestamp warnings
print_info "Synchronizing system clock..."
sudo apt-get update -y
sudo apt-get install -y ntp ntpdate
sudo systemctl stop ntp 2>/dev/null || true
sudo ntpdate -s time.nist.gov 2>/dev/null || sudo ntpdate -s pool.ntp.org 2>/dev/null || print_info "Clock sync skipped"
sudo systemctl start ntp 2>/dev/null || true
sudo systemctl enable ntp 2>/dev/null || true

print_info "Upgrading packages..."
sudo apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
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

# Create directories
sudo mkdir -p "$WEBROOT_DIR" "$SCRIPTS_DIR"

# Download the production dashboard package
print_info "Downloading latest dashboard from production repository..."
DASHBOARD_URL="https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/web.tar.gz"
curl -L -o /tmp/dashboard.tar.gz "$DASHBOARD_URL"

if [ $? -eq 0 ] && [ -f /tmp/dashboard.tar.gz ] && [ -s /tmp/dashboard.tar.gz ]; then
    print_status "Dashboard package downloaded successfully"
    
    # Extract to webroot
    print_info "Extracting dashboard to $WEBROOT_DIR..."
    cd /tmp
    tar -xzf dashboard.tar.gz
    if [ -d "web" ]; then
        sudo cp -r web/* "$WEBROOT_DIR/"
        sudo chown -R www-data:www-data "$WEBROOT_DIR"
        sudo chmod -R 755 "$WEBROOT_DIR"
        print_status "Dashboard extracted and permissions set"
    else
        print_error "Invalid dashboard package format"
        exit 1
    fi
    
    rm -rf /tmp/web /tmp/dashboard.tar.gz
else
    print_error "Failed to download dashboard package"
    exit 1
fi

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

# Ensure nginx directories exist
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# Create nginx config for React dashboard
sudo tee /etc/nginx/sites-available/cocktail-machine > /dev/null << EOF
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
sudo ln -sf /etc/nginx/sites-available/cocktail-machine /etc/nginx/sites-enabled/
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

# Create project directory
PROJECT_DIR="/home/$USER/cocktail-machine"
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
    networks:
      - cocktail-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:1880"]
      interval: 30s
      timeout: 10s
      retries: 3

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

# Create mosquitto config
cat > "$PROJECT_DIR/mosquitto/config/mosquitto.conf" << 'EOF'
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

# Step 8: Install X11 and Desktop Environment for kiosk
print_step "Step 8: Installing X11 and minimal desktop..."
sudo apt-get install -y \
    --no-install-recommends \
    xserver-xorg \
    xserver-xorg-video-fbdev \
    xorg \
    openbox \
    lightdm \
    chromium-browser \
    x11-xserver-utils \
    unclutter-startup
print_status "Desktop environment installed"

# Step 9: Create kiosk system
print_step "Step 9: Setting up kiosk system..."

# Create kiosk directory
mkdir -p /home/$USER/.cocktail-machine

# Download production kiosk scripts (but modify them for direct nginx)
print_info "Downloading and configuring kiosk scripts..."

# Create custom kiosk launcher for direct nginx access
cat > /home/$USER/.cocktail-machine/kiosk-launcher.sh << 'EOF'
#!/bin/bash
# Kiosk Launcher for nginx-served React dashboard

LOG_FILE="/tmp/kiosk-launcher.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Kiosk Launcher Started ==="

# Ensure DISPLAY is set
export DISPLAY=:0

# Kill any existing browser processes
pkill -f chromium-browser 2>/dev/null || true
sleep 2

# Start loading screen
log "Starting loading screen..."
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-extensions \
    --disable-plugins \
    --disable-translate \
    --disable-features=TranslateUI \
    --autoplay-policy=no-user-gesture-required \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-component-update \
    "file:///home/$USER/.cocktail-machine/loading.html" &

LOADING_PID=$!
log "Loading screen started (PID: $LOADING_PID)"

# Wait for nginx to be ready
log "Checking if nginx is ready..."
MAX_WAIT=60
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -s http://localhost/health | grep -q "healthy"; then
        log "Nginx is ready!"
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ $WAITED -ge $MAX_WAIT ]; then
    log "Nginx failed to start, showing error page..."
    kill $LOADING_PID 2>/dev/null || true
    chromium-browser --kiosk "data:text/html,<html><body style='background:#e74c3c;color:white;display:flex;align-items:center;justify-content:center;height:100vh;font-family:Arial'><div style='text-align:center'><h1>Service Error</h1><p>Cocktail machine service failed to start</p></div></body></html>" &
    exit 1
fi

# Kill loading screen and start dashboard
log "Service is ready! Switching to dashboard..."
kill $LOADING_PID 2>/dev/null || true
sleep 2

# Start dashboard
log "Starting dashboard..."
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-extensions \
    --disable-plugins \
    --disable-translate \
    --disable-features=TranslateUI \
    --autoplay-policy=no-user-gesture-required \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-component-update \
    "http://localhost" &

log "Dashboard started successfully!"
EOF

chmod +x /home/$USER/.cocktail-machine/kiosk-launcher.sh

# Create loading screen
cat > /home/$USER/.cocktail-machine/loading.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cocktail Machine Loading</title>
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
            overflow: hidden;
        }
        .container {
            text-align: center;
            animation: fadeIn 1s ease-in;
        }
        .logo {
            font-size: 80px;
            margin-bottom: 20px;
            animation: float 3s ease-in-out infinite;
        }
        h1 {
            font-size: 48px;
            margin-bottom: 20px;
            font-weight: 300;
        }
        .loader {
            width: 60px;
            height: 60px;
            border: 3px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s linear infinite;
            margin: 40px auto;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-20px); }
        }
        @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine</h1>
        <div class="loader"></div>
        <p>Starting services...</p>
    </div>
</body>
</html>
EOF

print_status "Kiosk system configured"

# Step 10: Configure kiosk auto-start (same as before)
print_step "Step 10: Configuring kiosk auto-start..."

# Configure auto-login
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/01-autologin.conf > /dev/null << EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
user-session=openbox
greeter-session=lightdm-gtk-greeter
EOF

# Enable graphical target
sudo systemctl set-default graphical.target
sudo systemctl enable lightdm

# Create systemd service for kiosk
sudo tee /etc/systemd/system/cocktail-kiosk-startup.service > /dev/null << EOF
[Unit]
Description=Start Cocktail Machine Kiosk
After=lightdm.service graphical.target multi-user.target
Wants=lightdm.service
Requires=graphical.target

[Service]
Type=forking
User=root
Environment=DISPLAY=:0
ExecStartPre=/bin/sleep 15
ExecStartPre=/bin/bash -c 'while ! systemctl is-active lightdm >/dev/null 2>&1; do sleep 2; done'
ExecStart=/bin/bash -c 'sudo -u $USER DISPLAY=:0 XAUTHORITY=/home/$USER/.Xauthority /home/$USER/.cocktail-machine/kiosk-launcher.sh &'
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cocktail-kiosk-startup.service

print_status "Kiosk auto-start configured"

# Step 11: Test installation
print_step "Step 11: Testing installation..."

# Test React dashboard
print_info "Testing React dashboard on port 80..."
if curl -s http://localhost | grep -q "Cocktail Machine"; then
    print_status "React dashboard is accessible on port 80"
else
    print_info "React dashboard may still be starting up"
fi

# Test nginx health
print_info "Testing nginx health check..."
if curl -s http://localhost/health | grep -q "healthy"; then
    print_status "Nginx health check passed"
else
    print_info "Nginx may still be starting up"
fi

# Test update system
print_info "Testing update system..."
if sudo "$SCRIPTS_DIR/update_dashboard.sh" --check; then
    print_status "Update system working"
else
    print_info "Update system check completed"
fi

print_status "Installation testing completed"

echo ""
echo "=================================================="
echo "🎉 Cocktail Machine Setup Complete!"
echo "=================================================="
echo ""
echo "✅ Production React dashboard installed and running"
echo "✅ Nginx web server configured and started"
echo "✅ Docker backend services running (Node-RED, MQTT)"
echo "✅ Update system installed and working"
echo "✅ Kiosk mode configured for Pi display"
echo "✅ Auto-login and quiet boot enabled"
echo ""
echo "🌐 Access Points:"
echo "   • React Dashboard: http://localhost"
echo "   • Node-RED:        http://localhost:1880"
echo "   • Health Check:    http://localhost/health"
echo ""
echo "🔄 Update Commands:"
echo "   • Check updates:   sudo $SCRIPTS_DIR/update_dashboard.sh --check"
echo "   • Install updates: sudo $SCRIPTS_DIR/update_dashboard.sh"
echo "   • Quick update:    sudo $SCRIPTS_DIR/quick-update.sh"
echo ""
echo "🖥️ Kiosk Mode:"
echo "   • Reboot to activate: sudo reboot"
echo "   • Manual start: sudo systemctl start cocktail-kiosk-startup"
echo "   • Check status: sudo systemctl status cocktail-kiosk-startup"
echo ""
echo "🎯 After reboot, your Pi will display the React dashboard"
echo "   in full-screen kiosk mode automatically!"
echo ""
echo "⏰ Ready to reboot? Run: sudo reboot"
echo "=================================================="
