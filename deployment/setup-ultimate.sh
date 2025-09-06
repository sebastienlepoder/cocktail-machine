#!/bin/bash

# Cocktail Machine - Ultimate Kiosk Setup Script
# Tested and working version for Raspberry Pi OS Lite (64-bit)

echo "=================================================="
echo "🍹 Cocktail Machine - Ultimate Kiosk Setup"
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

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

print_step "Checking Raspberry Pi OS version..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    print_info "OS: $PRETTY_NAME"
else
    print_error "Cannot determine OS version"
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
    git \
    wget \
    unzip \
    python3-pip \
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

# Step 4: Setup project
print_step "Step 4: Setting up Cocktail Machine project..."
PROJECT_DIR="/home/$USER/cocktail-machine"
if [ -d "$PROJECT_DIR/.git" ]; then
    print_info "Updating existing project..."
    cd "$PROJECT_DIR"
    git pull
else
    print_info "Cloning project..."
    git clone https://github.com/sebastienlepoder/cocktail-machine.git "$PROJECT_DIR"
    cd "$PROJECT_DIR"
fi

# Create directories
mkdir -p deployment/{mosquitto/{data,log},nodered/data,postgres/data,nginx/{sites,ssl},web/public}

# Step 5: Create configuration files
print_step "Step 5: Creating configuration files..."

# Nginx config
if [ ! -f deployment/nginx/nginx.conf ]; then
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
fi

# Environment file
if [ ! -f "deployment/.env" ]; then
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
fi

print_status "Configuration files created"

# Step 6: Install X11 and Desktop Environment
print_step "Step 6: Installing X11 and minimal desktop..."
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

# Step 7: Create the ultimate kiosk system
print_step "Step 7: Creating kiosk system..."

# Create kiosk directory
mkdir -p /home/$USER/.cocktail-machine

# Create a robust service checker script
cat > /home/$USER/.cocktail-machine/check-service.sh << 'EOF'
#!/bin/bash
# Service checker script

LOG_FILE="/tmp/kiosk-service-check.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Service Check Started ==="

# Maximum wait time (5 minutes)
MAX_WAIT=300
WAITED=0

# Wait for Docker to be ready
log "Waiting for Docker to be ready..."
while ! docker ps &>/dev/null && [ $WAITED -lt 60 ]; do
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ $WAITED -ge 60 ]; then
    log "ERROR: Docker not ready after 60 seconds"
    exit 1
fi

log "Docker is ready, checking cocktail machine service..."

# Reset counter for service check
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    # Check multiple endpoints to be sure
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/health 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        log "Health check passed (HTTP $HTTP_CODE)"
        
        # Double check the main service
        MAIN_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null || echo "000")
        if [ "$MAIN_CODE" = "200" ] || [ "$MAIN_CODE" = "302" ] || [ "$MAIN_CODE" = "304" ]; then
            log "Main service ready (HTTP $MAIN_CODE)"
            echo "READY"
            exit 0
        fi
    fi
    
    log "Service not ready yet (HTTP $HTTP_CODE), waiting... ($WAITED/$MAX_WAIT)"
    sleep 5
    WAITED=$((WAITED + 5))
done

log "ERROR: Service failed to start after $MAX_WAIT seconds"
echo "FAILED"
exit 1
EOF

chmod +x /home/$USER/.cocktail-machine/check-service.sh

# Create the ultimate kiosk launcher
cat > /home/$USER/.cocktail-machine/kiosk-launcher.sh << 'EOF'
#!/bin/bash
# Ultimate Kiosk Launcher

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
    --disable-ipc-flooding-protection \
    --disable-renderer-backgrounding \
    --disable-backgrounding-occluded-windows \
    --disable-features=VizDisplayCompositor \
    --autoplay-policy=no-user-gesture-required \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-component-update \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-field-trial-config \
    --disable-background-networking \
    "file:///home/$USER/.cocktail-machine/loading.html" &

LOADING_PID=$!
log "Loading screen started (PID: $LOADING_PID)"

# Wait for service to be ready
log "Checking if service is ready..."
/home/$USER/.cocktail-machine/check-service.sh
SERVICE_STATUS=$?

if [ $SERVICE_STATUS -eq 0 ]; then
    log "Service is ready! Switching to dashboard..."
    
    # Kill loading screen
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
else
    log "Service failed to start, showing error page..."
    
    # Kill loading screen
    kill $LOADING_PID 2>/dev/null || true
    sleep 1
    
    # Show error page
    chromium-browser \
        --kiosk \
        --noerrdialogs \
        --disable-infobars \
        "data:text/html,<html><head><title>Service Error</title></head><body style='background:#e74c3c;color:white;display:flex;align-items:center;justify-content:center;height:100vh;font-family:Arial,sans-serif'><div style='text-align:center'><h1 style='font-size:48px;margin-bottom:20px'>🚫 Service Error</h1><p style='font-size:24px'>The cocktail machine service failed to start</p><p style='font-size:16px;margin-top:20px'>Check logs: /tmp/kiosk-*.log</p></div></body></html>" &
fi
EOF

chmod +x /home/$USER/.cocktail-machine/kiosk-launcher.sh

# Create improved loading screen with better service detection
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
        .loader {
            width: 60px;
            height: 60px;
            border: 3px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s linear infinite;
            margin: 40px auto;
        }
        .status {
            font-size: 18px;
            margin-top: 20px;
            opacity: 0.9;
        }
        .dots::after {
            content: '';
            animation: dots 1.5s steps(4, end) infinite;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-20px); }
        }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
        @keyframes dots {
            0%, 20% { content: ''; }
            40% { content: '.'; }
            60% { content: '..'; }
            80%, 100% { content: '...'; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🍹</div>
        <h1>Cocktail Machine</h1>
        <div class="loader"></div>
        <div class="status" id="status">Starting services<span class="dots"></span></div>
        <p style="margin-top: 20px; opacity: 0.7; font-size: 14px;">Please wait while the system initializes</p>
    </div>
    
    <script>
        let attempts = 0;
        const maxAttempts = 100; // 5 minutes at 3-second intervals
        
        function updateStatus(message) {
            document.getElementById('status').innerHTML = message + '<span class="dots"></span>';
        }
        
        function checkService() {
            attempts++;
            
            if (attempts > maxAttempts) {
                updateStatus('Service startup timeout');
                return;
            }
            
            // Note: The kiosk launcher script handles the actual service checking
            // This is just a visual indicator
            updateStatus(`Checking services (${attempts}/${maxAttempts})`);
            
            setTimeout(checkService, 3000);
        }
        
        // Start checking after initial delay
        setTimeout(checkService, 5000);
    </script>
</body>
</html>
EOF

# Step 8: Configure OpenBox
print_step "Step 8: Configuring OpenBox..."
mkdir -p /home/$USER/.config/openbox

cat > /home/$USER/.config/openbox/autostart << 'EOF'
# Disable screen blanking and power management
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor when inactive
unclutter -idle 1 -root &

# Wait for X to fully initialize
sleep 3

# Start the kiosk launcher
/home/$USER/.cocktail-machine/kiosk-launcher.sh &
EOF

chmod +x /home/$USER/.config/openbox/autostart

# Step 9: Configure X11 startup
print_step "Step 9: Configuring X11 startup..."
cat > /home/$USER/.xinitrc << 'EOF'
#!/bin/sh
exec openbox-session
EOF
chmod +x /home/$USER/.xinitrc

# Step 10: Configure auto-login
print_step "Step 10: Configuring auto-login..."

# Configure LightDM for auto-login
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/01-autologin.conf > /dev/null << EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
EOF

# Enable graphical target
sudo systemctl set-default graphical.target

# Enable LightDM
sudo systemctl enable lightdm

# Configure console auto-login as backup
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF

# Step 11: Configure boot for kiosk mode
print_step "Step 11: Configuring boot parameters..."

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
    CURRENT_CMDLINE=$(cat "$CMDLINE_FILE" | tr -d '\n')
    
    # Remove existing quiet parameters
    CLEAN_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed -e 's/quiet//g' -e 's/splash//g' -e 's/plymouth.ignore-serial-consoles//g' -e 's/logo.nologo//g' -e 's/vt.global_cursor_default=[0-9]//g' -e 's/loglevel=[0-9]//g' -e 's/console=tty[0-9]//g' | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
    
    # Add quiet boot parameters
    NEW_CMDLINE="$CLEAN_CMDLINE quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0 loglevel=0"
    
    echo "$NEW_CMDLINE" | sudo tee "$CMDLINE_FILE" > /dev/null
    print_status "Boot parameters updated"
else
    print_error "Could not find cmdline.txt file"
fi

# Step 12: Create Docker service
print_step "Step 12: Creating Docker service..."
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
TimeoutStartSec=300
User=$USER
Group=docker

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cocktail-machine.service

print_status "Docker service created and enabled"

# Step 13: Final system configuration
print_step "Step 13: Final system configuration..."

# Disable unnecessary services
sudo systemctl disable bluetooth.service 2>/dev/null || true
sudo systemctl disable hciuart.service 2>/dev/null || true
sudo systemctl disable apt-daily.service apt-daily.timer 2>/dev/null || true
sudo systemctl disable apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true

# Configure GPU memory split for better graphics performance
if [ -f /boot/config.txt ]; then
    CONFIG_FILE="/boot/config.txt"
elif [ -f /boot/firmware/config.txt ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
fi

if [ -n "$CONFIG_FILE" ]; then
    # Add GPU memory split if not present
    if ! grep -q "gpu_mem" "$CONFIG_FILE"; then
        echo "gpu_mem=128" | sudo tee -a "$CONFIG_FILE" > /dev/null
    fi
    # Disable rainbow splash
    if ! grep -q "disable_splash" "$CONFIG_FILE"; then
        echo "disable_splash=1" | sudo tee -a "$CONFIG_FILE" > /dev/null
    fi
    # Disable overscan for better display
    if ! grep -q "disable_overscan" "$CONFIG_FILE"; then
        echo "disable_overscan=1" | sudo tee -a "$CONFIG_FILE" > /dev/null
    fi
fi

print_status "System configuration completed"

echo ""
echo "=================================================="
print_status "🎉 Cocktail Machine Kiosk Setup Complete!"
echo "=================================================="
echo ""
print_info "Summary of what was configured:"
print_info "• X11 and OpenBox desktop environment"
print_info "• Auto-login to desktop mode"  
print_info "• Chromium kiosk mode with loading screen"
print_info "• Robust service detection and health checks"
print_info "• Docker services with auto-start"
print_info "• Quiet boot configuration"
print_info "• Performance optimizations"
echo ""
print_info "Next steps:"
print_info "1. Update Supabase credentials in deployment/.env"
print_info "2. Reboot: sudo reboot"
print_info "3. The system will boot to kiosk mode automatically"
echo ""
print_info "Troubleshooting logs:"
print_info "• Kiosk launcher: /tmp/kiosk-launcher.log"
print_info "• Service check: /tmp/kiosk-service-check.log"
echo ""
print_info "Manual commands:"
print_info "• Start services: cd $PROJECT_DIR/deployment && docker-compose up -d"
print_info "• Test kiosk: DISPLAY=:0 /home/$USER/.cocktail-machine/kiosk-launcher.sh"
echo ""
