#!/bin/bash
# Service checker script

LOG_FILE="/tmp/kiosk-service-check.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Service Check Started ==="

# Maximum wait time (5 minutes)
MAX_WAIT=300
WAITED=0

# Wait for Docker to be ready
log "Waiting for Docker to be ready..."
while ! docker ps &>/dev/null && [ $WAITED -lt 60 ]; do
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ $WAITED -ge 60 ]; then
    log "ERROR: Docker not ready after 60 seconds"
    exit 1
fi

log "Docker is ready, checking cocktail machine service..."

# Reset counter for service check
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
    # Check the main dashboard endpoint (port 3000)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        log "Health check passed (HTTP $HTTP_CODE)"

        # Double check the main service
        MAIN_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
        if [ "$MAIN_CODE" = "200" ] || [ "$MAIN_CODE" = "302" ] || [ "$MAIN_CODE" = "304" ]; then
            log "Main service ready (HTTP $MAIN_CODE)"
            echo "READY"
            exit 0
        fi
    fi

    log "Service not ready yet (HTTP $HTTP_CODE), waiting... ($WAITED/$MAX_WAIT)"
    sleep 5
    WAITED=$((WAITED + 5))
done

log "ERROR: Service failed to start after $MAX_WAIT seconds"
echo "FAILED"
exit 1
