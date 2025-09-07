#!/bin/bash
# Simple and reliable kiosk script for Cocktail Machine

# Function to log messages
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /tmp/kiosk.log
}

log_msg "Starting cocktail machine kiosk..."

# Ensure DISPLAY is set
export DISPLAY=:0

# Kill any existing chromium
pkill -f chromium 2>/dev/null

# Wait a moment
sleep 2

# Start loading screen
log_msg "Launching loading screen..."
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-component-update \
    "file://$HOME/.cocktail-machine-dev/loading.html" &

LOADING_PID=$!
log_msg "Loading screen PID: $LOADING_PID"

# Wait for service
MAX_WAIT=300
WAITED=0
CHECKING=true

# Initial wait for docker to start
sleep 20

while $CHECKING; do
    log_msg "Checking if service is ready (attempt $WAITED)..."
    
    # Try to connect to the service
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        log_msg "Service is ready! (HTTP $HTTP_CODE)"
        
        # Kill loading screen
        kill $LOADING_PID 2>/dev/null
        
        # Small delay
        sleep 2
        
        # Launch dashboard
        log_msg "Launching dashboard..."
        chromium-browser \
            --kiosk \
            --noerrdialogs \
            --disable-infobars \
            --disable-component-update \
            "http://localhost:3000" &
        
        log_msg "Dashboard launched successfully!"
        exit 0
    fi
    
    # Check timeout
    if [ $WAITED -ge $MAX_WAIT ]; then
        log_msg "Service failed to start after $MAX_WAIT seconds"
        CHECKING=false
    else
        sleep 5
        WAITED=$((WAITED + 5))
    fi
done

# If we get here, service failed
log_msg "Showing error page..."
kill $LOADING_PID 2>/dev/null
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    "data:text/html,<h1 style='color:red;text-align:center;margin-top:40vh'>Service Failed to Start</h1>" &
