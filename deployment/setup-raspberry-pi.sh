#!/bin/bash

# Cocktail Machine - Raspberry Pi Setup Script
# Simplified and working version with official Pi kiosk method

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
if command -v raspi-config &> /dev/null; then
    print_status "Setting auto-login with raspi-config..."
    # B4 = Desktop auto-login
    sudo raspi-config nonint do_boot_behaviour B4
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
        
        location / {
            proxy_pass http://dashboard;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
        }
        
        location /admin {
            proxy_pass http://nodered;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
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

# System
TIMEZONE=Europe/Paris
EOF
    chmod 600 deployment/.env
    print_info "Environment file created at deployment/.env"
    print_info "Please update SUPABASE_URL and SUPABASE_ANON_KEY with your actual values"
fi

# Setup kiosk mode for dashboard display
print_status "Setting up dashboard display in kiosk mode..."

# Install required packages for kiosk
print_status "Installing kiosk dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    xserver-xorg \
    x11-xserver-utils \
    xinit \
    openbox \
    chromium-browser \
    rpi-chromium-mods \
    unclutter

# Create openbox config directory
mkdir -p /home/$USER/.config/openbox

# Create a loading screen HTML file
print_status "Creating loading screen..."
mkdir -p /home/$USER/.cocktail-machine
cat > /home/$USER/.cocktail-machine/loading.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Cocktail Machine Loading</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
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
            letter-spacing: 2px;
        }
        .status {
            font-size: 24px;
            margin: 20px 0;
            opacity: 0.9;
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
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        .dots {
            display: inline-block;
            animation: dots 1.5s infinite;
        }
        @keyframes dots {
            0%, 20% { content: '.'; }
            40% { content: '..'; }
            60%, 100% { content: '...'; }
        }
    </style>
    <script>
        // Auto-refresh every 3 seconds to check if service is ready
        setTimeout(function() {
            fetch('http://localhost:3000')
                .then(response => {
                    if (response.ok) {
                        window.location.href = 'http://localhost:3000';
                    }
                })
                .catch(() => {
                    setTimeout(() => window.location.reload(), 3000);
                });
        }, 3000);
    </script>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine</h1>
        <div class="loader"></div>
        <div class="status">Starting services<span class="dots">...</span></div>
        <p style="margin-top: 20px; opacity: 0.7;">Please wait while the system initializes</p>
    </div>
</body>
</html>
HTML

# Create service health check script
print_status "Creating service health check script..."
cat > /home/$USER/.cocktail-machine/wait-for-service.sh << 'SCRIPT'
#!/bin/bash
# Wait for the web dashboard to be ready

echo "Waiting for cocktail machine services to start..."

# Show loading screen immediately
chromium-browser --kiosk --noerrdialogs --disable-infobars \
    --check-for-update-interval=604800 \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --disable-translate \
    --touch-events=enabled \
    --enable-touch-drag-drop \
    --enable-touch-editing \
    --disable-features=TranslateUI \
    --disable-session-crashed-bubble \
    --disable-component-update \
    --autoplay-policy=no-user-gesture-required \
    "file:///home/${USER}/.cocktail-machine/loading.html" &

BROWSER_PID=$!

# Maximum wait time (5 minutes)
MAX_WAIT=300
WAITED=0

# First wait a bit for Docker to start
sleep 15

while [ $WAITED -lt $MAX_WAIT ]; do
    # Check if the service responds
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302"; then
        echo "Dashboard is ready!"
        # Kill the loading screen browser
        kill $BROWSER_PID 2>/dev/null || true
        sleep 1
        # Start Chromium with the dashboard
        chromium-browser --kiosk --noerrdialogs --disable-infobars \
            --check-for-update-interval=604800 \
            --disable-pinch \
            --overscroll-history-navigation=0 \
            --disable-translate \
            --touch-events=enabled \
            --enable-touch-drag-drop \
            --enable-touch-editing \
            --disable-features=TranslateUI \
            --disable-session-crashed-bubble \
            --disable-component-update \
            --autoplay-policy=no-user-gesture-required \
            http://localhost:3000 &
        exit 0
    fi
    
    echo "Service not ready yet. Waiting..."
    sleep 5
    WAITED=$((WAITED + 5))
done

echo "Service failed to start after $MAX_WAIT seconds"
# Kill loading screen and show error page
kill $BROWSER_PID 2>/dev/null || true
chromium-browser --kiosk --noerrdialogs --disable-infobars \
    "data:text/html,<html><body style='background:#f44336;color:white;display:flex;align-items:center;justify-center:center;height:100vh;font-family:sans-serif;'><div style='text-align:center;'><h1>Service Failed to Start</h1><p>Please check the system logs</p></div></body></html>" &
SCRIPT

chmod +x /home/$USER/.cocktail-machine/wait-for-service.sh

# Configure openbox autostart for kiosk mode (Official Raspberry Pi method)
print_status "Configuring kiosk mode with professional loading screen..."
cat > /home/$USER/.config/openbox/autostart << EOF
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor after 1 second
unclutter -idle 1 &

# Start the kiosk with loading screen and service check
/home/$USER/.cocktail-machine/wait-for-service.sh &
EOF

# Set proper permissions
chmod +x /home/$USER/.config/openbox/autostart

# Configure auto-login and boot to desktop
if command -v raspi-config &> /dev/null; then
    print_status "Configuring auto-login to desktop..."
    # B4 = Desktop auto-login
    sudo raspi-config nonint do_boot_behaviour B4
fi

# Ensure graphical target is set
sudo systemctl set-default graphical.target

# Configure quiet boot for professional appearance
print_status "Configuring quiet boot for professional appearance..."
# Disable boot messages (works for both /boot/cmdline.txt and /boot/firmware/cmdline.txt)
CMDLINE_FILE=""
if [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
elif [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
fi

if [ -n "$CMDLINE_FILE" ]; then
    # Backup original
    sudo cp "$CMDLINE_FILE" "${CMDLINE_FILE}.backup"
    # Add quiet splash if not already present
    if ! grep -q "quiet" "$CMDLINE_FILE"; then
        sudo sed -i 's/$/ quiet splash loglevel=0 logo.nologo vt.global_cursor_default=0/' "$CMDLINE_FILE"
    fi
fi

# Disable Plymouth boot messages (if installed)
if command -v plymouth &> /dev/null; then
    sudo plymouth-set-default-theme -R none 2>/dev/null || true
fi

# Hide fsck messages
sudo bash -c 'echo "FSCKFIX=yes" >> /etc/default/rcS' 2>/dev/null || true

# Disable systemd boot messages
sudo bash -c 'echo "ShowStatus=no" >> /etc/systemd/system.conf' 2>/dev/null || true

print_status "Kiosk mode configured! Dashboard will display on screen at startup."

# Create systemd service for auto-start
print_status "Creating systemd service for auto-start..."
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

# Create systemd service for kiosk display
print_status "Creating kiosk display service..."
sudo tee /etc/systemd/system/cocktail-kiosk.service > /dev/null << EOF
[Unit]
Description=Cocktail Machine Kiosk Display
After=graphical.target cocktail-machine.service
Wants=graphical.target

[Service]
Type=simple
User=$USER
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/$USER/.Xauthority"
ExecStartPre=/bin/sleep 10
ExecStart=/home/$USER/.cocktail-machine/wait-for-service.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

# Enable kiosk service
print_status "Enabling kiosk display service..."
sudo systemctl daemon-reload
sudo systemctl enable cocktail-kiosk.service

# Configure firewall (if ufw is installed)
if command -v ufw &> /dev/null; then
    print_status "Configuring firewall..."
    sudo ufw allow 1883/tcp  # MQTT
    sudo ufw allow 1880/tcp  # Node-RED
    sudo ufw allow 3000/tcp  # Web Dashboard
    sudo ufw allow 80/tcp    # HTTP
    sudo ufw allow 443/tcp   # HTTPS
fi

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
echo "   ✅ Kiosk mode configured - Dashboard will display on screen at startup"
echo ""

if [ -f /tmp/docker-build.log ] && grep -q "ERROR" /tmp/docker-build.log; then
    print_info "Note: Some services had build issues. Check logs with:"
    echo "   docker-compose -f $PROJECT_DIR/deployment/docker-compose.yml logs"
else
    print_status "All services are running! Your cocktail machine is ready! 🍹"
fi

echo ""
print_info "Reboot to activate kiosk mode:"
echo "   sudo reboot"
echo ""
print_info "Setup script completed successfully!"
