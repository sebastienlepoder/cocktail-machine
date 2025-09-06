#!/bin/bash

# Quick fix script to add health endpoint to nginx config
# Run this on an existing Pi installation to fix the health check

echo "=== Nginx Health Endpoint Fix ==="

cd /home/pi/cocktail-machine/deployment

# Backup current config
echo "Backing up current nginx config..."
cp nginx/nginx.conf nginx/nginx.conf.backup.$(date +%s)

# Create corrected nginx config with health endpoint
echo "Creating nginx config with health endpoint..."
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
        
        # Health check endpoint - CRITICAL for kiosk mode
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
        
        # WebSocket support
        location /ws {
            proxy_pass http://dashboard;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOF

# Restart nginx to apply changes
echo "Restarting nginx..."
docker-compose restart nginx

# Wait a moment for nginx to start
sleep 3

# Test the health endpoint
echo "Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s http://localhost/health)

if [ "$HEALTH_RESPONSE" = "healthy" ]; then
    echo "✅ SUCCESS: Health endpoint working!"
    echo "✅ Response: $HEALTH_RESPONSE"
    
    # Kill existing kiosk and restart it
    echo "Restarting kiosk..."
    pkill -f chromium 2>/dev/null || true
    sleep 2
    
    DISPLAY=:0 /home/pi/.cocktail-machine/kiosk-launcher.sh &
    echo "✅ Kiosk restarted - loading screen should transition to dashboard soon!"
    
else
    echo "❌ FAILED: Health endpoint not working"
    echo "❌ Response: $HEALTH_RESPONSE"
    echo "Check nginx logs: docker-compose logs nginx"
fi

echo ""
echo "=== Fix Complete ==="
