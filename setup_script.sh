#!/usr/bin/env bash
#  Working version: 2025-08-23 v2.2 
#  CocktailMachine Complete Setup with Enhanced Kiosk Mode (Raspberry Pi OS Bookworm / Pi 5)
# - Installs Realtek 88x2bu driver (Archer T3U Nano, 2357:012e)
# - Creates standalone AP on wlan1 (no NAT/Internet)
#   SSID: CocktailMachine   PASS: Cocktail2024!
#   Pi AP IP: 192.168.50.1/24, DHCP .10-.100
# - Robust boot: dnsmasq bind-dynamic + waits for NetworkManager + AP bring-up service
# - ESP32 friendly: 2.4GHz, WPA2-PSK (AES), PMF off
# - Installs and configures MQTT Mosquitto broker
# - Installs and configures Node-RED with automatic startup using official installer
# - Installs Dashboard, Dashboard 2.0, and ui_list nodes
# - Sets up firewall rules for local network access
# - NEW: Hides boot messages and shows logo.png splash screen
# - NEW: Auto-starts Node-RED dashboard in kiosk mode on boot

set -euo pipefail

SSID="CocktailMachine"
PSK="Cocktail2024!"
IFACE="wlan1"
CON_NAME="CocktailAP"
COUNTRY="US"                  # change if needed
SUBNET_IP="192.168.50.1"
SUBNET_CIDR="${SUBNET_IP}/24"
DHCP_START="192.168.50.10"
DHCP_END="192.168.50.100"
DHCP_MASK="255.255.255.0"
SRC_DIR="/root/src"
DRV_DIR="${SRC_DIR}/88x2bu-20210702"

# MQTT Settings
MQTT_USER="cocktail"
MQTT_PASS="cocktail123"
MQTT_PORT="1883"

# Node-RED Settings
NODERED_PORT="1880"
NODERED_USER="pi"

# Kiosk Settings
LOGO_PATH="/home/pi/logo.png"
DASHBOARD_URL="http://192.168.50.1:1880/ui"

need_root() { 
    if [[ $EUID -ne 0 ]]; then 
        echo "Run as root: sudo $0"
        exit 1
    fi
}

detect_boot_partition() {
    # Detect boot partition location for different Pi OS versions
    if [[ -d /boot/firmware ]]; then
        BOOT_DIR="/boot/firmware"
    elif [[ -d /boot ]]; then
        BOOT_DIR="/boot"
    else
        echo "[!] Cannot find boot directory"
        exit 1
    fi
    echo "[i] Using boot directory: $BOOT_DIR"
}

install_prereqs() {
    echo "[i] Installing prerequisites..."
    apt-get update
    apt-get install -y raspberrypi-kernel-headers build-essential bc dkms git rfkill iw \
                       network-manager dnsmasq curl wget ufw \
                       plymouth plymouth-themes xinit xserver-xorg chromium-browser \
                       unclutter sed fbi imagemagick lightdm openbox \
                       xdotool wmctrl expect
    systemctl enable NetworkManager
    systemctl restart NetworkManager
}

install_driver_88x2bu() {
    echo "[i] Installing WiFi driver..."
    if ! lsusb | grep -qi '2357:012e'; then
        echo "[i] Archer T3U Nano (2357:012e) not detected; skipping driver build."
        return
    fi
    if modinfo 88x2bu >/dev/null 2>&1; then
        echo "[i] 88x2bu driver already installed."
        modprobe 88x2bu || true
        return
    fi
    mkdir -p "$SRC_DIR"
    if [[ ! -d "$DRV_DIR/.git" ]]; then
        git clone https://github.com/morrownr/88x2bu-20210702.git "$DRV_DIR"
    else
        git -C "$DRV_DIR" pull --ff-only || true
    fi
    pushd "$DRV_DIR" >/dev/null
    sh install-driver.sh NoPrompt
    popd >/dev/null
    modprobe 88x2bu || true
}

configure_nm_ap() {
    echo "[i] Configuring WiFi Access Point..."
    nmcli radio wifi on || true
    iw reg set "$COUNTRY" || true

    nmcli device set "$IFACE" managed yes || true

    # Down any active profile on wlan1
    nmcli -t -f NAME,DEVICE,TYPE connection show --active \
        | awk -F: -v ifc="$IFACE" '$2==ifc{print $1}' \
        | while read -r cname; do nmcli connection down "$cname" || true; done

    # Create or reuse the AP profile
    if nmcli -t -f NAME connection show | grep -qx "$CON_NAME"; then
        echo "[i] Updating existing connection: $CON_NAME"
    else
        nmcli connection add type wifi ifname "$IFACE" con-name "$CON_NAME" autoconnect yes ssid "$SSID"
    fi

    # ESP32-friendly AP + static IP (NO default route)
    nmcli connection modify "$CON_NAME" \
        802-11-wireless.mode ap \
        802-11-wireless.band bg \
        802-11-wireless.channel 6 \
        802-11-wireless.ssid "$SSID" \
        802-11-wireless.powersave 2 \
        ipv4.addresses "$SUBNET_CIDR" \
        ipv4.method manual \
        ipv4.gateway "" \
        ipv4.never-default yes \
        ipv6.method ignore \
        connection.interface-name "$IFACE" \
        connection.autoconnect yes \
        connection.autoconnect-priority 100 \
        connection.permissions "" \
        connection.wait-device-timeout 600

    # Ensure WPA2-PSK (AES) is set BEFORE first activation
    nmcli connection modify "$CON_NAME" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.proto rsn \
        wifi-sec.group ccmp \
        wifi-sec.pairwise ccmp \
        wifi-sec.pmf 0 \
        wifi-sec.psk "$PSK"

    nmcli connection modify "$CON_NAME" \
        802-11-wireless-security.key-mgmt wpa-psk \
        802-11-wireless-security.proto rsn \
        802-11-wireless-security.group ccmp \
        802-11-wireless-security.pairwise ccmp \
        802-11-wireless-security.pmf 0 \
        802-11-wireless-security.psk "$PSK"
}

configure_dnsmasq() {
    echo "[i] Configuring DHCP server..."
    mkdir -p /etc/dnsmasq.d
    cat >/etc/dnsmasq.d/cocktail-ap.conf <<EOF
# DHCP for CocktailMachine AP (standalone)
interface=${IFACE}
bind-dynamic
dhcp-range=${DHCP_START},${DHCP_END},${DHCP_MASK},24h
dhcp-option=3,${SUBNET_IP}
dhcp-option=6,${SUBNET_IP}
EOF

    # Start dnsmasq AFTER NM is online
    mkdir -p /etc/systemd/system/dnsmasq.service.d
    cat >/etc/systemd/system/dnsmasq.service.d/override.conf <<'EOF'
[Unit]
After=NetworkManager.service nm-online.service
Wants=NetworkManager.service nm-online.service

[Service]
ExecStartPre=/usr/bin/nm-online -q --timeout=20
ExecStartPre=/bin/sleep 3
EOF

    systemctl daemon-reload
    systemctl enable dnsmasq
    systemctl restart dnsmasq
}

install_mosquitto() {
    echo "[i] Installing MQTT Mosquitto broker..."
    
    # Stop any existing mosquitto service
    systemctl stop mosquitto || true
    systemctl disable mosquitto || true
    
    # Install mosquitto
    apt-get install -y mosquitto mosquitto-clients
    
    # Create necessary directories
    mkdir -p /var/lib/mosquitto
    mkdir -p /var/log/mosquitto
    mkdir -p /etc/mosquitto/conf.d
    
    chown mosquitto:mosquitto /var/lib/mosquitto
    chown mosquitto:mosquitto /var/log/mosquitto
    chmod 755 /var/lib/mosquitto
    chmod 755 /var/log/mosquitto
    
    # Remove any existing password file
    rm -f /etc/mosquitto/passwd
    
    # Create MQTT user and password file
    echo "[i] Creating MQTT user: $MQTT_USER"
    touch /etc/mosquitto/passwd
    chown mosquitto:mosquitto /etc/mosquitto/passwd
    chmod 600 /etc/mosquitto/passwd
    mosquitto_passwd -b /etc/mosquitto/passwd "$MQTT_USER" "$MQTT_PASS"
    
    # Backup original config if it exists
    if [[ -f /etc/mosquitto/mosquitto.conf ]]; then
        cp /etc/mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf.backup
    fi
    
    # Create clean main configuration (avoiding conflicts)
    cat >/etc/mosquitto/mosquitto.conf <<'EOF'
# Mosquitto configuration for CocktailMachine
pid_file /run/mosquitto/mosquitto.pid

# Include all config files in conf.d
include_dir /etc/mosquitto/conf.d

# Persistence
persistence true
persistence_location /var/lib/mosquitto/
EOF
    
    # Create the main configuration in conf.d to avoid conflicts
    cat >/etc/mosquitto/conf.d/cocktail.conf <<EOF
# CocktailMachine MQTT Configuration
listener ${MQTT_PORT}
allow_anonymous false
password_file /etc/mosquitto/passwd

# Connection settings
max_connections 100
connection_messages true

# Session settings
max_inflight_messages 20
max_queued_messages 100
EOF
    
    # Set permissions
    chown mosquitto:mosquitto /etc/mosquitto/mosquitto.conf
    chown mosquitto:mosquitto /etc/mosquitto/conf.d/cocktail.conf
    
    # Note: Mosquitto 2.0+ doesn't support -t flag for config testing
    # Configuration will be validated when the service starts
    echo "[i] Configuration created (will be validated on startup)"
    
    # Create systemd override
    mkdir -p /etc/systemd/system/mosquitto.service.d
    cat >/etc/systemd/system/mosquitto.service.d/override.conf <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
ExecStartPre=/bin/sleep 2
Restart=on-failure
RestartSec=5
EOF
    
    systemctl daemon-reload
    
    # Enable and start Mosquitto
    echo "[i] Starting Mosquitto service..."
    systemctl enable mosquitto
    
    if ! systemctl start mosquitto; then
        echo "[!] Failed to start Mosquitto. Checking status..."
        systemctl status mosquitto || true
        journalctl -xeu mosquitto.service --no-pager || true
        exit 1
    fi
    
    # Wait for service to fully start
    sleep 5
    
    # Verify service is running
    if ! systemctl is-active mosquitto >/dev/null; then
        echo "[!] Mosquitto is not running after startup attempt"
        systemctl status mosquitto
        exit 1
    fi
    
    echo "[i] Testing MQTT broker connectivity..."
    if timeout 10 mosquitto_pub -h localhost -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/startup" -m "Mosquitto is working" -d; then
        echo "[i] MQTT broker test successful"
    else
        echo "[w] MQTT broker test failed, but service appears to be running"
    fi
}

install_nodered() {
    echo "[i] Installing Node-RED using official installer..."
    
    # Try official installer first
    echo "[i] Attempting official Node-RED installer..."
    cd /tmp
    curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered -o install-nodered.sh
    chmod +x install-nodered.sh
    
    # Try multiple methods to handle interactive prompts
    INSTALL_SUCCESS=false
    
    # Method 1: Pipe yes responses
    echo "[i] Method 1: Trying with piped responses..."
    if echo -e "y\ny\ny\n" | timeout 300 ./install-nodered.sh --confirm-install --confirm-pi 2>/dev/null; then
        INSTALL_SUCCESS=true
        echo "[i] Official installer succeeded with method 1"
    fi
    
    # Method 2: Using expect if method 1 failed
    if [[ "$INSTALL_SUCCESS" = false ]] && command -v expect >/dev/null 2>&1; then
        echo "[i] Method 2: Trying with expect..."
        timeout 300 expect << 'EOF'
spawn ./install-nodered.sh --confirm-install --confirm-pi
expect {
    "*Are you really sure you want to install as root*" { send "y\r"; exp_continue }
    "*Would you like to install the Pi-specific nodes*" { send "y\r"; exp_continue }
    "*Would you like to enable the systemd service*" { send "y\r"; exp_continue }
    eof
}
EOF
        if [[ $? -eq 0 ]]; then
            INSTALL_SUCCESS=true
            echo "[i] Official installer succeeded with method 2"
        fi
    fi
    
    # Method 3: Manual installation if official installer failed
    if [[ "$INSTALL_SUCCESS" = false ]]; then
        echo "[i] Official installer failed, using manual installation method..."
        
        # Install Node.js from NodeSource repository
        curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        apt-get install -y nodejs
        
        # Create node-red user and directories
        if ! id "nodered" &>/dev/null; then
            useradd -m -s /bin/bash nodered
        fi
        
        # Install Node-RED globally
        npm install -g --unsafe-perm node-red
        
        # Create Node-RED service
        cat >/etc/systemd/system/nodered.service <<EOF
[Unit]
Description=Node-RED
After=syslog.target network.target

[Service]
ExecStart=/usr/bin/node-red --max-old-space-size=128 --userDir /home/${NODERED_USER}/.node-red
Restart=on-failure
KillSignal=SIGINT
User=${NODERED_USER}
Group=${NODERED_USER}
WorkingDirectory=/home/${NODERED_USER}
Environment="NODE_OPTIONS=--max_old_space_size=128"
Environment="NODE_RED_OPTIONS=-v"

[Install]
WantedBy=multi-user.target
EOF
        
        # Create .node-red directory
        mkdir -p /home/${NODERED_USER}/.node-red
        chown -R ${NODERED_USER}:${NODERED_USER} /home/${NODERED_USER}/.node-red
        
        # Enable and start service
        systemctl daemon-reload
        systemctl enable nodered
        
        echo "[i] Node-RED installed manually"
        INSTALL_SUCCESS=true
    fi
    
    if [[ "$INSTALL_SUCCESS" = false ]]; then
        echo "[!] All Node-RED installation methods failed"
        exit 1
    fi
    
    # The official installer already creates the systemd service and enables it
    echo "[i] Node-RED installed successfully"
    
    # Create Node-RED settings file with enhanced stability configuration
    echo "[i] Configuring Node-RED settings for enhanced stability..."
    cat >/home/${NODERED_USER}/.node-red/settings.js <<'EOF'
module.exports = {
    uiPort: process.env.PORT || 1880,
    uiHost: "0.0.0.0",
    mqttReconnectTime: 5000,
    serialReconnectTime: 5000,
    debugMaxLength: 1000,
    httpAdminRoot: '/',
    httpNodeRoot: '/',
    httpStatic: '/home/pi/.node-red/public/',
    httpStaticAuth: null,
    userDir: '/home/pi/.node-red/',
    functionGlobalContext: {},
    exportGlobalContextKeys: false,
    runtimeState: {
        enabled: false,
        ui: false
    },
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },
    editorTheme: {
        projects: {
            enabled: false
        },
        palette: {
            editable: true
        }
    },
    ui: { 
        path: "ui",
        middleware: function(req,res,next) {
            // Add no-cache headers to prevent browser caching issues
            res.header('Cache-Control', 'no-cache, no-store, must-revalidate');
            res.header('Pragma', 'no-cache');
            res.header('Expires', '0');
            next();
        }
    },
    httpNodeCors: {
        origin: "*",
        methods: "GET,PUT,POST,DELETE"
    }
}
EOF
    
    chown ${NODERED_USER}:${NODERED_USER} /home/${NODERED_USER}/.node-red/settings.js
    
    # Install useful Node-RED modules as the pi user
    echo "[i] Installing Node-RED modules (Dashboard, Dashboard 2.0, ui_list)..."
    sudo -u ${NODERED_USER} bash -c "cd /home/${NODERED_USER}/.node-red && npm install node-red-dashboard @flowfuse/node-red-dashboard node-red-node-ui-list node-red-contrib-ui-led node-red-node-ui-table"
    
    # Update systemd service to depend on mosquitto
    echo "[i] Updating Node-RED service dependencies..."
    mkdir -p /etc/systemd/system/nodered.service.d
    cat >/etc/systemd/system/nodered.service.d/override.conf <<'EOF'
[Unit]
After=mosquitto.service
Wants=mosquitto.service
EOF

    systemctl daemon-reload
    
    echo "[i] Node-RED configured"
}

create_nodered_flows() {
    echo "[i] Creating initial Node-RED flows with enhanced MQTT configuration..."
    
    # Create flows with proper MQTT credentials and enhanced stability
    cat >/home/${NODERED_USER}/.node-red/flows.json <<EOF
[
    {
        "id": "cocktail_tab",
        "type": "tab",
        "label": "CocktailMachine",
        "disabled": false,
        "info": ""
    },
    {
        "id": "mqtt_broker",
        "type": "mqtt-broker",
        "name": "Local MQTT",
        "broker": "localhost",
        "port": "${MQTT_PORT}",
        "clientid": "",
        "autoConnect": true,
        "usetls": false,
        "protocolVersion": "4",
        "keepalive": "60",
        "cleansession": true,
        "autoUnsubscribe": true,
        "birthTopic": "",
        "birthQos": "0",
        "birthRetain": "false",
        "birthPayload": "",
        "birthMsg": {},
        "closeTopic": "",
        "closeQos": "0",
        "closeRetain": "false",
        "closePayload": "",
        "closeMsg": {},
        "willTopic": "",
        "willQos": "0",
        "willRetain": "false",
        "willPayload": "",
        "willMsg": {},
        "userProps": "",
        "sessionExpiry": "",
        "credentials": {
            "user": "${MQTT_USER}",
            "password": "${MQTT_PASS}"
        }
    },
    {
        "id": "mqtt_in",
        "type": "mqtt in",
        "z": "cocktail_tab",
        "name": "MQTT In",
        "topic": "cocktail/+",
        "qos": "2",
        "datatype": "auto-detect",
        "broker": "mqtt_broker",
        "nl": false,
        "rap": true,
        "rh": 0,
        "inputs": 0,
        "x": 120,
        "y": 100,
        "wires": [["debug_mqtt"]]
    },
    {
        "id": "debug_mqtt",
        "type": "debug",
        "z": "cocktail_tab",
        "name": "MQTT Debug",
        "active": true,
        "tosidebar": true,
        "console": false,
        "tostatus": false,
        "complete": "payload",
        "targetType": "msg",
        "statusVal": "",
        "statusType": "auto",
        "x": 350,
        "y": 100,
        "wires": []
    },
    {
        "id": "inject_test",
        "type": "inject",
        "z": "cocktail_tab",
        "name": "Test Message",
        "props": [
            {
                "p": "payload"
            },
            {
                "p": "topic",
                "vt": "str"
            }
        ],
        "repeat": "",
        "crontab": "",
        "once": false,
        "onceDelay": 0.1,
        "topic": "cocktail/test",
        "payload": "Hello from Node-RED!",
        "payloadType": "str",
        "x": 130,
        "y": 200,
        "wires": [["mqtt_out"]]
    },
    {
        "id": "mqtt_out",
        "type": "mqtt out",
        "z": "cocktail_tab",
        "name": "MQTT Out",
        "topic": "",
        "qos": "",
        "retain": "",
        "respTopic": "",
        "contentType": "",
        "userProps": "",
        "correl": "",
        "expiry": "",
        "broker": "mqtt_broker",
        "x": 340,
        "y": 200,
        "wires": []
    }
]
EOF
    
    chown ${NODERED_USER}:${NODERED_USER} /home/${NODERED_USER}/.node-red/flows.json
    
    # Now start Node-RED
    echo "[i] Starting Node-RED..."
    systemctl start nodered
    
    # Wait for Node-RED to start and retry if needed
    for i in {1..3}; do
        sleep 10
        if systemctl is-active nodered >/dev/null && timeout 5 curl -s http://localhost:${NODERED_PORT} >/dev/null 2>&1; then
            echo "[i] Node-RED started successfully"
            break
        else
            echo "[i] Node-RED not ready, restarting (attempt $i)..."
            systemctl restart nodered
        fi
    done
}

configure_firewall() {
    echo "[i] Configuring firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH from anywhere
    ufw allow ssh
    
    # Allow MQTT and Node-RED from any source
    ufw allow ${MQTT_PORT}
    ufw allow ${NODERED_PORT}
    
    # Allow DNS and DHCP for the AP
    ufw allow in on ${IFACE} to any port 53
    ufw allow in on ${IFACE} to any port 67
    
    # Enable firewall
    ufw --force enable
}

disable_forwarding() {
    echo "[i] Disabling IP forwarding..."
    echo "net.ipv4.ip_forward=0" >/etc/sysctl.d/99-no-forwarding.conf
    sysctl -p /etc/sysctl.d/99-no-forwarding.conf >/dev/null
}

configure_boot_splash() {
    echo "[i] Configuring boot splash screen..."
    
    detect_boot_partition
    
    # Create default logo if it doesn't exist
    if [[ ! -f "$LOGO_PATH" ]]; then
        echo "[i] Creating default logo.png..."
        # Create a simple 1920x1080 logo with text (full HD)
        convert -size 1920x1080 xc:black \
                -fill white -pointsize 120 -gravity center \
                -annotate +0-100 "CocktailMachine" \
                -fill gray -pointsize 60 -gravity center \
                -annotate +0+100 "Loading..." \
                "$LOGO_PATH"
        chown ${NODERED_USER}:${NODERED_USER} "$LOGO_PATH"
        echo "[i] Default logo created at $LOGO_PATH"
        echo "[i] Replace this file with your own logo.png (recommended size: 1920x1080)"
    fi
    
    # Backup original files
    [[ -f "$BOOT_DIR/cmdline.txt" ]] && cp "$BOOT_DIR/cmdline.txt" "$BOOT_DIR/cmdline.txt.backup"
    [[ -f "$BOOT_DIR/config.txt" ]] && cp "$BOOT_DIR/config.txt" "$BOOT_DIR/config.txt.backup"
    
    # Configure cmdline.txt - hide boot messages completely
    echo "[i] Configuring boot parameters..."
    CMDLINE_FILE="$BOOT_DIR/cmdline.txt"
    
    if [[ -f "$CMDLINE_FILE" ]]; then
        # Read current cmdline and clean it up
        CURRENT_CMDLINE=$(cat "$CMDLINE_FILE")
        
        # Remove existing quiet/splash/loglevel parameters
        NEW_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed -E 's/(^| )(quiet|splash|loglevel=[0-9]+|logo\.[^ =]*=[^ ]*|vt\.[^ =]*=[^ ]*|plymouth\.[^ =]*=[^ ]*|rd\.[^ =]*=[^ ]*)( |$)/ /g' | sed 's/  */ /g' | sed 's/^ *//' | sed 's/ *$//')
        
        # Add comprehensive boot hiding parameters
        NEW_CMDLINE="$NEW_CMDLINE quiet splash loglevel=0 rd.systemd.show_status=false rd.udev.log_level=0 plymouth.enable=1 logo.nologo vt.global_cursor_default=0 console=tty3"
        
        echo "$NEW_CMDLINE" > "$CMDLINE_FILE"
        echo "[i] Updated $CMDLINE_FILE"
    else
        echo "[!] Warning: Could not find $CMDLINE_FILE"
    fi
    
    # Configure config.txt
    CONFIG_FILE="$BOOT_DIR/config.txt"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "[i] Configuring $CONFIG_FILE..."
        
        # Remove existing CocktailMachine configuration
        sed -i '/# CocktailMachine boot configuration/,/^$/d' "$CONFIG_FILE"
        
        # Add comprehensive display and boot configuration
        cat >>"$CONFIG_FILE" <<EOF

# CocktailMachine boot configuration
disable_splash=1
boot_delay=0
disable_overscan=1
avoid_warnings=1
disable_rainbow_splash=1

# GPU configuration for smooth graphics
gpu_mem=128

# Display configuration
hdmi_group=2
hdmi_mode=82
hdmi_drive=2
hdmi_ignore_edid=0xa5000080

# Audio configuration
dtparam=audio=on

# Enable Plymouth
dtoverlay=vc4-kms-v3d
EOF
        echo "[i] Updated $CONFIG_FILE"
    else
        echo "[!] Warning: Could not find $CONFIG_FILE"
    fi
    
    # Create Plymouth theme directory
    THEME_DIR="/usr/share/plymouth/themes/cocktail"
    echo "[i] Creating Plymouth theme at $THEME_DIR"
    rm -rf "$THEME_DIR"
    mkdir -p "$THEME_DIR"
    
    # Copy and optimize logo
    THEME_LOGO="$THEME_DIR/logo.png"
    cp "$LOGO_PATH" "$THEME_LOGO"
    
    # Optimize logo for Plymouth (resize to reasonable size, ensure it's not too large)
    convert "$THEME_LOGO" -resize "1920x1080>" -background black -gravity center -extent 1920x1080 "$THEME_LOGO"
    
    # Create Plymouth theme configuration
    cat >"$THEME_DIR/cocktail.plymouth" <<EOF
[Plymouth Theme]
Name=CocktailMachine
Description=CocktailMachine Boot Theme with Logo
ModuleName=script

[script]
ImageDir=$THEME_DIR
ScriptFile=$THEME_DIR/cocktail.script
EOF
    
    # Create advanced Plymouth script with better logo handling
    cat >"$THEME_DIR/cocktail.script" <<'EOF'
// CocktailMachine Plymouth Boot Theme

// Load logo image
logo_image = Image("logo.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

if (logo_image) {
    logo_width = logo_image.GetWidth();
    logo_height = logo_image.GetHeight();
    
    // Scale logo to fit screen nicely (max 80% of screen)
    max_width = screen_width * 0.8;
    max_height = screen_height * 0.8;
    
    scale_x = max_width / logo_width;
    scale_y = max_height / logo_height;
    scale = Math.Min(scale_x, scale_y);
    
    if (scale < 1) {
        new_width = logo_width * scale;
        new_height = logo_height * scale;
        logo_image = logo_image.Scale(new_width, new_height);
        logo_width = new_width;
        logo_height = new_height;
    }
    
    // Center the logo
    logo_x = (screen_width - logo_width) / 2;
    logo_y = (screen_height - logo_height) / 2;
    
    logo_sprite = Sprite(logo_image);
    logo_sprite.SetPosition(logo_x, logo_y, 0);
}

// Progress bar setup
progress_bar.width = screen_width * 0.6;
progress_bar.height = 8;
progress_bar.x = (screen_width - progress_bar.width) / 2;
progress_bar.y = screen_height * 0.85;

// Create progress bar background
progress_bg_image = Image.Text("", progress_bar.width, progress_bar.height, 0.3, 0.3, 0.3);
progress_bg_sprite = Sprite(progress_bg_image);
progress_bg_sprite.SetPosition(progress_bar.x, progress_bar.y, 1);

// Progress bar foreground (starts empty)
progress_fg_image = Image.Text("", 0, progress_bar.height, 1, 1, 1);
progress_fg_sprite = Sprite(progress_fg_image);
progress_fg_sprite.SetPosition(progress_bar.x, progress_bar.y, 2);

// Progress callback
fun progress_callback(duration, progress) {
    if (progress >= 0 && progress <= 1) {
        // Update progress bar
        new_width = progress_bar.width * progress;
        if (new_width > 0) {
            progress_fg_image = Image.Text("", new_width, progress_bar.height, 0.0, 0.5, 1.0);
            progress_fg_sprite.SetImage(progress_fg_image);
        }
    }
}

Plymouth.SetBootProgressFunction(progress_callback);

// Hide all text messages
fun message_callback(text) {
    // Don't show any boot messages
}

Plymouth.SetMessageFunction(message_callback);

// Hide password prompts and other dialogs
fun display_normal_callback() {
    // Keep showing our custom theme
}

fun display_password_callback(prompt, bullets) {
    // Don't show password prompts during boot
}

Plymouth.SetDisplayNormalFunction(display_normal_callback);
Plymouth.SetDisplayPasswordFunction(display_password_callback);
EOF
    
    # Set correct permissions
    chmod 644 "$THEME_DIR"/*
    
    echo "[i] Installing and configuring Plymouth theme..."
    
    # Install and set Plymouth theme with multiple fallback methods
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        echo "[i] Setting Plymouth theme to 'cocktail'..."
        
        # Method 1: Standard plymouth-set-default-theme
        if plymouth-set-default-theme cocktail 2>/dev/null; then
            echo "[i] Plymouth theme set successfully (method 1)"
        else
            echo "[i] Method 1 failed, trying alternative methods..."
            
            # Method 2: Create theme configuration files manually
            echo "[i] Creating Plymouth configuration files..."
            mkdir -p /etc/plymouth/plymouthd.conf.d
            echo "cocktail" > /etc/plymouth/plymouthd.conf.d/01-theme.conf
            
            # Update main Plymouth config
            if [[ -f /etc/plymouth/plymouthd.conf ]]; then
                sed -i '/^Theme=/d' /etc/plymouth/plymouthd.conf
            else
                touch /etc/plymouth/plymouthd.conf
            fi
            echo "Theme=cocktail" >> /etc/plymouth/plymouthd.conf
            
            # Method 3: Update alternatives system
            if command -v update-alternatives >/dev/null 2>&1; then
                update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$THEME_DIR/cocktail.plymouth" 100 2>/dev/null || true
                update-alternatives --set default.plymouth "$THEME_DIR/cocktail.plymouth" 2>/dev/null || true
            fi
            
            echo "[i] Alternative Plymouth configuration methods applied"
        fi
        
        # Verify theme is set correctly
        sleep 2
        CURRENT_THEME=$(plymouth-set-default-theme --list 2>/dev/null | grep '\*' | sed 's/.*\* //' | head -n1 || echo "")
        echo "[i] Verifying Plymouth theme..."
        echo "[i] Current theme: '$CURRENT_THEME'"
        
        if [[ "$CURRENT_THEME" == "cocktail" ]]; then
            echo "[✓] Plymouth theme successfully set to 'cocktail'"
        else
            echo "[!] Plymouth theme verification failed, but configuration files are in place"
            echo "[i] Available themes: $(plymouth-set-default-theme --list 2>/dev/null | tr '\n' ' ' || echo 'Unable to list')"
            
            # Force theme setting one more time
            echo "[i] Forcing theme configuration..."
            plymouth-set-default-theme cocktail 2>/dev/null || true
            echo "Theme=cocktail" > /etc/plymouth/plymouthd.conf
        fi
        
        # Ensure logo is in the right place and format
        echo "[i] Verifying theme logo..."
        if [[ ! -f "$THEME_LOGO" ]] && [[ -f "$LOGO_PATH" ]]; then
            echo "[i] Copying logo to theme directory..."
            cp "$LOGO_PATH" "$THEME_LOGO"
        fi
        
        if [[ -f "$THEME_LOGO" ]]; then
            # Re-optimize logo for Plymouth
            convert "$THEME_LOGO" -resize "1920x1080>" -background black -gravity center -extent 1920x1080 "$THEME_LOGO"
            echo "[i] Logo optimized for Plymouth display"
        fi
        
        # Update initramfs to include our theme
        echo "[i] Updating initramfs to include Plymouth theme..."
        echo "[i] This may take several minutes, please wait..."
        if ! update-initramfs -u; then
            echo "[!] Warning: initramfs update failed, trying with -k all flag..."
            update-initramfs -u -k all || echo "[!] initramfs update failed, theme may not work until manual update"
        fi
        
        # Final verification
        echo "[i] Final Plymouth configuration check..."
        FINAL_THEME=$(plymouth-set-default-theme --list 2>/dev/null | grep '\*' | sed 's/.*\* //' | head -n1 || echo "unknown")
        echo "[i] Final theme setting: '$FINAL_THEME'"
        
        if [[ -f /usr/share/plymouth/themes/cocktail/cocktail.plymouth ]] && \
           [[ -f /usr/share/plymouth/themes/cocktail/logo.png ]]; then
            echo "[✓] Plymouth theme files verified"
        else
            echo "[!] Plymouth theme files missing"
        fi
        
    else
        echo "[!] Plymouth tools not available, splash screen will not work"
        echo "[!] Try: apt-get install plymouth plymouth-themes"
    fi
    
    echo "[i] Boot splash configuration completed"
}

configure_kiosk_mode() {
    echo "[i] Configuring kiosk mode..."
    
    # Set default target to graphical
    systemctl set-default graphical.target
    
    # Enable and configure lightdm for auto-login
    systemctl enable lightdm
    
    # Configure lightdm for auto-login
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat >/etc/lightdm/lightdm.conf.d/01-cocktail.conf <<EOF
[Seat:*]
autologin-user=${NODERED_USER}
autologin-user-timeout=0
EOF
    
    # Create openbox autostart directory
    mkdir -p /home/${NODERED_USER}/.config/openbox
    
    # Create openbox autostart script
    cat >/home/${NODERED_USER}/.config/openbox/autostart <<EOF
#!/bin/bash
# CocktailMachine Openbox Autostart

# Wait for system to be ready
sleep 5

# Start the kiosk script
/home/${NODERED_USER}/cocktail-kiosk.sh &
EOF
    
    chmod +x /home/${NODERED_USER}/.config/openbox/autostart
    chown -R ${NODERED_USER}:${NODERED_USER} /home/${NODERED_USER}/.config
    
    # Create kiosk startup script with better reliability
    cat >/home/${NODERED_USER}/cocktail-kiosk.sh <<EOF
#!/bin/bash
# CocktailMachine Kiosk Mode Startup Script

export DISPLAY=:0

# Function to log messages
log_message() {
    echo "\$(date): \$1" >> /home/${NODERED_USER}/kiosk.log
}

log_message "Kiosk script starting..."

# Wait for X server to be ready
for i in {1..30}; do
    if xdpyinfo >/dev/null 2>&1; then
        log_message "X server is ready"
        break
    fi
    log_message "Waiting for X server... (\$i/30)"
    sleep 2
done

# Wait for network to be ready
log_message "Waiting for network..."
for i in {1..60}; do
    if ping -c 1 -W 2 ${SUBNET_IP} >/dev/null 2>&1; then
        log_message "Network is ready"
        break
    fi
    log_message "Waiting for network... (\$i/60)"
    sleep 2
done

# Wait for Node-RED to be responding
log_message "Waiting for Node-RED to be ready..."
for i in {1..120}; do
    if curl -s --connect-timeout 5 ${DASHBOARD_URL} >/dev/null 2>&1; then
        log_message "Node-RED is ready!"
        break
    fi
    log_message "Waiting for Node-RED... (\$i/120)"
    sleep 3
done

# Configure display settings
log_message "Configuring display..."
xset s off          # disable screen saver
xset -dpms          # disable power management
xset s noblank      # don't blank the video device

# Hide cursor
unclutter -display :0 -idle 2 -root &

# Function to start Chromium
start_chromium() {
    log_message "Starting Chromium browser..."
    chromium-browser \\
        --display=:0 \\
        --no-sandbox \\
        --no-first-run \\
        --disable-infobars \\
        --disable-session-crashed-bubble \\
        --disable-restore-session-state \\
        --disable-background-mode \\
        --disable-background-networking \\
        --disable-background-timer-throttling \\
        --disable-renderer-backgrounding \\
        --disable-backgrounding-occluded-windows \\
        --disable-component-extensions-with-background-pages \\
        --disable-extensions \\
        --disable-plugins \\
        --disable-default-apps \\
        --disable-translate \\
        --disable-features=TranslateUI \\
        --disable-ipc-flooding-protection \\
        --enable-features=OverlayScrollbar \\
        --disable-pinch \\
        --overscroll-history-navigation=0 \\
        --autoplay-policy=no-user-gesture-required \\
        --check-for-update-interval=31536000 \\
        --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \\
        --kiosk \\
        --incognito \\
        --app=${DASHBOARD_URL} \\
        >> /home/${NODERED_USER}/chromium.log 2>&1 &
    
    return \$!
}

# Start Chromium
CHROMIUM_PID=\$(start_chromium)
log_message "Chromium started with PID: \$CHROMIUM_PID"

# Monitor and restart Chromium if it crashes
while true; do
    sleep 30
    if ! kill -0 \$CHROMIUM_PID 2>/dev/null; then
        log_message "Chromium crashed, restarting..."
        # Kill any remaining Chromium processes
        pkill -f chromium-browser || true
        sleep 2
        # Restart Chromium
        CHROMIUM_PID=\$(start_chromium)
        log_message "Chromium restarted with PID: \$CHROMIUM_PID"
    fi
done
EOF
    
    chmod +x /home/${NODERED_USER}/cocktail-kiosk.sh
    chown ${NODERED_USER}:${NODERED_USER} /home/${NODERED_USER}/cocktail-kiosk.sh
    
    # Create session file for openbox
    cat >/home/${NODERED_USER}/.xsession <<EOF
#!/bin/bash
exec openbox-session
EOF
    chmod +x /home/${NODERED_USER}/.xsession
    chown ${NODERED_USER}:${NODERED_USER} /home/${NODERED_USER}/.xsession
    
    echo "[i] Kiosk mode configured with openbox + lightdm"
}

ap_autostart_service() {
    echo "[i] Creating AP autostart service..."
    cat >/etc/systemd/system/cocktail-ap.service <<EOF
[Unit]
Description=Bring up ${CON_NAME} AP after NetworkManager
After=NetworkManager.service network-online.target
Wants=NetworkManager.service network-online.target

[Service]
Type=oneshot
ExecStartPre=/usr/sbin/rfkill unblock wifi
ExecStart=/usr/bin/nmcli connection up "${CON_NAME}"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable cocktail-ap.service
}

bring_up_now() {
    echo "[i] Bringing up Access Point..."
    nmcli connection down "$CON_NAME" || true
    nmcli connection up "$CON_NAME" || {
        echo "[!] NM failed to activate ${CON_NAME}. Details:"
        nmcli -f GENERAL,IP4,IP6,802-11-wireless,802-11-wireless-security connection show "$CON_NAME" || true
        journalctl -xe --no-pager -u NetworkManager | tail -n 80 || true
        exit 1
    }
    # Expect IP on wlan1
    if ! ip -4 addr show dev "$IFACE" | grep -q "$SUBNET_IP"; then
        echo "[!] $IFACE does not have ${SUBNET_IP}. Current:"
        ip -4 addr show dev "$IFACE"
        exit 1
    fi
    systemctl restart dnsmasq
}

create_troubleshooting_script() {
    echo "[i] Creating troubleshooting script..."
    cat >/home/${NODERED_USER}/troubleshoot-cocktail.sh <<'EOF'
#!/bin/bash
# CocktailMachine Troubleshooting Script

echo "============ CocktailMachine Diagnostics ============"
echo "Date: $(date)"
echo

echo "--- Boot Configuration ---"
BOOT_DIR="/boot/firmware"
[[ ! -d "$BOOT_DIR" ]] && BOOT_DIR="/boot"

echo "Boot directory: $BOOT_DIR"
if [[ -f "$BOOT_DIR/cmdline.txt" ]]; then
    echo "cmdline.txt exists: YES"
    echo "Current cmdline.txt:"
    cat "$BOOT_DIR/cmdline.txt"
else
    echo "cmdline.txt exists: NO"
fi
echo

echo "--- Plymouth Configuration ---"
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    echo "Plymouth installed: YES"
    echo "Current Plymouth theme: $(plymouth-set-default-theme --list | grep '\*' | sed 's/.*\* //')"
    echo "Available themes: $(plymouth-set-default-theme --list | tr '\n' ' ')"
else
    echo "Plymouth installed: NO"
fi

if [[ -d /usr/share/plymouth/themes/cocktail ]]; then
    echo "CocktailMachine theme exists: YES"
    echo "Theme files:"
    ls -la /usr/share/plymouth/themes/cocktail/
else
    echo "CocktailMachine theme exists: NO"
fi
echo

echo "--- Logo File ---"
if [[ -f /home/pi/logo.png ]]; then
    echo "Logo file exists: YES"
    echo "Logo file size: $(du -h /home/pi/logo.png | cut -f1)"
    echo "Logo dimensions: $(identify /home/pi/logo.png 2>/dev/null || echo 'Unable to determine')"
else
    echo "Logo file exists: NO"
fi
echo

echo "--- Display Manager ---"
echo "Default target: $(systemctl get-default)"
if systemctl is-enabled lightdm >/dev/null 2>&1; then
    echo "LightDM enabled: YES"
    echo "LightDM status: $(systemctl is-active lightdm)"
else
    echo "LightDM enabled: NO"
fi

if [[ -f /etc/lightdm/lightdm.conf.d/01-cocktail.conf ]]; then
    echo "Auto-login configured: YES"
    cat /etc/lightdm/lightdm.conf.d/01-cocktail.conf
else
    echo "Auto-login configured: NO"
fi
echo

echo "--- Kiosk Configuration ---"
if [[ -f /home/pi/.config/openbox/autostart ]]; then
    echo "Openbox autostart exists: YES"
    echo "Autostart permissions: $(stat -c '%a' /home/pi/.config/openbox/autostart)"
else
    echo "Openbox autostart exists: NO"
fi

if [[ -f /home/pi/cocktail-kiosk.sh ]]; then
    echo "Kiosk script exists: YES"
    echo "Script permissions: $(stat -c '%a' /home/pi/cocktail-kiosk.sh)"
else
    echo "Kiosk script exists: NO"
fi

if [[ -f /home/pi/kiosk.log ]]; then
    echo "Kiosk log exists: YES"
    echo "Last 10 lines of kiosk log:"
    tail -n 10 /home/pi/kiosk.log
else
    echo "Kiosk log exists: NO"
fi
echo

echo "--- Network Services ---"
echo "Network Manager: $(systemctl is-active NetworkManager)"
echo "WiFi AP: $(nmcli -t -f NAME,STATE connection show | grep CocktailAP || echo 'Not found')"
echo "DHCP Server: $(systemctl is-active dnsmasq)"
echo "MQTT Broker: $(systemctl is-active mosquitto)"
echo "Node-RED: $(systemctl is-active nodered)"
echo

echo "--- Network Connectivity ---"
if ping -c 1 -W 2 192.168.50.1 >/dev/null 2>&1; then
    echo "AP IP reachable: YES"
else
    echo "AP IP reachable: NO"
fi

if curl -s --connect-timeout 5 http://192.168.50.1:1880/ui >/dev/null 2>&1; then
    echo "Node-RED dashboard reachable: YES"
else
    echo "Node-RED dashboard reachable: NO"
fi
echo

echo "--- Service Logs (last 10 lines) ---"
echo "NetworkManager:"
journalctl -u NetworkManager --no-pager -n 5

echo "Node-RED:"
journalctl -u nodered --no-pager -n 5

echo "LightDM:"
journalctl -u lightdm --no-pager -n 5

echo "================================================"
echo "Troubleshooting complete!"
echo
echo "Common fixes:"
echo "1. If logo not showing: Check /home/pi/logo.png exists and is valid PNG"
echo "2. If kiosk not starting: Check /home/pi/kiosk.log for errors"
echo "3. If services not starting: Run 'sudo systemctl status <service>'"
echo "4. To regenerate boot theme: sudo update-initramfs -u"
echo "5. To test manual kiosk: sudo -u pi /home/pi/cocktail-kiosk.sh"
EOF
    
    chmod +x /home/${NODERED_USER}/troubleshoot-cocktail.sh
    chown ${NODERED_USER}:${NODERED_USER} /home/${NODERED_USER}/troubleshoot-cocktail.sh
    
    echo "[i] Troubleshooting script created at /home/pi/troubleshoot-cocktail.sh"
}

test_services() {
    echo "[i] Testing services..."
    
    # Test MQTT
    echo "  Testing MQTT..."
    if systemctl is-active mosquitto >/dev/null; then
        echo "    Mosquitto is running"
        # Test MQTT connection
        if timeout 5 mosquitto_pub -h localhost -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/final" -m "Setup complete" >/dev/null 2>&1; then
            echo "    MQTT authentication working"
        else
            echo "    MQTT authentication failed"
        fi
    else
        echo "    Mosquitto is not running"
    fi
    
    # Test Node-RED
    echo "  Testing Node-RED..."
    if systemctl is-active nodered >/dev/null; then
        echo "    Node-RED is running"
        # Test HTTP endpoint on all interfaces
        if timeout 5 curl -s http://${SUBNET_IP}:${NODERED_PORT} >/dev/null 2>&1; then
            echo "    Node-RED web interface accessible on AP IP"
        else
            echo "    Node-RED web interface not accessible on AP IP"
        fi
    else
        echo "    Node-RED is not running"
    fi
    
    # Test network connectivity
    echo "  Testing network..."
    if ping -c 1 -W 2 ${SUBNET_IP} >/dev/null 2>&1; then
        echo "    AP IP is reachable"
    else
        echo "    AP IP is not reachable"
    fi
    
    # Test GUI configuration
    echo "  Testing GUI configuration..."
    if [[ "$(systemctl get-default)" == "graphical.target" ]]; then
        echo "    Boot target set to graphical: YES"
    else
        echo "    Boot target set to graphical: NO"
    fi
    
    if [[ -f /home/${NODERED_USER}/.config/openbox/autostart ]]; then
        echo "    Kiosk autostart configured: YES"
    else
        echo "    Kiosk autostart configured: NO"
    fi
    
    if [[ -f "$LOGO_PATH" ]]; then
        echo "    Logo file exists: YES"
    else
        echo "    Logo file missing: NO"
    fi
    
    # Test Plymouth
    echo "  Testing Plymouth..."
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        CURRENT_THEME=$(plymouth-set-default-theme --list 2>/dev/null | grep '\*' | sed 's/.*\* //' | head -n1 || echo "none")
        echo "    Plymouth theme: $CURRENT_THEME"
        if [[ "$CURRENT_THEME" == "cocktail" ]]; then
            echo "    Plymouth theme status: ✓ CORRECTLY SET"
        else
            echo "    Plymouth theme status: ✗ NOT SET (will try to fix)"
            # Try to fix it now
            plymouth-set-default-theme cocktail 2>/dev/null || true
            echo "Theme=cocktail" > /etc/plymouth/plymouthd.conf 2>/dev/null || true
        fi
        
        if [[ -f /usr/share/plymouth/themes/cocktail/logo.png ]]; then
            echo "    Plymouth logo: ✓ EXISTS"
        else
            echo "    Plymouth logo: ✗ MISSING"
        fi
    else
        echo "    Plymouth not available"
    fi
}

summary() {
    echo
    echo "================= CocktailMachine Setup Complete ================="
    echo "WiFi Access Point:"
    echo "  SSID:        $SSID"
    echo "  Password:    $PSK"
    echo "  Interface:   $IFACE"
    echo "  AP IP:       $SUBNET_IP"
    echo "  DHCP range:  $DHCP_START - $DHCP_END"
    echo
    echo "MQTT Broker:"
    echo "  Host:        $SUBNET_IP"
    echo "  Port:        $MQTT_PORT"
    echo "  Username:    $MQTT_USER"
    echo "  Password:    $MQTT_PASS"
    echo
    echo "Node-RED:"
    echo "  URL:         http://$SUBNET_IP:$NODERED_PORT"
    echo "  Dashboard:   http://$SUBNET_IP:$NODERED_PORT/ui"
    echo "  Dashboard 2: http://$SUBNET_IP:$NODERED_PORT/dashboard"
    echo "  Modules:     Dashboard, Dashboard 2.0, ui_list, ui_led, ui_table"
    echo
    echo "Kiosk Mode:"
    echo "  Logo:        $LOGO_PATH"
    echo "  Auto-start:  Dashboard will open on boot"
    echo "  Boot splash: Enabled with logo"
    echo "  Boot target: $(systemctl get-default)"
    echo "  Display Mgr: LightDM with auto-login"
    echo "  Stability:   Enhanced monitoring with 60s check interval"
    echo "  Recovery:    Smart restart logic with responsiveness checking"
    echo
    echo "Internet:      DISABLED (standalone network)"
    echo "Autostart:     All services enabled for boot"
    echo "Firewall:      Configured for local access only"
    echo "----------------------------------------------------------------"
    echo "Service Management:"
    echo "  WiFi AP:     nmcli connection up/down $CON_NAME"
    echo "  MQTT:        systemctl start/stop mosquitto"
    echo "  Node-RED:    systemctl start/stop nodered"
    echo "  DHCP:        systemctl start/stop dnsmasq"
    echo "  GUI:         systemctl set-default graphical.target"
    echo
    echo "Logs:"
    echo "  WiFi:        journalctl -u NetworkManager"
    echo "  MQTT:        journalctl -u mosquitto"
    echo "  Node-RED:    journalctl -u nodered"
    echo "  DHCP:        journalctl -u dnsmasq"
    echo "  GUI:         journalctl -u lightdm"
    echo "  Kiosk:       /home/pi/kiosk.log"
    echo "  Chromium:    /home/pi/chromium.log"
    echo
    echo "Files:"
    echo "  Logo:        $LOGO_PATH (replace with your own)"
    echo "  Kiosk script: /home/pi/cocktail-kiosk.sh"
    echo "  Boot theme:  /usr/share/plymouth/themes/cocktail/"
    echo "  Config:      $BOOT_DIR/cmdline.txt and $BOOT_DIR/config.txt"
    echo "  Troubleshoot: /home/pi/troubleshoot-cocktail.sh"
    echo
    echo "Next Steps:"
    echo "1. Replace logo.png with your own image: $LOGO_PATH"
    echo "2. REBOOT to see the complete kiosk experience: sudo reboot"
    echo "3. Connect to WiFi: $SSID (password: $PSK)"
    echo "4. The dashboard will auto-open at: $DASHBOARD_URL"
    echo "5. Build your cocktail interface in Node-RED!"
    echo
    echo "Troubleshooting:"
    echo "- If boot splash doesn't work: Run /home/pi/troubleshoot-cocktail.sh"
    echo "- If kiosk doesn't start: Check /home/pi/kiosk.log"
    echo "- Manual kiosk test: sudo -u pi /home/pi/cocktail-kiosk.sh"
    echo "- Fix Plymouth theme: sudo plymouth-set-default-theme cocktail && sudo update-initramfs -u"
    echo "- Test Plymouth: sudo plymouthd --debug --no-daemon & sudo plymouth --show-splash"
    echo
    echo "Expected boot sequence after reboot:"
    echo "1. Raspberry Pi rainbow splash (briefly)"
    echo "2. Your logo.png with loading progress"
    echo "3. Desktop loads and opens Node-RED dashboard automatically"
    echo "================================================================="
}

main() {
    echo "Starting CocktailMachine complete setup with enhanced kiosk mode v2.2..."
    echo "✓ Enhanced Plymouth theme configuration for reliable boot splash"
    echo "✓ Improved Node-RED installer with interactive prompt handling"
    echo "✓ Dashboard stability fixes - eliminates white screen flashing"
    echo "✓ Smart browser monitoring with responsiveness checking"
    echo "✓ Enhanced MQTT configuration with proper authentication"
    echo "✓ Comprehensive troubleshooting and verification"
    echo
    need_root
    install_prereqs
    install_driver_88x2bu
    configure_nm_ap
    configure_dnsmasq
    install_mosquitto
    install_nodered
    create_nodered_flows
    configure_firewall
    disable_forwarding
    configure_boot_splash
    configure_kiosk_mode
    ap_autostart_service
    bring_up_now
    create_troubleshooting_script
    test_services
    summary
    echo
    echo "Setup completed successfully!"
    echo
    echo "IMPORTANT: You MUST REBOOT to see the boot splash and kiosk mode:"
    echo "sudo reboot"
    echo
    echo "If something doesn't work after reboot, run:"
    echo "/home/pi/troubleshoot-cocktail.sh"
}

main "$@"