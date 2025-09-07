#!/bin/bash

# Cocktail Machine Auto-Update Service
# Checks for Git updates and redeploys services automatically

# Configuration
GIT_REPO=${GIT_REPO:-"https://github.com/sebastienlepoder/cocktail-machine-dev.git"}
UPDATE_INTERVAL=${UPDATE_INTERVAL:-3600}  # Default: 1 hour
APP_DIR="/app"
DEPLOYMENT_DIR="/deployment"
UPDATE_LOG="/var/log/cocktail-updater.log"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$UPDATE_LOG"
}

# Function to check for updates
check_for_updates() {
    cd "$APP_DIR"
    
    # Fetch latest changes from remote
    git fetch origin main
    
    # Check if there are updates
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    
    if [ "$LOCAL" != "$REMOTE" ]; then
        return 0  # Updates available
    else
        return 1  # No updates
    fi
}

# Function to apply updates
apply_updates() {
    log_message "Applying updates..."
    
    cd "$APP_DIR"
    
    # Store current commit hash
    OLD_COMMIT=$(git rev-parse HEAD)
    
    # Pull latest changes
    git pull origin main
    
    # Get new commit hash
    NEW_COMMIT=$(git rev-parse HEAD)
    
    # Log the update
    log_message "Updated from $OLD_COMMIT to $NEW_COMMIT"
    
    # Check what changed
    CHANGED_FILES=$(git diff --name-only "$OLD_COMMIT" "$NEW_COMMIT")
    
    # Determine what needs to be redeployed
    NEEDS_RESTART=false
    UPDATE_ESP32=false
    UPDATE_NODERED=false
    UPDATE_WEB=false
    
    for file in $CHANGED_FILES; do
        case "$file" in
            esp32/*)
                UPDATE_ESP32=true
                ;;
            node-red/*|deployment/nodered/*)
                UPDATE_NODERED=true
                NEEDS_RESTART=true
                ;;
            web/*)
                UPDATE_WEB=true
                NEEDS_RESTART=true
                ;;
            deployment/docker-compose.yml|deployment/mosquitto/*)
                NEEDS_RESTART=true
                ;;
        esac
    done
    
    # Apply updates based on what changed
    if [ "$NEEDS_RESTART" = true ]; then
        log_message "Restarting Docker services..."
        cd "$DEPLOYMENT_DIR"
        
        # Pull new images if needed
        docker-compose pull
        
        # Restart services with minimal downtime
        docker-compose up -d --build
        
        log_message "Services restarted successfully"
    fi
    
    if [ "$UPDATE_ESP32" = true ]; then
        log_message "ESP32 firmware updated. Manual flashing required."
        # Could trigger OTA update here if implemented
        
        # Create notification file for web dashboard
        echo "{\"type\":\"firmware_update\",\"timestamp\":\"$(date -Iseconds)\"}" > "$DEPLOYMENT_DIR/notifications/firmware_update.json"
    fi
    
    if [ "$UPDATE_NODERED" = true ]; then
        log_message "Node-RED flows updated"
        
        # Copy new flows if they exist
        if [ -f "$APP_DIR/node-red/flows.json" ]; then
            cp "$APP_DIR/node-red/flows.json" "$DEPLOYMENT_DIR/nodered/data/"
            
            # Restart Node-RED to load new flows
            docker-compose -f "$DEPLOYMENT_DIR/docker-compose.yml" restart nodered
        fi
    fi
    
    if [ "$UPDATE_WEB" = true ]; then
        log_message "Web dashboard updated"
        
        # Rebuild web container
        docker-compose -f "$DEPLOYMENT_DIR/docker-compose.yml" up -d --build web-dashboard
    fi
    
    # Run any migration scripts if they exist
    if [ -f "$APP_DIR/deployment/migrate.sh" ]; then
        log_message "Running migration script..."
        bash "$APP_DIR/deployment/migrate.sh"
    fi
    
    # Send notification about successful update
    send_update_notification "Update completed successfully"
}

# Function to send notifications (implement based on your needs)
send_update_notification() {
    local message=$1
    
    # Send MQTT notification
    if command -v mosquitto_pub &> /dev/null; then
        mosquitto_pub -h mosquitto -t "cocktail/system/update" -m "{\"status\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}"
    fi
    
    # Log to file for web dashboard
    echo "{\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}" > "$DEPLOYMENT_DIR/notifications/last_update.json"
}

# Function to perform health check
health_check() {
    local all_healthy=true
    
    # Check if services are running
    for service in mosquitto nodered postgres web-dashboard; do
        if ! docker ps | grep -q "cocktail-$service"; then
            log_message "WARNING: Service $service is not running"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = false ]; then
        log_message "Attempting to restart failed services..."
        cd "$DEPLOYMENT_DIR"
        docker-compose up -d
    fi
}

# Main update loop
main() {
    log_message "Cocktail Machine Update Service Started"
    log_message "Repository: $GIT_REPO"
    log_message "Update interval: $UPDATE_INTERVAL seconds"
    
    # Initial setup
    if [ ! -d "$APP_DIR/.git" ]; then
        log_message "Cloning repository..."
        git clone "$GIT_REPO" "$APP_DIR"
    fi
    
    # Create notifications directory
    mkdir -p "$DEPLOYMENT_DIR/notifications"
    
    while true; do
        # Perform health check
        health_check
        
        # Check for updates
        if check_for_updates; then
            log_message "Updates available, applying..."
            apply_updates
        else
            log_message "No updates available"
        fi
        
        # Wait before next check
        sleep "$UPDATE_INTERVAL"
    done
}

# Handle signals for graceful shutdown
trap 'log_message "Update service shutting down..."; exit 0' SIGTERM SIGINT

# Start the service
main
