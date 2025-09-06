#!/bin/bash
# Cocktail Machine - Start Docker Services Script
# This script starts all the cocktail machine Docker services

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_step() { echo -e "${BLUE}►${NC} $1"; }

echo "🍹 Cocktail Machine - Service Starter"
echo "====================================="

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Change to the deployment directory
print_step "Changing to deployment directory: $SCRIPT_DIR"
cd "$SCRIPT_DIR"

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml not found in $SCRIPT_DIR"
    print_info "Make sure you're running this script from the deployment directory"
    exit 1
fi

# Check if Docker is running
print_step "Checking Docker status..."
if ! docker ps &>/dev/null; then
    print_error "Docker is not running or not accessible"
    print_info "Try: sudo systemctl start docker"
    exit 1
fi
print_status "Docker is running"

# Check if user is in docker group
if ! groups $USER | grep -q docker; then
    print_info "User $USER is not in docker group, using sudo..."
    DOCKER_CMD="sudo docker-compose"
else
    DOCKER_CMD="docker-compose"
fi

# Stop any existing containers
print_step "Stopping any existing containers..."
$DOCKER_CMD down 2>/dev/null || true

# Start the services
print_step "Starting Docker Compose services..."
if $DOCKER_CMD up -d; then
    print_status "Services started successfully!"
    
    # Wait a moment for services to initialize
    sleep 3
    
    # Show status
    print_step "Service status:"
    $DOCKER_CMD ps
    
    echo ""
    print_status "🎉 All services are now running!"
    echo ""
    print_info "You can access:"
    print_info "• Dashboard: http://$(hostname -I | awk '{print $1}')"
    print_info "• Node-RED: http://$(hostname -I | awk '{print $1}'):1880"
    echo ""
    print_info "To stop services: $DOCKER_CMD down"
    print_info "To view logs: $DOCKER_CMD logs -f"
    
else
    print_error "Failed to start services"
    echo ""
    print_info "Troubleshooting:"
    print_info "• Check logs: $DOCKER_CMD logs"
    print_info "• Check .env file exists and has correct values"
    print_info "• Ensure all required ports are free"
    print_info "• Try: $DOCKER_CMD down && $DOCKER_CMD up -d"
    exit 1
fi
