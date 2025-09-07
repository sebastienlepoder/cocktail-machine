# 🚀 Cocktail Machine Deployment & Update System

This document explains how to deploy dashboard updates and how Pi users can easily update their systems.

## 🏗️ System Overview

### 📚 Repository Structure

The cocktail machine uses a **dev → production deployment model** with separate repositories:

| Repository | Type | Purpose | URL |
|------------|------|---------|-----|
| `warp-cocktail-machine` | **Local Dev** | Your development environment | *This repo* |
| `cocktail-machine` | **GitHub Dev** | Development repo (synced via Warp) | https://github.com/sebastienlepoder/cocktail-machine |
| `cocktail-deploy` | **Production** | Built releases for Pi users | https://github.com/sebastienlepoder/cocktail-deploy |

### 🔄 Deployment Flow

```
💻 Local Development    🚀 GitHub Dev         🏭 Production          🤖 Pi Users
(warp-cocktail-     (cocktail-machine)   (cocktail-deploy)    (Raspberry Pi)
machine)            │                    │                   │
│                   │                    │                   │
│-- Warp sync ---▶│                    │                   │
                    │-- Manual deploy -▶│                   │
                                          │-- Auto notify -▶│
```

### 🏠 System Components

1. **GitHub Actions** - Manual deployment workflow (dev → prod)
2. **Node-RED Update System** - Built-in update interface on the Pi
3. **Update Scripts** - Command-line tools for Pi users
4. **Version Management** - Automatic versioning and release notes

## 🔧 Initial Setup

### 1. Create Deployment Repository

First, create the `cocktail-deploy` repository on GitHub:

```bash
# Create new repository
gh repo create sebastienlepoder/cocktail-deploy --public --description "Cocktail Machine Pi Deployment Releases"

# Clone and set up basic structure
git clone https://github.com/sebastienlepoder/cocktail-deploy.git
cd cocktail-deploy

# Create initial structure
mkdir -p web scripts kiosk
echo "v0.0.1" > web/VERSION
echo "# Cocktail Machine Deployment Repo" > README.md

# Initial commit
git add .
git commit -m "Initial deployment repository setup"
git push origin main
```

### 2. Configure GitHub Secrets

In your **development repository** (`cocktail-machine` on GitHub), add these secrets:

1. Go to https://github.com/sebastienlepoder/cocktail-machine/settings/secrets/actions
2. Click **"New repository secret"**
3. Add this secret:

```
Name: DEPLOY_TOKEN
Value: [Your Personal Access Token]
```

**To create the Personal Access Token:**
- Go to **GitHub Settings** → **Developer settings** → **Personal access tokens**
- Create a token with `repo` permissions
- Copy the token value to use as the `DEPLOY_TOKEN` secret value

### 3. Set Up Node-RED Flow

Your Node-RED flow already has the update system! It includes:
- Update status checking at `/api/update/status`
- Update installation at `/api/update/now` 
- Built-in UI in the "Updates" tab
- Automatic version checking every 10 minutes

## 📦 How Deployments Work

### Development to Production Workflow

**Your repositories:**
- **Development:** `warp-cocktail-machine` (local) ↔ `cocktail-machine` (GitHub)
- **Production:** `cocktail-deploy` (GitHub)

**Deployment process:**
1. **Develop locally** in `warp-cocktail-machine` (synced to `cocktail-machine` via Warp)
2. **When ready for production:** Manually deploy from dev to prod
3. **Pi users:** Get automatic update notifications

### Manual Dev → Prod Deployment (Recommended)

**When your dev repo is ready for Pi users:**

1. Go to **Actions** tab in [`cocktail-machine`](https://github.com/sebastienlepoder/cocktail-machine) repository
2. Select **"🚀 Dev → Prod Deployment"** workflow
3. Click **"Run workflow"**
4. Fill out the deployment form:
   - **Release type:** `minor` (normal), `patch` (bugfix), `major` (big changes)
   - **Release notes:** Description of what's new
   - **Force deploy:** Only if deploying without changes
5. Click **"Run workflow"** button
6. **Wait 2-3 minutes** for completion
7. **Pi users get notified** automatically!

**What happens during deployment:**
1. **Builds** the dashboard from your dev repo (`npm run build`)
2. **Creates** production package with version number
3. **Generates** `versions.json` for the update system
4. **Deploys** to the `cocktail-deploy` production repository
5. **Updates** Pi user notification system

### Legacy Auto-Deployment

*Note: The auto-deployment workflow is still available but not the recommended approach for production releases.*

## 🔄 How Pi Users Update

Pi users have **4 easy ways** to update their dashboard:

### Method 1: Node-RED Dashboard (Recommended)
1. Open Node-RED dashboard: `http://pi-ip:1880/ui`
2. Go to **Updates** tab
3. Click **Install Update** button
4. Wait for update to complete

### Method 2: API Call
```bash
# Check for updates
curl http://pi-ip:1880/api/update/status

# Install update
curl -X POST http://pi-ip:1880/api/update/now
```

### Method 3: Update Script
```bash
# Run the full update script
sudo /opt/scripts/update_dashboard.sh

# Or install specific version
sudo /opt/scripts/update_dashboard.sh v2.1.0
```

### Method 4: Quick Update (One-liner)
```bash
# Download latest update script and run
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/scripts/quick-update.sh)"
```

### Method 5: Manual Service Start
If you need to manually start/restart the Docker services:
```bash
# Using the convenient start script
cd ~/cocktail-machine/deployment && ./start-services.sh

# Or using docker-compose directly
cd ~/cocktail-machine/deployment && docker-compose up -d
```

## 📝 Version Management

### Version Format
Versions follow the format: `vYYYY.MM.DD-GITHASH`

Examples:
- `v2024.12.15-a1b2c3d` - Deployed on Dec 15, 2024
- `v2024.12.16-f4e5d6c` - Next day update

### Version Files

**`/opt/webroot/VERSION`** - Current installed version on Pi
**`web/versions.json`** - Available versions and release notes:

```json
{
  "dashboard": {
    "latest": "v2024.12.15-a1b2c3d",
    "artifact": "web.tar.gz",
    "notes": [
      "Updated dashboard from commit a1b2c3d",
      "Built on 2024-12-15T10:30:00Z",
      "Latest features and improvements"
    ]
  },
  "modules": {
    "latest": "v1.0.0",
    "notes": ["Stable bottle module firmware"]
  },
  "backend": {
    "latest": "v1.0.0", 
    "notes": ["Node-RED cocktail control flow"]
  }
}
```

## 🛠️ Customization Options

### Environment Variables

Users can customize update behavior with environment variables:

```bash
# Custom deployment repository
export DEPLOY_REPO="myusername/my-cocktail-deploy"

# Custom branch
export BRANCH="production"

# Custom paths
export WEBROOT="/var/www/html"
export BACKUP_DIR="/home/pi/backups"

# GitHub token for private repos
export RAW_GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# Then run update
sudo -E /opt/scripts/update_dashboard.sh
```

### Custom Update Script Location

Update scripts are downloaded from:
```
https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/scripts/update_dashboard.sh
```

You can host your own version by changing the `DEPLOY_REPO` environment variable.

## 🔍 Troubleshooting

### Common Issues

**1. Permission Errors**
```bash
# Fix file permissions
sudo chown -R www-data:www-data /opt/webroot
sudo chmod -R 755 /opt/webroot
```

**2. Download Failures**
```bash
# Check internet connectivity
ping github.com

# Check if URLs are accessible
curl -I https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/web/versions.json
```

**3. Node-RED API Not Working**
```bash
# Check if Node-RED is running
systemctl status nodered

# Check Node-RED logs
journalctl -u nodered -f

# Restart Node-RED if needed
sudo systemctl restart nodered
```

### Logs and Debugging

**Update Script Logs:**
- The update script provides colored output with detailed status
- Backups are automatically created in `/opt/backup/`

**Node-RED Logs:**
```bash
# View Node-RED logs
journalctl -u nodered -f

# Check specific update messages
journalctl -u nodered | grep -i update
```

**Web Server Logs:**
```bash
# Nginx logs
tail -f /var/log/nginx/error.log

# Apache logs  
tail -f /var/log/apache2/error.log
```

## 📝 Development Workflow

### Recommended Development Process

1. **Develop locally** in `warp-cocktail-machine` (this repo)
2. **Test changes** in your local environment
3. **Warp automatically syncs** your changes to `cocktail-machine` GitHub repo
4. **When ready for production:** Go to GitHub Actions and run **"Dev → Prod Deployment"**
5. **GitHub Actions** builds and deploys to `cocktail-deploy` production repo
6. **Pi users** get notified and can update via Node-RED UI

📋 **For detailed deployment workflow, see:** [HOW_TO_DEPLOY.md](HOW_TO_DEPLOY.md) ← **Simple 3-step guide**  
📋 **For advanced deployment docs, see:** [DEPLOYMENT_WORKFLOW.md](DEPLOYMENT_WORKFLOW.md)

### Testing Updates

Before releasing to users, you can test the update system:

1. **Create a test deployment:**
   ```bash
   # Create test branch
   git checkout -b test-update
   
   # Make changes and commit
   git add . && git commit -m "Test update"
   git push origin test-update
   ```

2. **Test manual deployment:**
   - Use GitHub Actions "Run workflow" with your test branch
   - Verify files are deployed correctly

3. **Test on a Pi:**
   ```bash
   # Point to test branch
   export BRANCH="test-update"
   sudo -E /opt/scripts/update_dashboard.sh
   ```

## 🎯 Best Practices

### For Developers

1. **Test before pushing** - Always test locally first
2. **Use semantic commits** - Clear commit messages help with release notes
3. **Tag releases** - Use git tags for major versions
4. **Update documentation** - Keep deployment docs current

### For Pi Users

1. **Backup before updating** - Updates create automatic backups, but manual ones are good too
2. **Check version first** - Use the Node-RED dashboard to see current/available versions
3. **Update during low usage** - Updates restart web services briefly
4. **Keep Node-RED updated** - Occasionally update Node-RED itself with `update-nodejs-and-nodered`

## 🚀 Advanced Features

### Rollback System

If an update causes issues, you can rollback:

```bash
# List available backups
ls -la /opt/backup/

# Restore from backup (replace timestamp)
sudo cp -r /opt/backup/dashboard_backup_v2.1.0_20241215_103000/webroot/* /opt/webroot/
sudo systemctl restart nginx
```

### Multiple Environment Support

You can maintain separate deployment environments:

```bash
# Production updates (default)
export DEPLOY_REPO="sebastienlepoder/cocktail-deploy"
export BRANCH="main"

# Development updates
export DEPLOY_REPO="sebastienlepoder/cocktail-deploy-dev"  
export BRANCH="development"

# Run update with custom environment
sudo -E /opt/scripts/update_dashboard.sh
```

### Private Repository Support

For private repositories, set up authentication:

```bash
# Create GitHub personal access token
# Set environment variable
export RAW_GITHUB_TOKEN="ghp_xxxxxxxxxxxx"

# Updates will now work with private repos
sudo -E /opt/scripts/update_dashboard.sh
```

---

## 🎉 Quick Start Summary

**For You (Developer):**
1. ✅ `cocktail-deploy` repository already set up
2. ✅ `DEPLOY_TOKEN` secret already configured  
3. **Develop locally** in `warp-cocktail-machine` (syncs to GitHub automatically)
4. **When ready for production:** Go to GitHub Actions → **"🚀 Dev → Prod Deployment"** → Run workflow
5. **Pi users get notified** automatically!

**For Pi Users:**
1. Open Node-RED dashboard at `http://pi-ip:1880/ui`
2. Go to Updates tab (updates appear within 10 minutes)
3. Click "Install Update"
4. Enjoy the latest features!

**🚀 Your deployment workflow is now:**  
**Local Dev** → **Warp Sync** → **Manual Deploy** → **Pi Users Notified** → **One-Click Updates**

The system is designed for **controlled, manual deployments** while providing **automatic updates** for Pi users!

# Cocktail Machine Deployment Guide

This guide provides step-by-step instructions for deploying the Cocktail Machine system on a new Raspberry Pi 5.

## System Overview

The Cocktail Machine consists of:
- **Multiple ESP32 bottle modules** controlling pumps and sensors
- **Raspberry Pi 5** running the main control system
- **Docker containers** for all services (MQTT, Node-RED, Web Dashboard, Database)
- **Automatic update system** for remote maintenance

## Prerequisites

### Hardware Requirements
- Raspberry Pi 5 (4GB+ RAM recommended)
- MicroSD card (32GB+ recommended)
- 5" HDMI display for user interface
- Ethernet or WiFi connection
- Power supply for Raspberry Pi and pumps

### Software Requirements  
- **Raspberry Pi OS (64-bit) Lite** - RECOMMENDED for kiosk mode
- **Raspberry Pi OS (64-bit) Desktop** - Alternative if you need full desktop
- Internet connection for initial setup

> 💡 **Recommendation**: Use **Raspberry Pi OS Lite (64-bit)** for best kiosk performance. The setup script will install only the minimal desktop components needed.

## Quick Start Deployment

### 1. Prepare the Raspberry Pi

1. **Flash Raspberry Pi OS** to the SD card using Raspberry Pi Imager
2. **Enable SSH** during setup (optional but recommended)
3. **Connect to network** (Ethernet or WiFi)
4. **Boot the Raspberry Pi** and log in

### 2. Run Automated Setup

Connect to your Raspberry Pi via SSH or directly, then run the **Production Setup Script**:

```bash
# Download and run the production setup script (one-line install)
curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/scripts/setup-ultimate.sh | bash
```

**This setup script provides:**
- ✅ **Your React dashboard** downloaded directly from production
- ✅ **Proper Docker configuration** with nginx serving your dashboard
- ✅ **Kiosk mode** with loading screen and auto-start
- ✅ **Update system** with production scripts
- ✅ **Health checking** and service monitoring
- ✅ **Auto-login** and quiet boot configuration
- ✅ **Professional presentation** mode

This script will:
- Install Docker and Docker Compose
- Install minimal X11 desktop environment (OpenBox + LightDM)
- Clone the repository and set up directories
- Create configuration files with health check endpoints
- **Configure kiosk mode with professional loading screen**
- **Set up auto-login and quiet boot**
- **Create robust service health checking**
- Configure auto-start services and backups

### 3. Configure Environment

Edit the environment file with your Supabase credentials:

```bash
nano /home/pi/cocktail-machine/deployment/.env
```

Update these values:
```env
SUPABASE_URL=your_actual_supabase_url
SUPABASE_ANON_KEY=your_actual_anon_key
```

### 4. Reboot to Kiosk Mode

After configuration, reboot to start kiosk mode:

```bash
sudo reboot
```

**What happens after reboot:**
1. 🔇 **Silent boot** (no boot messages)
2. 🖥️ **Auto-login** to desktop
3. 🍹 **Loading screen** appears immediately  
4. ⏳ **Service health check** runs in background
5. 📱 **Dashboard** appears when services are ready

> The services start automatically via systemd. No manual intervention needed!

### 5. Configure ESP32 Modules

For each bottle module:

1. **Update WiFi credentials** in ESP32 firmware
2. **Set MQTT broker IP** to Raspberry Pi's address
3. **Assign unique module ID** (vodka, rum, gin, etc.)
4. **Flash firmware** to ESP32-S3

## Manual Deployment Steps

If you prefer manual installation:

### Step 1: Install Docker

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo apt-get install -y docker-compose
```

### Step 2: Clone Repository

```bash
git clone https://github.com/sebastienlepoder/cocktail-machine.git
cd cocktail-machine
```

### Step 3: Create Environment File

```bash
cd deployment
cat > .env << EOF
DB_PASSWORD=$(openssl rand -base64 32)
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_key
MQTT_HOST=localhost
MQTT_PORT=1883
EOF
```

### Step 4: Start Services

```bash
docker-compose up -d
```

## Service Access

Once deployed, access services at:

- **Web Dashboard**: `http://<raspberry-pi-ip>` (port 80)
- **Kiosk Display**: Automatically shown on connected screen
- **Node-RED Admin**: `http://<raspberry-pi-ip>/admin`
- **MQTT Broker**: `<raspberry-pi-ip>:1883`
- **PostgreSQL**: `<raspberry-pi-ip>:5432`
- **Health Check**: `http://<raspberry-pi-ip>/health`

> 💡 The kiosk will automatically display the dashboard on the connected screen. For remote access, use the IP addresses above.

## ESP32 Module Setup

### Firmware Configuration

Each ESP32 module needs:

```cpp
// config.h
#define WIFI_SSID "your-wifi-ssid"
#define WIFI_PASSWORD "your-wifi-password"
#define MQTT_SERVER "192.168.1.100"  // Raspberry Pi IP
#define MODULE_ID "vodka"  // Unique for each module
```

### Flashing Firmware

Using PlatformIO:
```bash
cd esp32
pio run -t upload --upload-port COM3
```

Using Arduino IDE:
1. Open `esp32/cocktail_module.ino`
2. Select Board: ESP32-S3 Dev Module
3. Upload to module

## Maintenance

### Viewing Logs

```bash
cd /home/pi/cocktail-machine/deployment
docker-compose logs -f  # All services
docker-compose logs -f mosquitto  # Specific service
```

### Manual Update

```bash
/home/pi/cocktail-machine/update.sh
```

### Backup

Automatic backups run daily at 2 AM. Manual backup:

```bash
/home/pi/cocktail-machine/backup.sh
```

### Restore from Backup

```bash
cd /home/pi/cocktail-machine
tar -xzf /home/pi/cocktail-backups/cocktail_backup_TIMESTAMP.tar.gz
cd deployment
docker-compose down
docker-compose up -d
```

## Kiosk Mode Troubleshooting

### Loading Screen Stuck

If the loading screen never transitions to the dashboard:

```bash
# SSH into the Pi and check logs
ssh pi@<raspberry-pi-ip>

# View kiosk logs
cat /tmp/kiosk-launcher.log
cat /tmp/kiosk-service-check.log

# Check if services are running
cd /home/pi/cocktail-machine/deployment
docker-compose ps

# Manually test service health
curl http://localhost/health
```

### Manual Kiosk Restart

```bash
# Kill browser and restart kiosk
pkill -f chromium
DISPLAY=:0 /home/pi/.cocktail-machine/kiosk-launcher.sh
```

### Boot Messages Still Showing

If you still see boot messages:

```bash
# Check if quiet boot is configured
cat /boot/cmdline.txt
# Should contain: quiet splash plymouth.ignore-serial-consoles logo.nologo

# If missing, run:
sudo nano /boot/cmdline.txt
# Add the quiet parameters manually
```

### Desktop Not Starting

```bash
# Check if graphical target is enabled
sudo systemctl get-default
# Should show: graphical.target

# Check LightDM status
sudo systemctl status lightdm

# Check auto-login configuration
cat /etc/lightdm/lightdm.conf.d/01-autologin.conf
```

## General Troubleshooting

### Services Not Starting

Check Docker status:
```bash
sudo systemctl status docker
docker ps -a
```

Restart services:
```bash
cd /home/pi/cocktail-machine/deployment
docker-compose down
docker-compose up -d
```

### MQTT Connection Issues

Test MQTT broker:
```bash
# Install mosquitto clients
sudo apt-get install -y mosquitto-clients

# Test subscribe
mosquitto_sub -h localhost -t "#" -v

# Test publish
mosquitto_pub -h localhost -t "test" -m "hello"
```

### ESP32 Not Connecting

1. Check WiFi credentials
2. Verify MQTT broker IP
3. Check firewall settings:
   ```bash
   sudo ufw status
   sudo ufw allow 1883/tcp
   ```

### Database Issues

Reset database:
```bash
cd deployment
docker-compose down postgres
docker volume rm deployment_postgres-data
docker-compose up -d postgres
```

## Production Deployment

### Security Hardening

1. **Change default passwords** in `.env`
2. **Enable MQTT authentication**:
   Edit `mosquitto/config/mosquitto.conf`:
   ```conf
   allow_anonymous false
   password_file /mosquitto/config/passwords
   ```

3. **Set up SSL/TLS** for web services
4. **Configure firewall** rules
5. **Enable automatic security updates**:
   ```bash
   sudo apt-get install -y unattended-upgrades
   sudo dpkg-reconfigure unattended-upgrades
   ```

### Performance Optimization

1. **Increase swap** for low-memory situations:
   ```bash
   sudo dphys-swapfile swapoff
   sudo nano /etc/dphys-swapfile  # Set CONF_SWAPSIZE=2048
   sudo dphys-swapfile setup
   sudo dphys-swapfile swapon
   ```

2. **Optimize Docker**:
   ```bash
   sudo nano /etc/docker/daemon.json
   ```
   Add:
   ```json
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "10m",
       "max-file": "3"
     }
   }
   ```

### Remote Management

For remote access:

1. **Set up VPN** (recommended) or
2. **Configure port forwarding** with dynamic DNS
3. **Use SSH tunneling** for secure access:
   ```bash
   ssh -L 3000:localhost:3000 pi@raspberry-pi-ip
   ```

## Support

For issues or questions:
1. Check logs: `docker-compose logs`
2. Review this documentation
3. Open an issue on GitHub
4. Contact support

## Version Information

- **System Version**: 1.0.0
- **ESP32 Firmware**: 1.0.0
- **Last Updated**: 2024

---

© 2024 Cocktail Machine Project
