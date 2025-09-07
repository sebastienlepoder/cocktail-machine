# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a custom Cocktail Machine with modular hardware design for commercial deployment. Each alcohol bottle has its own ESP32-S3 module controlling pumps and sensors, coordinated by a Raspberry Pi 5 main controller.

### Hardware Architecture
- **Bottle Modules**: ESP32-S3 controllers with HC-SR04 sensors, ST7789 displays, DC pumps
- **Main Controller**: Raspberry Pi 5 with 5" HDMI display
- **Communication**: MQTT over WiFi between modules and main controller

### Software Stack
- **ESP32 Firmware**: Controls pumps, reads sensors, displays status
- **Raspberry Pi Services**: MQTT broker, Node-RED backend, Web dashboard
- **Frontend**: React-based dashboard (Lovable.dev + Supabase)
- **Deployment**: Docker-based for easy customer deployment

## Project Structure

The repository follows this directory structure:
- `esp32/` - ESP32 firmware for bottle modules
- `node-red/` - Node-RED flows and configuration
- `web/` - Web dashboard (React + Supabase)
- `deployment/` - Docker configs and deployment scripts
- `data/` - Recipe databases and configurations
- `docs/` - Documentation and guides

## Development Environment Setup

### Prerequisites
- Docker and Docker Compose (for services)
- PlatformIO or Arduino IDE (for ESP32 development)
- Node.js 18+ (for web dashboard)
- Git for version control

### ESP32 Development
```bash
# Using PlatformIO
pio run -t upload -e esp32s3
pio device monitor

# Flash ESP32 with new firmware
esptool.py --chip esp32s3 --port COM3 write_flash 0x0 firmware.bin
```

### Raspberry Pi Deployment
```bash
# Clone repository on Raspberry Pi
git clone https://github.com/sebastienlepoder/cocktail-machine.git
cd cocktail-machine/deployment

# Run automated setup
curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/scripts/setup-ultimate.sh | bash

# Start all services
docker-compose up -d
```

## Common Development Commands

### Docker Services Management
```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Restart specific service
docker-compose restart mosquitto
docker-compose restart nodered

# Update and redeploy
git pull
docker-compose down
docker-compose up -d --build
```

### MQTT Testing
```bash
# Subscribe to all topics
mosquitto_sub -h localhost -t "#" -v

# Publish test message
mosquitto_pub -h localhost -t "cocktail/module/test" -m "hello"

# Monitor specific module
mosquitto_sub -h localhost -t "cocktail/module/+/status" -v
```

### Node-RED Management
```bash
# Access Node-RED UI
# http://raspberry-pi-ip:1880

# Backup flows
docker exec nodered cat /data/flows.json > backup-flows.json

# Restore flows
docker cp flows.json nodered:/data/flows.json
docker-compose restart nodered
```

### Web Dashboard
```bash
# Development mode
cd web
npm install
npm run dev

# Build for production
npm run build

# Deploy to Raspberry Pi
npm run deploy
```

## Architecture Details

### Hardware Modules (ESP32-S3)
Each bottle module includes:
- **HC-SR04 Sensor**: Ultrasonic level detection
- **ST7789 Display**: 1.5" 240x280 SPI display for status
- **DC Pump**: Reversible pump for precise pouring
- **LED Strip**: Addressable LEDs for visual feedback (planned)
- **MQTT Client**: WiFi communication with main controller

### Communication Protocol
MQTT Topics Structure:
```
cocktail/module/{module_id}/status    # Module status updates
cocktail/module/{module_id}/level     # Bottle level readings
cocktail/module/{module_id}/pump      # Pump control commands
cocktail/module/{module_id}/display   # Display updates
cocktail/system/recipe                # Recipe execution
cocktail/system/status                # System-wide status
```

### Services Architecture
1. **Mosquitto MQTT Broker**: Central message broker
2. **Node-RED**: Business logic and automation flows
3. **Web Dashboard**: User interface (React + Supabase)
4. **PostgreSQL/Supabase**: Recipe and inventory database
5. **Update Service**: Git-based auto-updater

### Data Flow
1. ESP32 modules publish sensor data via MQTT
2. Node-RED processes data and controls pumps
3. Web dashboard displays status and accepts orders
4. Database stores recipes, history, and configurations

## Git Workflow

### Branch Strategy
- `master` or `main` - Production-ready code
- Feature branches for new functionality
- Use descriptive branch names: `feature/recipe-storage`, `fix/ingredient-calculation`

### Commit Conventions
```bash
# View current status
git status

# Stage and commit changes
git add .
git commit -m "Type: Brief description"

# Push changes
git push origin branch-name
```

## Project Roadmap Implementation Guide

When implementing roadmap items from README:
1. Define core cocktail data structures → Create models in `src/models/`
2. Implement recipe storage → Build database layer in `src/storage/`
3. Create ingredient management → Develop `src/ingredients/` module
4. Build mixing logic → Implement `src/mixing/` calculations
5. Develop user interface → Start with CLI in `src/cli/`

## Development Notes

### Current State
- Project initialized with basic structure
- No implementation code yet
- Python-focused development expected based on .gitignore

### Next Steps for Implementation
1. Create `requirements.txt` with initial dependencies
2. Set up basic project structure in `src/`
3. Implement first data models for cocktails and ingredients
4. Add unit tests in `tests/`
5. Create example recipes in `data/`

### Testing Strategy
- Unit tests for all business logic
- Integration tests for data persistence
- End-to-end tests for complete workflows
- Mock hardware interfaces if applicable

### Documentation
- Maintain docstrings for all public functions
- Update README.md as features are implemented
- Consider using Sphinx for API documentation in `docs/`
