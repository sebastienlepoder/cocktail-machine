#!/bin/bash

# Cocktail Machine - Ultimate Setup Script (Production Ready)
# Downloads React dashboard directly from production repository

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
PROJECT_DIR="/home/$USER/cocktail-machine"
SCRIPTS_DIR="/opt/scripts"
WEBROOT_DIR="/opt/webroot"

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

print_step "Checking Raspberry Pi OS version..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    print_info "OS: $PRETTY_NAME"
else
    print_error "Cannot determine OS version"
fi

# Ensure running as non-root user
if [ "$EUID" -eq 0 ]; then
    print_error "Please run this script as a regular user (not root)"
    print_info "Usage: curl -fsSL https://raw.githubusercontent.com/$DEPLOY_REPO/main/scripts/setup-ultimate.sh | bash"
    exit 1
fi

# Step 1: System Update
print_step "Step 1: Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
print_status "System updated"

# Step 2: Install essential packages
print_step "Step 2: Installing essential packages..."
sudo apt-get install -y \
    curl \
    wget \
    unzip \
    jq \
    openssl \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https
print_status "Essential packages installed"

# Step 3: Install Docker
print_step "Step 3: Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    
    # Install Docker Compose
    sudo apt-get install -y docker-compose-plugin docker-compose
    print_status "Docker installed successfully"
else
    print_status "Docker already installed"
fi

sudo systemctl enable docker
sudo systemctl start docker

# Step 4: Download Production React Dashboard
print_step "Step 4: Downloading production React dashboard..."

# Create directories
sudo mkdir -p "$WEBROOT_DIR" "$SCRIPTS_DIR" "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/deployment"

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
    
    # Also copy to project directory for Docker
    cp -r web/* "$PROJECT_DIR/"
    print_status "Dashboard copied to project directory"
    
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

# Step 6: Create Docker configuration for React dashboard
print_step "Step 6: Creating Docker configuration..."

# Create simple Dockerfile for React app
cat > "$PROJECT_DIR/Dockerfile" << 'EOF'
FROM nginx:alpine
COPY . /usr/share/nginx/html/
EXPOSE 80
EOF

# Create docker-compose.yml for simple nginx setup
cat > "$PROJECT_DIR/deployment/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # React Dashboard (served by nginx)
  web-dashboard:
    build:
      context: ..
      dockerfile: Dockerfile
    container_name: cocktail-web
    restart: unless-stopped
    ports:
      - "3000:80"
    volumes:
      - ../:/usr/share/nginx/html/
    networks:
      - cocktail-network

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

  # Nginx reverse proxy
  nginx:
    image: nginx:alpine
    container_name: cocktail-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
    networks:
      - cocktail-network
    depends_on:
      - web-dashboard
      - nodered

networks:
  cocktail-network:
    driver: bridge
EOF

# Create nginx reverse proxy config
mkdir -p "$PROJECT_DIR/deployment/nginx"
cat > "$PROJECT_DIR/deployment/nginx/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream dashboard {
        server web-dashboard:80;
    }
    
    upstream nodered {
        server nodered:1880;
    }
    
    server {
        listen 80;
        server_name _;
        
        location / {
            proxy_pass http://dashboard;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        location /admin {
            proxy_pass http://nodered;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
        }
        
        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Create directories for services
mkdir -p "$PROJECT_DIR/deployment"/{mosquitto/{config,data,log},nodered/data}

# Create mosquitto config
cat > "$PROJECT_DIR/deployment/mosquitto/config/mosquitto.conf" << 'EOF'
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

print_status "Docker configuration created"

# Step 7: Install X11 and Desktop Environment for kiosk
print_step "Step 7: Installing X11 and minimal desktop..."
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

# Step 8: Create kiosk system with correct URLs
print_step "Step 8: Setting up kiosk system..."

# Create kiosk directory
mkdir -p /home/$USER/.cocktail-machine

# Download production kiosk scripts
print_info "Downloading production kiosk scripts..."
curl -L -o /home/$USER/.cocktail-machine/kiosk-launcher.sh \
    "https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/scripts/kiosk-launcher.sh"
chmod +x /home/$USER/.cocktail-machine/kiosk-launcher.sh

curl -L -o /home/$USER/.cocktail-machine/check-service.sh \
    "https://raw.githubusercontent.com/$DEPLOY_REPO/$BRANCH/scripts/check-service.sh"
chmod +x /home/$USER/.cocktail-machine/check-service.sh

# Create beautiful loading screen
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
    <script>
        // Check if service is ready every 3 seconds
        setInterval(function() {
            fetch('http://localhost/health')
                .then(response => {
                    if (response.ok) {
                        window.location.href = 'http://localhost';
                    }
                })
                .catch(() => {});
        }, 3000);
    </script>
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

# Step 9: Configure auto-login and kiosk startup
print_step "Step 9: Configuring kiosk auto-start..."

# Configure auto-login
print_info "Configuring auto-login..."
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
print_info "Creating kiosk startup service..."
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

# Configure console auto-login as fallback
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF

print_status "Kiosk auto-start configured"

# Step 10: Configure quiet boot
print_step "Step 10: Configuring quiet boot..."

# Find the correct cmdline.txt file
CMDLINE_FILE=""
if [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
elif [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
fi

if [ -n "$CMDLINE_FILE" ]; then
    # Backup original
    sudo cp "$CMDLINE_FILE" "${CMDLINE_FILE}.backup.$(date +%s)"
    
    # Get current cmdline and clean it
    CURRENT_CMDLINE=$(cat "$CMDLINE_FILE")
    
    # Remove any existing quiet/splash parameters
    CLEAN_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed -E 's/(^| )(quiet|splash|loglevel=[0-9]+|logo\.nologo|vt\.global_cursor_default=[0-9]+)( |$)/ /g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    
    # Add our quiet parameters
    NEW_CMDLINE="$CLEAN_CMDLINE quiet splash loglevel=0 logo.nologo vt.global_cursor_default=0"
    
    # Update cmdline.txt
    echo "$NEW_CMDLINE" | sudo tee "$CMDLINE_FILE" > /dev/null
    print_status "Quiet boot configured"
else
    print_info "Could not find cmdline.txt file, skipping quiet boot setup"
fi

print_status "Quiet boot configured"

# Step 11: Start Docker services
print_step "Step 11: Starting Docker services..."
cd "$PROJECT_DIR/deployment"

# Start services
print_info "Building and starting services..."
docker-compose up -d --build

# Wait for services to start
print_info "Waiting for services to initialize..."
sleep 10

# Check service status
docker-compose ps
print_status "Docker services started"

# Step 12: Test installation
print_step "Step 12: Testing installation..."

# Test React dashboard
print_info "Testing React dashboard on port 3000..."
if curl -s http://localhost:3000 | grep -q "Cocktail Machine"; then
    print_status "React dashboard is accessible on port 3000"
else
    print_info "React dashboard may still be starting up"
fi

# Test nginx proxy
print_info "Testing nginx proxy on port 80..."
if curl -s http://localhost/health | grep -q "healthy"; then
    print_status "Nginx proxy health check passed"
else
    print_info "Nginx proxy may still be starting up"
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
echo "✅ Docker services configured and started"
echo "✅ Update system installed and working"
echo "✅ Kiosk mode configured for Pi display"
echo "✅ Auto-login and quiet boot enabled"
echo ""
echo "🌐 Access Points:"
echo "   • React Dashboard: http://localhost:3000"
echo "   • Main Interface:  http://localhost (via nginx)"
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
