#!/bin/bash
# Simple Kiosk Launcher for Cocktail Machine

echo "🍹 Starting Cocktail Machine Dashboard..."

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 5

# Check if dashboard is running
if ! curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo "Dashboard not running. Starting Docker services..."
    cd /home/pi/cocktail-machine/deployment
    docker-compose up -d
    echo "Waiting for dashboard to start..."
    sleep 20
fi

# Determine which chromium command to use
if command -v chromium-browser &> /dev/null; then
    BROWSER="chromium-browser"
elif command -v chromium &> /dev/null; then
    BROWSER="chromium"
else
    echo "Error: Chromium not found! Installing..."
    sudo apt-get update
    sudo apt-get install -y chromium-browser
    BROWSER="chromium-browser"
fi

echo "Starting browser in kiosk mode..."

# Try with sudo if regular start fails
$BROWSER \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --disable-translate \
    --disable-features=TranslateUI \
    --check-for-update-interval=604800 \
    --start-fullscreen \
    http://localhost:3000 2>/dev/null || \
sudo $BROWSER \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --disable-translate \
    --disable-features=TranslateUI \
    --check-for-update-interval=604800 \
    --start-fullscreen \
    http://localhost:3000
