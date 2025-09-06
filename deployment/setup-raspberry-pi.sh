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
sudo apt-get update
sudo apt-get upgrade -y

# Install required packages
print_status "Installing required packages..."
sudo apt-get install -y \
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
    sudo apt-get install -y docker-compose
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
if [ -n "$DISPLAY" ] || [ "$XDG_SESSION_TYPE" = "x11" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then
    print_status "Setting up kiosk mode for dashboard display..."
    
    # Install required packages for GUI
    sudo apt-get install -y chromium-browser unclutter xdotool 2>/dev/null || 
    sudo apt-get install -y chromium unclutter xdotool 2>/dev/null
    
    # Create autostart directory if it doesn't exist
    mkdir -p /home/$USER/.config/autostart
    
    # Create kiosk script
    cat > "$PROJECT_DIR/kiosk.sh" << 'EOF'
#!/bin/bash
# Cocktail Machine Kiosk Mode Script

# Wait for network and services to be ready
sleep 30

# Get the IP address
PI_IP=$(hostname -I | cut -d' ' -f1)

# Disable screen blanking and power management
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor after 3 seconds of inactivity
unclutter -idle 3 &

# Start Chromium in kiosk mode
chromium-browser --kiosk --noerrdialogs --disable-infobars \
    --disable-session-crashed-bubble --disable-features=TranslateUI \
    --check-for-update-interval=604800 --disable-pinch \
    --overscroll-history-navigation=0 \
    "http://localhost:3000" &

# Alternative if chromium-browser command doesn't exist
if [ $? -ne 0 ]; then
    chromium --kiosk --noerrdialogs --disable-infobars \
        --disable-session-crashed-bubble --disable-features=TranslateUI \
        --check-for-update-interval=604800 --disable-pinch \
        --overscroll-history-navigation=0 \
        "http://localhost:3000" &
fi
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
    cat > "$PROJECT_DIR/start-dashboard.sh" << 'EOF'
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
    
    print_status "Kiosk mode configured! Dashboard will display on screen at startup."
else
    print_info "No display detected. Skipping kiosk mode setup."
    print_info "To set up kiosk mode later, run the setup script from the desktop environment."
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
    print_info "Reboot recommended for kiosk mode to take effect."
    echo "   sudo reboot"
else
    print_info "Setup script completed. Services should be running."
fi
