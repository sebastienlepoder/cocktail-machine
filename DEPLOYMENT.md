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

Connect to your Raspberry Pi via SSH or directly, then run the **Ultimate Setup Script**:

```bash
# Download and run the ultimate kiosk setup script
curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-machine/main/deployment/setup-ultimate.sh -o setup-ultimate.sh
chmod +x setup-ultimate.sh
./setup-ultimate.sh
```

> ⚠️ **Important**: Use `setup-ultimate.sh` instead of the basic setup script. This provides:
> - Proper kiosk mode with loading screen
> - Robust service health checking  
> - Auto-login to desktop
> - Quiet boot configuration
> - Professional presentation mode

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
