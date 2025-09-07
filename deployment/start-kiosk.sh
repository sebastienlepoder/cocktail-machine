#!/bin/bash
# Simplified kiosk startup script for Cocktail Machine
# This script can be run directly or added to autostart

# Wait for X to be ready
sleep 5

# Disable screen blanking
export DISPLAY=:0
xset s off
xset -dpms
xset s noblank

# Kill any existing chromium instances
pkill -f chromium

# Start with loading screen
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --check-for-update-interval=604800 \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --disable-translate \
    --touch-events=enabled \
    --enable-touch-drag-drop \
    --enable-touch-editing \
    --disable-features=TranslateUI \
    --disable-session-crashed-bubble \
    --disable-component-update \
    --autoplay-policy=no-user-gesture-required \
    "file:///home/$USER/.cocktail-machine-dev/loading.html" &

BROWSER_PID=$!

# Wait for service to be ready
echo "Waiting for cocktail machine services..."
MAX_WAIT=300
WAITED=0

# Give Docker time to start
sleep 15

while [ $WAITED -lt $MAX_WAIT ]; do
    # Check if service is ready
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|302"; then
        echo "Dashboard is ready!"
        # Kill loading screen
        kill $BROWSER_PID 2>/dev/null
        sleep 1
        # Start dashboard
        chromium-browser \
            --kiosk \
            --noerrdialogs \
            --disable-infobars \
            --check-for-update-interval=604800 \
            --disable-pinch \
            --overscroll-history-navigation=0 \
            --disable-translate \
            --touch-events=enabled \
            --enable-touch-drag-drop \
            --enable-touch-editing \
            --disable-features=TranslateUI \
            --disable-session-crashed-bubble \
            --disable-component-update \
            --autoplay-policy=no-user-gesture-required \
            "http://localhost:3000" &
        exit 0
    fi
    
    sleep 3
    WAITED=$((WAITED + 3))
done

echo "Service failed to start"
# Show error page
kill $BROWSER_PID 2>/dev/null
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    "data:text/html,<html><body style='background:#f44336;color:white;display:flex;align-items:center;justify-content:center;height:100vh;font-family:sans-serif;'><div style='text-align:center;'><h1>Service Failed to Start</h1><p>Please check the system logs</p></div></body></html>" &
