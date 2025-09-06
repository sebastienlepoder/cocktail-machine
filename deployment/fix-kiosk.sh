#!/bin/bash
# Fix script for Raspberry Pi Kiosk Mode
# Run this directly on the Raspberry Pi to fix boot and auto-login issues

echo "=== Cocktail Machine Kiosk Fix Script ==="
echo "This will fix the boot sequence and auto-login issues"
echo ""

# Ensure we're running as the pi user or with proper permissions
if [ "$USER" != "pi" ] && [ "$USER" != "root" ]; then
    echo "Please run this script as the 'pi' user or with sudo"
    exit 1
fi

# Fix 1: Configure auto-login to desktop properly
echo "1. Configuring auto-login to desktop..."
sudo raspi-config nonint do_boot_behaviour B4

# Fix 2: Ensure graphical target is default
echo "2. Setting graphical target as default..."
sudo systemctl set-default graphical.target

# Fix 3: Create proper autologin service
echo "3. Creating autologin service..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I $TERM
EOF

# Fix 4: Create .xinitrc for X startup
echo "4. Creating .xinitrc for X startup..."
cat > /home/pi/.xinitrc << 'EOF'
#!/bin/sh
# Start openbox window manager
exec openbox-session
EOF
chmod +x /home/pi/.xinitrc

# Fix 5: Update .bash_profile to start X if not in SSH session
echo "5. Updating .bash_profile for auto-start X..."
cat > /home/pi/.bash_profile << 'EOF'
# Auto-start X at login if not SSH session
if [ -z "$DISPLAY" ] && [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
    startx
fi
EOF

# Fix 6: Ensure openbox autostart is correct
echo "6. Updating openbox autostart..."
mkdir -p /home/pi/.config/openbox
cat > /home/pi/.config/openbox/autostart << 'EOF'
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor
unclutter -idle 1 &

# Wait a moment for X to stabilize
sleep 3

# Start the cocktail machine kiosk
/home/pi/.cocktail-machine/simple-kiosk.sh &
EOF

# Fix 7: Create a failsafe systemd service for the kiosk
echo "7. Creating systemd kiosk service..."
sudo tee /etc/systemd/system/cocktail-kiosk.service > /dev/null << 'EOF'
[Unit]
Description=Cocktail Machine Kiosk
After=graphical.target
Wants=graphical.target

[Service]
Type=simple
User=pi
Group=pi
Environment="DISPLAY=:0"
Environment="HOME=/home/pi"
Environment="XAUTHORITY=/home/pi/.Xauthority"
ExecStartPre=/bin/bash -c 'while ! xset q &>/dev/null; do sleep 1; done'
ExecStart=/home/pi/.cocktail-machine/simple-kiosk.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

# Fix 8: Ensure the simple kiosk script exists
echo "8. Ensuring kiosk script exists..."
if [ ! -f /home/pi/.cocktail-machine/simple-kiosk.sh ]; then
    mkdir -p /home/pi/.cocktail-machine
    cat > /home/pi/.cocktail-machine/simple-kiosk.sh << 'KIOSK'
#!/bin/bash
# Simple kiosk script

echo "[$(date)] Starting kiosk..." >> /tmp/kiosk.log

# Set display
export DISPLAY=:0

# Kill any existing browser
pkill -f chromium 2>/dev/null
sleep 2

# Check if loading screen exists
if [ -f /home/pi/.cocktail-machine/loading.html ]; then
    echo "[$(date)] Starting with loading screen..." >> /tmp/kiosk.log
    chromium-browser --kiosk --noerrdialogs --disable-infobars \
        "file:///home/pi/.cocktail-machine/loading.html" &
    BROWSER_PID=$!
    
    # Wait for service
    MAX_WAIT=300
    WAITED=0
    sleep 15
    
    while [ $WAITED -lt $MAX_WAIT ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302"; then
            echo "[$(date)] Service ready, switching to dashboard..." >> /tmp/kiosk.log
            kill $BROWSER_PID 2>/dev/null
            sleep 1
            chromium-browser --kiosk --noerrdialogs --disable-infobars \
                "http://localhost:3000" &
            exit 0
        fi
        sleep 5
        WAITED=$((WAITED + 5))
    done
else
    # No loading screen, go direct
    echo "[$(date)] No loading screen, going direct to dashboard..." >> /tmp/kiosk.log
    chromium-browser --kiosk --noerrdialogs --disable-infobars \
        "http://localhost:3000" &
fi
KIOSK
    chmod +x /home/pi/.cocktail-machine/simple-kiosk.sh
fi

# Fix 9: Enable services
echo "9. Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable cocktail-kiosk.service

# Fix 10: Fix quiet boot parameters
echo "10. Fixing quiet boot parameters..."
if [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
elif [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
else
    echo "Warning: Could not find cmdline.txt"
    CMDLINE_FILE=""
fi

if [ -n "$CMDLINE_FILE" ]; then
    # Backup
    sudo cp "$CMDLINE_FILE" "${CMDLINE_FILE}.backup.$(date +%s)"
    
    # Get current cmdline
    CMDLINE=$(cat "$CMDLINE_FILE" | tr -d '\n')
    
    # Remove any existing quiet parameters to avoid duplicates
    CMDLINE=$(echo "$CMDLINE" | sed 's/quiet//g' | sed 's/splash//g' | sed 's/plymouth.ignore-serial-consoles//g' | sed 's/logo.nologo//g' | sed 's/vt.global_cursor_default=0//g' | sed 's/loglevel=0//g' | sed 's/  */ /g')
    
    # Add quiet parameters at the end
    CMDLINE="$CMDLINE quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0 loglevel=0"
    
    # Write back
    echo "$CMDLINE" | sudo tee "$CMDLINE_FILE" > /dev/null
    echo "Updated boot parameters in $CMDLINE_FILE"
fi

# Fix 11: Disable unnecessary services that show messages
echo "11. Disabling unnecessary boot messages..."
sudo systemctl disable bluetooth.service 2>/dev/null || true
sudo systemctl disable hciuart.service 2>/dev/null || true
sudo systemctl disable apt-daily.service 2>/dev/null || true
sudo systemctl disable apt-daily-upgrade.service 2>/dev/null || true

echo ""
echo "=== Fix Applied Successfully! ==="
echo ""
echo "The system will now reboot to apply all changes."
echo "After reboot, you should see:"
echo "1. No boot messages (black screen)"
echo "2. Auto-login to desktop"
echo "3. Loading screen appears"
echo "4. Dashboard loads when ready"
echo ""
echo "Press Enter to reboot now, or Ctrl+C to reboot manually later..."
read

sudo reboot
