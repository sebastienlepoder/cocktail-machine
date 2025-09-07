#!/bin/bash
# Ultimate Kiosk Launcher

LOG_FILE="/tmp/kiosk-launcher.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Kiosk Launcher Started ==="

# Ensure DISPLAY is set
export DISPLAY=:0

# Kill any existing browser processes
pkill -f chromium-browser 2>/dev/null || true
sleep 2

# Start loading screen
log "Starting loading screen..."
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-extensions \
    --disable-plugins \
    --disable-translate \
    --disable-features=TranslateUI \
    --disable-ipc-flooding-protection \
    --disable-renderer-backgrounding \
    --disable-backgrounding-occluded-windows \
    --disable-features=VizDisplayCompositor \
    --autoplay-policy=no-user-gesture-required \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-component-update \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-field-trial-config \
    --disable-background-networking \
    "file:///home/$USER/.cocktail-machine-dev/loading.html" &

LOADING_PID=$!
log "Loading screen started (PID: $LOADING_PID)"

# Wait for service to be ready
log "Checking if service is ready..."
/home/$USER/.cocktail-machine-dev/check-service.sh
SERVICE_STATUS=$?

if [ $SERVICE_STATUS -eq 0 ]; then
    log "Service is ready! Switching to dashboard..."

    # Kill loading screen
    kill $LOADING_PID 2>/dev/null || true
    sleep 2

    # Start dashboard
    log "Starting dashboard..."
    chromium-browser \
        --kiosk \
        --noerrdialogs \
        --disable-infobars \
        --disable-extensions \
        --disable-plugins \
        --disable-translate \
        --disable-features=TranslateUI \
        --autoplay-policy=no-user-gesture-required \
        --no-first-run \
        --fast \
        --fast-start \
        --disable-component-update \
        "http://localhost:3000" &

    log "Dashboard started successfully!"
else
    log "Service failed to start, showing error page..."

    # Kill loading screen
    kill $LOADING_PID 2>/dev/null || true
    sleep 1

    # Show error page
    chromium-browser \
        --kiosk \
        --noerrdialogs \
        --disable-infobars \
        "data:text/html,<html><head><title>Service Error</title></head><body style='background:#e74c3c;color:white;display:flex;align-items:center;justify-content:center;height:100vh;font-family:Arial,sans-serif'><div style='text-align:center'><h1 style='font-size:48px;margin-bottom:20px'>🚫 Service Error</h1><p style='font-size:24px'>The cocktail machine service failed to start</p><p style='font-size:16px;margin-top:20px'>Check logs: /tmp/kiosk-*.log</p></div></body></html>" &
fi
