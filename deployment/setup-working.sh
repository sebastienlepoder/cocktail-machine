#!/bin/bash

# Cocktail Machine - Working Setup Script
# Simplified version that actually works

echo "========================================="
echo "Cocktail Machine - Raspberry Pi Setup"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[i]${NC} $1"
}

# Don't exit on error - let's handle errors manually
set +e

# Set non-interactive mode
export DEBIAN_FRONTEND=noninteractive

print_status "Step 1: Updating system..."
sudo apt-get update || print_error "Failed to update package list"

print_status "Step 2: Installing basic packages..."
sudo apt-get install -y curl git wget python3-pip jq || print_error "Failed to install basic packages"

print_status "Step 3: Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    sudo apt-get install -y docker-compose
    print_status "Docker installed successfully"
else
    print_status "Docker already installed"
fi

# Enable Docker
sudo systemctl enable docker
sudo systemctl start docker

print_status "Step 4: Setting up project..."
PROJECT_DIR="/home/$USER/cocktail-machine"
if [ -d "$PROJECT_DIR/.git" ]; then
    print_status "Updating existing project..."
    cd "$PROJECT_DIR"
    git pull
else
    print_status "Cloning project..."
    git clone https://github.com/sebastienlepoder/cocktail-machine.git "$PROJECT_DIR"
    cd "$PROJECT_DIR"
fi

print_status "Step 5: Creating directories..."
mkdir -p deployment/mosquitto/data
mkdir -p deployment/mosquitto/log  
mkdir -p deployment/nodered/data
mkdir -p deployment/postgres/data
mkdir -p deployment/nginx/sites
mkdir -p deployment/web/public

print_status "Step 6: Creating nginx config..."
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

print_status "Step 7: Creating environment file..."
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
    print_info "Environment file created at deployment/.env"
fi

print_status "Step 8: Setting up kiosk mode..."

# Install GUI packages
print_status "Installing desktop environment..."
sudo apt-get install -y \
    xserver-xorg \
    x11-xserver-utils \
    xinit \
    openbox \
    chromium-browser \
    unclutter

# Create kiosk directories
mkdir -p /home/$USER/.cocktail-machine
mkdir -p /home/$USER/.config/openbox

print_status "Step 9: Creating loading screen..."
cat > /home/$USER/.cocktail-machine/loading.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
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
        @keyframes spin { to { transform: rotate(360deg); } }
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-20px); }
        }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
    </style>
    <script>
        setInterval(function() {
            fetch('http://localhost:3000')
                .then(response => {
                    if (response.ok) {
                        window.location.href = 'http://localhost:3000';
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

print_status "Step 10: Creating kiosk script..."
cat > /home/$USER/.cocktail-machine/kiosk.sh << 'EOF'
#!/bin/bash
# Kiosk startup script

export DISPLAY=:0

# Wait for X to start
sleep 5

# Kill any existing chromium
pkill -f chromium 2>/dev/null

# Start with loading screen
chromium-browser --kiosk --noerrdialogs --disable-infobars \
    "file:///home/$USER/.cocktail-machine/loading.html" &

echo "Kiosk started with loading screen"
EOF

chmod +x /home/$USER/.cocktail-machine/kiosk.sh

print_status "Step 11: Creating openbox autostart..."
cat > /home/$USER/.config/openbox/autostart << EOF
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor
unclutter -idle 1 &

# Start kiosk
/home/$USER/.cocktail-machine/kiosk.sh &
EOF

chmod +x /home/$USER/.config/openbox/autostart

print_status "Step 12: Setting up auto-start..."
# Create .xinitrc
cat > /home/$USER/.xinitrc << 'EOF'
#!/bin/sh
exec openbox-session
EOF
chmod +x /home/$USER/.xinitrc

# Add to .bashrc
if ! grep -q "startx" /home/$USER/.bashrc; then
    echo '
# Auto-start X if not SSH session
if [ -z "$SSH_TTY" ] && [ "$TERM" = "linux" ]; then
    startx
fi' >> /home/$USER/.bashrc
fi

print_status "Step 13: Creating Docker service..."
sudo tee /etc/systemd/system/cocktail-machine.service > /dev/null << EOF
[Unit]
Description=Cocktail Machine Docker Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR/deployment
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
User=$USER
Group=docker

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cocktail-machine.service

print_status "Step 14: Configuring auto-login..."
# Try raspi-config if available
if command -v raspi-config &> /dev/null; then
    sudo raspi-config nonint do_boot_behaviour B4 2>/dev/null || print_info "Using alternative auto-login method"
fi

# Alternative auto-login method
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF

sudo systemctl set-default graphical.target

print_status "Setup completed successfully!"
print_info "The system is ready. After reboot:"
print_info "1. Auto-login will occur"
print_info "2. Desktop will start"
print_info "3. Loading screen will appear"
print_info "4. Dashboard will load when services are ready"
print_info ""
print_info "To start services now: cd $PROJECT_DIR/deployment && docker-compose up -d"
print_info "To reboot: sudo reboot"
