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
    jq

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

# Display status
print_status "Setup complete!"
echo ""
echo "========================================="
echo "Next Steps:"
echo "========================================="
echo "1. Update environment variables in: deployment/.env"
echo "2. Start services: cd $PROJECT_DIR/deployment && docker-compose up -d"
echo "3. Access services:"
echo "   - Node-RED: http://$(hostname -I | cut -d' ' -f1):1880"
echo "   - Web Dashboard: http://$(hostname -I | cut -d' ' -f1):3000"
echo "   - MQTT: $(hostname -I | cut -d' ' -f1):1883"
echo ""
echo "Useful commands:"
echo "   - Update system: $PROJECT_DIR/update.sh"
echo "   - Create backup: $PROJECT_DIR/backup.sh"
echo "   - View logs: cd $PROJECT_DIR/deployment && docker-compose logs -f"
echo ""
print_info "Please reboot to ensure all services start correctly"
