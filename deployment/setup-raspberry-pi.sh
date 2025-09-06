#!/bin/bash

# Cocktail Machine - Raspberry Pi 5 Setup Script
# This script automates the setup of a new Raspberry Pi for the cocktail machine

set -e  # Exit on error

echo "========================================="
echo "Cocktail Machine - Raspberry Pi Setup"
echo "========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Set non-interactive mode to prevent prompts
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Configure needrestart to not prompt
if [ -f /etc/needrestart/needrestart.conf ]; then
    sudo sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" /etc/needrestart/needrestart.conf
    sudo sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" /etc/needrestart/needrestart.conf
fi

# Configure auto-login for console
print_status "Configuring auto-login..."
# Method 1: Using raspi-config (most reliable)
if command -v raspi-config &> /dev/null; then
    print_status "Setting auto-login with raspi-config..."
    # B2 = Console auto-login
    sudo raspi-config nonint do_boot_behaviour B2
fi

# Method 2: Systemd service override (backup method)
print_status "Configuring systemd auto-login..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo bash -c "cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
Type=idle
EOF

# Method 3: For systems using lightdm
if [ -f /etc/lightdm/lightdm.conf ]; then
    print_status "Configuring LightDM auto-login..."
    sudo sed -i "s/^#autologin-user=.*/autologin-user=$USER/" /etc/lightdm/lightdm.conf 2>/dev/null || 
    echo "autologin-user=$USER" | sudo tee -a /etc/lightdm/lightdm.conf
fi

sudo systemctl daemon-reload

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    print_info "Warning: This doesn't appear to be a Raspberry Pi"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Update system
print_status "Updating system packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Install required packages
print_status "Installing required packages..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    curl \
    git \
    wget \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    python3-pip \
    jq \
    mosquitto-clients

# Install Docker
if ! command -v docker &> /dev/null; then
    print_status "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    
    # Install Docker Compose
    print_status "Installing Docker Compose..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose
else
    print_status "Docker already installed"
fi

# Enable Docker service
print_status "Enabling Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

# Create project directory
PROJECT_DIR="/home/$USER/cocktail-machine"
if [ ! -d "$PROJECT_DIR" ]; then
    print_status "Creating project directory..."
    mkdir -p "$PROJECT_DIR"
fi

# Clone or update repository
if [ -d "$PROJECT_DIR/.git" ]; then
    print_status "Updating existing repository..."
    cd "$PROJECT_DIR"
    git pull
else
    print_status "Cloning repository..."
    git clone https://github.com/sebastienlepoder/cocktail-machine.git "$PROJECT_DIR"
    cd "$PROJECT_DIR"
fi

# Create necessary directories
print_status "Creating directory structure..."
mkdir -p deployment/mosquitto/data
mkdir -p deployment/mosquitto/log
mkdir -p deployment/nodered/data
mkdir -p deployment/postgres/data
mkdir -p deployment/postgres/init
mkdir -p deployment/nginx/sites
mkdir -p deployment/nginx/ssl
mkdir -p deployment/web/public

# Create nginx configuration if it doesn't exist
if [ ! -f deployment/nginx/nginx.conf ]; then
    print_status "Creating nginx configuration..."
    cat > deployment/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream dashboard {
        server web-dashboard:3000;
    }
    
    upstream nodered {
        server nodered:1880;
    }
    
    server {
        listen 80;
        server_name _;
        
        # Main dashboard
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
        
        # Node-RED admin
        location /admin {
            proxy_pass http://nodered;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
        }
        
        # WebSocket support
        location /ws {
            proxy_pass http://dashboard;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF
fi

# Set permissions
print_status "Setting permissions..."
sudo chown -R 1883:1883 deployment/mosquitto/ 2>/dev/null || true
sudo chown -R 1000:1000 deployment/nodered/ 2>/dev/null || true

# Create environment file if it doesn't exist
if [ ! -f "deployment/.env" ]; then
    print_status "Creating environment file..."
    cat > deployment/.env << EOF
# Cocktail Machine Environment Variables
# Generated on $(date)

# Database
DB_PASSWORD=$(openssl rand -base64 32)

# Supabase (update these with your actual values)
SUPABASE_URL=your_supabase_url_here
SUPABASE_ANON_KEY=your_supabase_anon_key_here

# MQTT
MQTT_HOST=localhost
MQTT_PORT=1883

# Node-RED
NODE_RED_ADMIN_PASSWORD=cocktail_admin

# System
TIMEZONE=Europe/Paris
EOF
    chmod 600 deployment/.env
    print_info "Environment file created at deployment/.env"
    print_info "Please update SUPABASE_URL and SUPABASE_ANON_KEY with your actual values"
fi

# Create systemd service for auto-start
print_status "Creating systemd service..."
sudo tee /etc/systemd/system/cocktail-machine.service > /dev/null << EOF
[Unit]
Description=Cocktail Machine Docker Services
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR/deployment
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0
User=$USER
Group=docker

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
print_status "Enabling auto-start service..."
sudo systemctl daemon-reload
sudo systemctl enable cocktail-machine.service

# Configure firewall (if ufw is installed)
if command -v ufw &> /dev/null; then
    print_status "Configuring firewall..."
    sudo ufw allow 1883/tcp  # MQTT
    sudo ufw allow 1880/tcp  # Node-RED
    sudo ufw allow 3000/tcp  # Web Dashboard
    sudo ufw allow 80/tcp    # HTTP
    sudo ufw allow 443/tcp   # HTTPS
fi

# Install Node-RED additional nodes
print_status "Preparing Node-RED nodes list..."
cat > deployment/nodered/package.json << EOF
{
    "name": "cocktail-machine-nodered",
    "description": "Node-RED instance for Cocktail Machine",
    "version": "1.0.0",
    "dependencies": {
        "node-red-contrib-mqtt-broker": "*",
        "node-red-dashboard": "*",
        "node-red-node-ui-table": "*",
        "node-red-contrib-supabase": "*"
    }
}
EOF

# Create update script
print_status "Creating update script..."
cat > "$PROJECT_DIR/update.sh" << 'EOF'
#!/bin/bash
# Update script for Cocktail Machine

cd "$(dirname "$0")"

echo "Updating Cocktail Machine..."
git pull

cd deployment
docker-compose pull
docker-compose down
docker-compose up -d --build

echo "Update complete!"
EOF
chmod +x "$PROJECT_DIR/update.sh"

# Create backup script
print_status "Creating backup script..."
cat > "$PROJECT_DIR/backup.sh" << 'EOF'
#!/bin/bash
# Backup script for Cocktail Machine

BACKUP_DIR="/home/$USER/cocktail-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/cocktail_backup_$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Creating backup..."
cd "$(dirname "$0")"

# Backup important data
tar -czf "$BACKUP_FILE" \
    deployment/mosquitto/data \
    deployment/nodered/data \
    deployment/postgres/data \
    deployment/.env \
    2>/dev/null

echo "Backup saved to: $BACKUP_FILE"

# Keep only last 5 backups
ls -t "$BACKUP_DIR"/cocktail_backup_*.tar.gz | tail -n +6 | xargs -r rm
EOF
chmod +x "$PROJECT_DIR/backup.sh"

# Setup cron for automatic backups
print_status "Setting up automatic backups..."
(crontab -l 2>/dev/null; echo "0 2 * * * $PROJECT_DIR/backup.sh") | crontab -

# Setup kiosk mode for dashboard display
print_status "Checking for desktop environment..."

# Check if we have a desktop environment, if not install a minimal one
if ! command -v startx &> /dev/null && ! command -v chromium-browser &> /dev/null && ! command -v chromium &> /dev/null; then
    print_status "No desktop environment detected. Installing minimal GUI for dashboard..."
    
    # Install minimal X server and window manager
    sudo DEBIAN_FRONTEND=noninteractive apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        xserver-xorg \
        x11-xserver-utils \
        xinit \
        openbox \
        chromium-browser \
        unclutter \
        lightdm
    
    # Configure auto-login for lightdm
    print_status "Configuring auto-login..."
    sudo mkdir -p /etc/lightdm
    sudo bash -c "cat > /etc/lightdm/lightdm.conf" << EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
user-session=openbox
greeter-session=pi-greeter
EOF
    
    # Enable GUI boot
    print_status "Enabling GUI boot..."
    sudo systemctl set-default graphical.target
    sudo systemctl enable lightdm.service
    
    # Configure raspi-config for GUI boot
    if command -v raspi-config &> /dev/null; then
        sudo raspi-config nonint do_boot_behaviour B4 || true
    fi
    
    print_status "Minimal desktop environment installed."
    
    # Create a simple .bash_profile to auto-start X if not running
    cat >> /home/$USER/.bash_profile << 'EOF'

# Auto-start kiosk mode if on console
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec startx /home/pi/cocktail-machine/kiosk.sh -- -nocursor
fi
EOF
    
    # Alternative: Configure auto-login on tty1
    print_status "Configuring console auto-login..."
    sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
    sudo bash -c "cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF
    sudo systemctl daemon-reload
fi

# Now proceed with kiosk setup
if command -v chromium-browser &> /dev/null || command -v chromium &> /dev/null; then
    print_status "Setting up kiosk mode for dashboard display..."
    
    # Install additional required packages
    sudo apt-get install -y unclutter 2>/dev/null || true
    
    # Create autostart directory if it doesn't exist
    mkdir -p /home/$USER/.config/autostart
    
    # Create kiosk script
    cat > "$PROJECT_DIR/kiosk.sh" << 'EOF'
#!/bin/bash
# Cocktail Machine Kiosk Mode Script

# Wait for network and services to be ready
echo "Waiting for services to start..."
sleep 20

# Wait for web service to be available
while ! curl -s http://localhost:3000 > /dev/null 2>&1; do
    echo "Waiting for dashboard to be ready..."
    sleep 5
done

# Disable screen blanking and power management (if X is available)
if command -v xset &> /dev/null; then
    xset s off
    xset -dpms
    xset s noblank
fi

# Hide mouse cursor after 3 seconds of inactivity
if command -v unclutter &> /dev/null; then
    unclutter -idle 3 &
fi

# Determine which chromium command to use
if command -v chromium-browser &> /dev/null; then
    CHROMIUM_CMD="chromium-browser"
elif command -v chromium &> /dev/null; then
    CHROMIUM_CMD="chromium"
else
    echo "Error: Chromium not found!"
    exit 1
fi

echo "Starting dashboard in kiosk mode..."

# Start Chromium in kiosk mode
exec $CHROMIUM_CMD \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-features=TranslateUI \
    --check-for-update-interval=604800 \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --no-first-run \
    --disable-translate \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-renderer-backgrounding \
    --window-position=0,0 \
    --window-size=1920,1080 \
    "http://localhost:3000"
EOF
    chmod +x "$PROJECT_DIR/kiosk.sh"
    
    # Create desktop autostart entry
    cat > /home/$USER/.config/autostart/cocktail-kiosk.desktop << EOF
[Desktop Entry]
Type=Application
Name=Cocktail Machine Dashboard
Exec=$PROJECT_DIR/kiosk.sh
Hidden=false
X-GNOME-Autostart-enabled=true
Comment=Start Cocktail Machine Dashboard in Kiosk Mode
EOF
    
    # For Raspberry Pi OS Lite with X11 (if using startx)
    if [ -f /home/$USER/.xinitrc ]; then
        echo "exec $PROJECT_DIR/kiosk.sh" >> /home/$USER/.xinitrc
    fi
    
    # For Openbox (minimal desktop)
    mkdir -p /home/$USER/.config/openbox
    cat > /home/$USER/.config/openbox/autostart << EOF
# Cocktail Machine Kiosk Autostart
$PROJECT_DIR/kiosk.sh &
EOF
    chmod +x /home/$USER/.config/openbox/autostart
    
    # For systems using LXDE (Raspberry Pi OS Desktop)
    if [ -d /home/$USER/.config/lxsession/LXDE-pi ]; then
        mkdir -p /home/$USER/.config/lxsession/LXDE-pi
        cat > /home/$USER/.config/lxsession/LXDE-pi/autostart << EOF
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash
@$PROJECT_DIR/kiosk.sh
EOF
    fi
    
    # For Wayfire (newer Raspberry Pi OS)
    if [ -f /home/$USER/.config/wayfire.ini ]; then
        print_info "Configuring Wayfire for kiosk mode..."
        # Add autostart entry to wayfire.ini if not already present
        if ! grep -q "cocktail-kiosk" /home/$USER/.config/wayfire.ini; then
            cat >> /home/$USER/.config/wayfire.ini << EOF

[autostart]
coctail_kiosk = $PROJECT_DIR/kiosk.sh
EOF
        fi
    fi
    
    # Disable screen blanking in console
    sudo bash -c 'echo -e "\n# Disable screen blanking\nconsoleblank=0" >> /boot/cmdline.txt' 2>/dev/null || true
    
    # Create a simple launcher script
    cat > "$PROJECT_DIR/start-dashboard.sh" << EOF
#!/bin/bash
# Manual launcher for Cocktail Machine Dashboard

echo "Starting Cocktail Machine Dashboard..."
echo "Press Ctrl+Alt+F1 to exit kiosk mode"

# Kill any existing browser instances
pkill -f chromium

# Start the kiosk
exec $PROJECT_DIR/kiosk.sh
EOF
    chmod +x "$PROJECT_DIR/start-dashboard.sh"
    
    # Create framebuffer kiosk script (no X needed)
    cat > "$PROJECT_DIR/kiosk-fb.sh" << 'EOF'
#!/bin/bash
# Framebuffer Kiosk Mode - runs without X server

echo "Starting framebuffer kiosk mode..."

# Wait for services
sleep 10

# Install chromium if needed
if ! command -v chromium-browser &> /dev/null && ! command -v chromium &> /dev/null; then
    echo "Installing Chromium browser..."
    sudo apt-get update
    sudo apt-get install -y chromium-browser || sudo apt-get install -y chromium
fi

# Use chromium in framebuffer mode
if command -v chromium-browser &> /dev/null; then
    BROWSER="chromium-browser"
else
    BROWSER="chromium"
fi

# Run browser without X
sudo $BROWSER \
    --kiosk \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-dev-tools \
    --noerrdialogs \
    --disable-infobars \
    --disable-translate \
    --disable-features=TranslateUI \
    --disk-cache-dir=/tmp/cache \
    --aggressive-cache-discard \
    --disable-application-cache \
    --media-cache-size=1 \
    --disk-cache-size=1 \
    --enable-features=OverlayScrollbar \
    --start-fullscreen \
    --window-position=0,0 \
    --display=:0 \
    http://localhost:3000
EOF
    chmod +x "$PROJECT_DIR/kiosk-fb.sh"
    
    # Create auto-start service for framebuffer kiosk
    sudo bash -c "cat > /etc/systemd/system/cocktail-kiosk.service" << EOF
[Unit]
Description=Cocktail Machine Kiosk Mode
After=multi-user.target docker.service
Wants=docker.service

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
User=$USER
Environment="HOME=/home/$USER"
ExecStartPre=/bin/sleep 20
ExecStart=/home/$USER/cocktail-machine/kiosk-fb.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable cocktail-kiosk.service
    
    print_status "Kiosk mode configured! Dashboard will display on screen at startup."
    
    # Add auto-start to bashrc for console login
    if ! grep -q "start-kiosk" /home/$USER/.bashrc; then
        print_status "Adding kiosk auto-start to bashrc..."
        cat >> /home/$USER/.bashrc << 'EOF'

# Auto-start Cocktail Machine Dashboard
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    echo "Starting Cocktail Machine Dashboard..."
    if [ -f /home/pi/cocktail-machine/start-kiosk.sh ]; then
        exec /home/pi/cocktail-machine/start-kiosk.sh
    elif [ -f /home/pi/cocktail-machine/kiosk.sh ]; then
        exec startx /home/pi/cocktail-machine/kiosk.sh 2>/dev/null || 
             sudo startx /home/pi/cocktail-machine/kiosk.sh
    fi
fi
EOF
    fi
    
    print_info "The system will reboot into kiosk mode."
else
    print_info "Chromium browser not available. Please install a desktop environment."
fi

# Start Docker services
print_status "Starting Docker services..."
cd "$PROJECT_DIR/deployment"

# Clean any previous failed builds
docker system prune -f > /dev/null 2>&1

# Try to start all services
print_status "Building and starting services (this may take several minutes)..."
if docker-compose up -d --build 2>&1 | tee /tmp/docker-build.log; then
    print_status "All services started successfully!"
else
    print_info "Some services may have failed to start. Checking core services..."
    
    # Start core services without web dashboard if it fails
    print_status "Starting core services (MQTT, Node-RED, Database)..."
    docker-compose up -d mosquitto postgres nodered 2>/dev/null
    
    print_info "Web dashboard may need manual setup. Core services should be running."
fi

# Wait for services to initialize
print_status "Waiting for services to initialize..."
sleep 10

# Check service status
print_status "Checking service status..."
docker-compose ps

# Get IP address
PI_IP=$(hostname -I | cut -d' ' -f1)

# Test MQTT connection
if command -v mosquitto_sub &> /dev/null; then
    print_status "Testing MQTT broker..."
    timeout 2 mosquitto_sub -h localhost -t "test" -C 1 &> /dev/null && print_status "MQTT broker is running!" || print_info "MQTT broker may still be starting"
fi

# Display status
echo ""
echo "========================================="
print_status "Setup complete!"
echo "========================================="
echo ""
echo "🍹 Cocktail Machine Services:"
echo "========================================="
echo "📍 Access your services at:"
echo "   🔧 Node-RED:       http://$PI_IP:1880"
echo "   🌐 Web Dashboard:  http://$PI_IP:3000"
echo "   📊 MQTT Broker:    $PI_IP:1883"
echo ""
echo "📝 Configuration:"
echo "   Environment: $PROJECT_DIR/deployment/.env"
echo "   "
echo "🔧 Management Commands:"
echo "   Update:  $PROJECT_DIR/update.sh"
echo "   Backup:  $PROJECT_DIR/backup.sh"
echo "   Logs:    docker-compose -f $PROJECT_DIR/deployment/docker-compose.yml logs -f"
echo "   Status:  docker-compose -f $PROJECT_DIR/deployment/docker-compose.yml ps"
echo ""
echo "⚙️ ESP32 Configuration:"
echo "   Set MQTT_SERVER to: $PI_IP"
echo "   in your ESP32 config.h file"
echo ""
echo "🖥️ Display Configuration:"
if [ -f "$PROJECT_DIR/kiosk.sh" ]; then
    echo "   ✅ Kiosk mode configured - Dashboard will display on screen at startup"
    echo "   Manual start: $PROJECT_DIR/start-dashboard.sh"
else
    echo "   ℹ️ Connect a display and run setup again for kiosk mode"
fi
echo ""

if [ -f /tmp/docker-build.log ] && grep -q "ERROR" /tmp/docker-build.log; then
    print_info "Note: Some services had build issues. Check logs with:"
    echo "   docker-compose -f $PROJECT_DIR/deployment/docker-compose.yml logs"
else
    print_status "All services are running! Your cocktail machine is ready! 🍹"
fi

echo ""
if [ -f "$PROJECT_DIR/kiosk.sh" ]; then
    print_info "Reboot to activate kiosk mode:"
    echo "   sudo reboot"
    echo ""
    print_info "If dashboard doesn't start automatically after reboot, try:"
    echo "   startx /home/pi/cocktail-machine/kiosk.sh"
    echo "   OR"
    echo "   sudo systemctl start lightdm"
else
    print_info "Setup script completed. Services should be running."
fi
