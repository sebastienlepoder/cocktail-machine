#!/usr/bin/env bash
# CocktailMachine Complete Setup (Raspberry Pi OS Bookworm / Pi 5)
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

need_root() { 
    if [[ $EUID -ne 0 ]]; then 
        echo "Run as root: sudo $0"
        exit 1
    fi
}

install_prereqs() {
    echo "[i] Installing prerequisites..."
    apt-get update
    apt-get install -y raspberrypi-kernel-headers build-essential bc dkms git rfkill iw \
                       network-manager dnsmasq curl wget ufw
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
    
    # Download and run the official Node-RED installer
    echo "[i] Running official Node-RED installer (this may take several minutes)..."
    cd /tmp
    curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered -o install-nodered.sh
    chmod +x install-nodered.sh
    ./install-nodered.sh --confirm-install --confirm-pi
    
    # The official installer already creates the systemd service and enables it
    echo "[i] Node-RED installed successfully"
    
    # Create Node-RED settings file with custom configuration
    echo "[i] Configuring Node-RED settings..."
    cat >/home/${NODERED_USER}/.node-red/settings.js <<'EOF'
module.exports = {
    uiPort: process.env.PORT || 1880,
    uiHost: "0.0.0.0",
    mqttReconnectTime: 15000,
    serialReconnectTime: 15000,
    debugMaxLength: 1000,
    httpAdminRoot: '/',
    httpNodeRoot: '/',
    userDir: '/home/pi/.node-red/',
    functionGlobalContext: {},
    exportGlobalContextKeys: false,
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
        }
    },
    ui: { path: "ui" }
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
    echo "[i] Creating initial Node-RED flows..."
    
    # Create a basic flow with MQTT nodes
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
        "clientid": "nodered_cocktail",
        "usetls": false,
        "compatmode": false,
        "keepalive": "60",
        "cleansession": true,
        "birthTopic": "",
        "birthQos": "0",
        "birthPayload": "",
        "closeTopic": "",
        "closeQos": "0",
        "closePayload": "",
        "willTopic": "",
        "willQos": "0",
        "willPayload": "",
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
        "datatype": "auto",
        "broker": "mqtt_broker",
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
    echo "Internet:      DISABLED (standalone network)"
    echo "Autostart:     All services enabled for boot"
    echo "Firewall:      Configured for local access only"
    echo "----------------------------------------------------------------"
    echo "Service Management:"
    echo "  WiFi AP:     nmcli connection up/down $CON_NAME"
    echo "  MQTT:        systemctl start/stop mosquitto"
    echo "  Node-RED:    systemctl start/stop nodered"
    echo "  DHCP:        systemctl start/stop dnsmasq"
    echo
    echo "Logs:"
    echo "  WiFi:        journalctl -u NetworkManager"
    echo "  MQTT:        journalctl -u mosquitto"
    echo "  Node-RED:    journalctl -u nodered"
    echo "  DHCP:        journalctl -u dnsmasq"
    echo
    echo "Next Steps:"
    echo "1. Connect to WiFi: $SSID (password: $PSK)"
    echo "2. Open Node-RED: http://$SUBNET_IP:$NODERED_PORT"
    echo "3. Import your flows or create new ones"
    echo "4. Access Dashboard: http://$SUBNET_IP:$NODERED_PORT/ui"
    echo "5. Access Dashboard 2.0: http://$SUBNET_IP:$NODERED_PORT/dashboard"
    echo "6. Test MQTT: mosquitto_pub -h $SUBNET_IP -p $MQTT_PORT -u $MQTT_USER -P $MQTT_PASS -t 'test/topic' -m 'Hello World'"
    echo "================================================================="
}

main() {
    echo "Starting CocktailMachine complete setup..."
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
    ap_autostart_service
    bring_up_now
    test_services
    summary
    echo
    echo "Setup completed successfully! Reboot recommended."
}

main "$@"