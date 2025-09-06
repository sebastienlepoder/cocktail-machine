#!/bin/bash

# Fix script for Raspberry Pi kiosk startup issues
# Run this on your existing Pi to fix the black screen problem

echo "=== Cocktail Machine Kiosk Startup Fix ==="

# 1. Update nginx config with health endpoint
echo "1. Fixing nginx configuration..."
cd /home/pi/cocktail-machine/deployment

# Backup current nginx config
cp nginx/nginx.conf nginx/nginx.conf.backup

# Add health endpoint if missing
if ! grep -q "/health" nginx/nginx.conf; then
    cat > nginx/nginx.conf << 'EOF'
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

    # Restart nginx
    docker-compose restart nginx
    echo "✓ Nginx updated with health endpoint"
else
    echo "✓ Health endpoint already present"
fi

# 2. Configure LightDM auto-login
echo "2. Configuring auto-login..."
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/01-autologin.conf > /dev/null << EOF
[Seat:*]
autologin-user=pi
autologin-user-timeout=0
user-session=openbox
greeter-session=lightdm-gtk-greeter
EOF

# 3. Enable graphical target and LightDM
sudo systemctl set-default graphical.target
sudo systemctl enable lightdm

# 4. Create kiosk startup service
echo "3. Creating kiosk startup service..."
sudo tee /etc/systemd/system/cocktail-kiosk-startup.service > /dev/null << 'EOF'
[Unit]
Description=Start Cocktail Machine Kiosk
After=lightdm.service graphical.target cocktail-machine.service
Wants=lightdm.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
ExecStartPre=/bin/sleep 15
ExecStart=/bin/bash -c 'systemctl start lightdm; sleep 5; sudo -u pi DISPLAY=:0 /home/pi/.cocktail-machine/kiosk-launcher.sh &'

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable cocktail-kiosk-startup.service

# 5. Add .bashrc fallback
echo "4. Adding .bashrc fallback..."
if ! grep -q "kiosk-launcher" ~/.bashrc; then
    cat >> ~/.bashrc << 'BASHRC'

# Auto-start kiosk if not SSH session and no desktop running
if [ -z "$SSH_TTY" ] && [ -z "$DISPLAY" ] && [ "$TERM" = "linux" ]; then
    if [ $(tty) = "/dev/tty1" ]; then
        echo "Starting desktop and kiosk mode..."
        startx -- -nocursor &
        sleep 8
        export DISPLAY=:0
        /home/pi/.cocktail-machine/kiosk-launcher.sh &
    fi
fi
BASHRC
fi

# 6. Test the setup
echo "5. Testing configuration..."

# Test health endpoint
echo -n "Health endpoint: "
curl -s http://localhost/health || echo "FAILED"

# Test dashboard
echo -n "Dashboard: "
if curl -s http://localhost | grep -q "Cocktail Machine"; then
    echo "OK"
else
    echo "FAILED"
fi

echo ""
echo "=== Fix Complete ==="
echo ""
echo "The system now has multiple ways to start:"
echo "1. LightDM auto-login → OpenBox → Kiosk"
echo "2. Systemd service as backup"
echo "3. .bashrc fallback if all else fails"
echo ""
echo "Reboot to test: sudo reboot"
echo ""
echo "If still having issues after reboot:"
echo "- Check: sudo systemctl status lightdm"
echo "- Check: sudo systemctl status cocktail-kiosk-startup"
echo "- Manual start: sudo systemctl start lightdm"
