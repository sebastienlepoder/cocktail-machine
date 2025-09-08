#!/bin/bash

# Fix Node-RED container restart loop
echo "==================================================="
echo "🔴 Fixing Node-RED Container Restart Loop"
echo "==================================================="

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

PROJECT_DIR="/home/$USER/cocktail-machine"

if [ ! -d "$PROJECT_DIR" ]; then
    print_error "Project directory not found: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"

print_step "1. Diagnosing Node-RED restart issue"

print_info "Current container status:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

print_info "Node-RED container logs (last 20 lines):"
docker logs cocktail-nodered --tail 20 2>/dev/null || print_error "Cannot access container logs"

print_step "2. Stopping containers for inspection"
print_info "Stopping containers..."
docker-compose stop 2>/dev/null || docker compose stop 2>/dev/null || {
    print_info "Docker compose not available, stopping manually..."
    docker stop cocktail-nodered cocktail-mqtt 2>/dev/null
}

print_step "3. Checking Node-RED data directory"
print_info "Node-RED data directory contents:"
ls -la nodered/data/ 2>/dev/null || print_error "Node-RED data directory not accessible"

print_info "Checking Node-RED data permissions:"
stat nodered/data/ 2>/dev/null || print_error "Cannot stat nodered/data"

print_step "4. Fixing Node-RED configuration"

print_info "Ensuring Node-RED data directory exists with correct permissions..."
mkdir -p nodered/data
sudo chown -R 1000:1000 nodered/data
chmod -R 755 nodered/data

print_info "Creating basic Node-RED settings if missing..."
if [ ! -f "nodered/data/settings.js" ]; then
    cat > nodered/data/settings.js << 'SETTINGS_EOF'
module.exports = {
    uiPort: process.env.PORT || 1880,
    uiHost: '0.0.0.0',
    
    // Security
    httpAdminRoot: '/admin',
    httpNodeRoot: '/api',
    
    // Runtime settings
    userDir: '/data',
    flowFile: 'flows.json',
    flowFilePretty: true,
    
    // UI settings
    editorTheme: {
        page: {
            title: "Cocktail Machine - Node-RED",
            favicon: "🍹"
        },
        header: {
            title: "🍹 Cocktail Machine Control"
        }
    },
    
    // Logging
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },
    
    // Function settings
    functionGlobalContext: {
        // Add any global variables here
    },
    
    // Export settings
    exportGlobalContextKeys: false
};
SETTINGS_EOF
    print_status "Created Node-RED settings.js"
fi

print_info "Creating basic flows.json if missing..."
if [ ! -f "nodered/data/flows.json" ]; then
    cat > nodered/data/flows.json << 'FLOWS_EOF'
[
    {
        "id": "main-flow",
        "type": "tab",
        "label": "Cocktail Machine Main",
        "disabled": false,
        "info": ""
    },
    {
        "id": "welcome-inject",
        "type": "inject",
        "z": "main-flow",
        "name": "Welcome Message",
        "props": [
            {
                "p": "payload"
            }
        ],
        "repeat": "",
        "crontab": "",
        "once": true,
        "onceDelay": 0.1,
        "topic": "",
        "payload": "🍹 Cocktail Machine Node-RED is running!",
        "payloadType": "str",
        "x": 140,
        "y": 80,
        "wires": [
            [
                "debug-output"
            ]
        ]
    },
    {
        "id": "debug-output",
        "type": "debug",
        "z": "main-flow",
        "name": "System Status",
        "active": true,
        "tosidebar": true,
        "console": false,
        "tostatus": false,
        "complete": "payload",
        "targetType": "msg",
        "statusVal": "",
        "statusType": "auto",
        "x": 360,
        "y": 80,
        "wires": []
    }
]
FLOWS_EOF
    print_status "Created basic flows.json"
fi

print_info "Setting correct permissions for all Node-RED files..."
sudo chown -R 1000:1000 nodered/data
chmod 644 nodered/data/*.js* 2>/dev/null || true
chmod 644 nodered/data/*.json 2>/dev/null || true

print_step "5. Updating Docker Compose configuration"

print_info "Creating optimized docker-compose.yml..."
cat > docker-compose.yml << 'DOCKER_EOF'
version: '3.8'

services:
  nodered:
    image: nodered/node-red:latest
    container_name: cocktail-nodered
    restart: unless-stopped
    ports:
      - "1880:1880"
    volumes:
      - ./nodered/data:/data
    environment:
      - TZ=Europe/Paris
      - NODE_RED_ENABLE_PROJECTS=false
      - NODE_RED_ENABLE_SAFE_MODE=false
    networks:
      - cocktail-network
    user: "1000:1000"
    command: ["node-red", "--userDir", "/data", "--settings", "/data/settings.js"]

  mqtt:
    image: eclipse-mosquitto:latest
    container_name: cocktail-mqtt
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto/config:/mosquitto/config
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log
    networks:
      - cocktail-network

networks:
  cocktail-network:
    driver: bridge
DOCKER_EOF

print_status "Updated docker-compose.yml with explicit user and command"

print_step "6. Starting containers with new configuration"

print_info "Removing old containers..."
docker-compose down --remove-orphans 2>/dev/null || docker compose down --remove-orphans 2>/dev/null || {
    docker rm -f cocktail-nodered cocktail-mqtt 2>/dev/null || true
}

print_info "Starting containers with new configuration..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose up -d
elif docker compose version >/dev/null 2>&1; then
    docker compose up -d
else
    print_error "Docker Compose not available"
    exit 1
fi

print_step "7. Monitoring Node-RED startup"

print_info "Waiting for Node-RED to start..."
sleep 15

print_info "Checking container status..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

print_info "Node-RED logs (last 10 lines):"
docker logs cocktail-nodered --tail 10 2>/dev/null || print_error "Cannot access logs"

print_step "8. Testing Node-RED accessibility"

for i in {1..10}; do
    print_info "Testing Node-RED accessibility (attempt $i/10)..."
    
    if curl -s http://localhost:1880 >/dev/null 2>&1; then
        print_status "Node-RED is accessible!"
        
        print_info "Testing Node-RED admin interface..."
        if curl -s http://localhost:1880/admin >/dev/null 2>&1; then
            print_status "Node-RED admin interface is working!"
        fi
        
        break
    else
        if [ $i -eq 10 ]; then
            print_error "Node-RED still not accessible after 10 attempts"
            print_info "Final container status:"
            docker ps -a | grep cocktail-nodered
            print_info "Final logs:"
            docker logs cocktail-nodered --tail 5 2>/dev/null
        else
            sleep 5
        fi
    fi
done

echo
echo "==================================================="
echo "🔴 Node-RED Fix Completed!"
echo "==================================================="
echo
echo "🌍 Try accessing Node-RED now:"
echo "   • Node-RED Editor: http://$(hostname -I | awk '{print $1}'):1880/admin"
echo "   • Node-RED Dashboard: http://$(hostname -I | awk '{print $1}'):1880/ui"
echo
echo "📋 Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
echo
echo "🔄 If Node-RED is still not working:"
echo "   1. Check logs: docker logs cocktail-nodered"
echo "   2. Restart: docker-compose restart nodered"
echo "   3. Check permissions: ls -la nodered/data/"
