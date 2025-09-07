# 🍹 Cocktail Machine - Node-RED Flows

This directory contains the Node-RED flows and configuration for the Cocktail Machine system.

## 📁 Directory Structure

```
node-red/
├── flows/
│   ├── flows.json          # Main Node-RED flows
│   └── flows_cred.json     # Encrypted credentials (auto-generated)
├── settings/
│   ├── settings.js         # Node-RED configuration
│   └── package.json        # Additional Node-RED modules
└── README.md               # This file
```

## 🔄 Flow Structure

The Node-RED flows are organized into separate tabs:

### 1. **Cocktail Machine Control** (`main-flow`)
- **MQTT Input**: Bottle status and level monitoring
- **Recipe Execution**: API endpoint for cocktail recipes
- **Status Processing**: Real-time bottle state management
- **Pump Control**: MQTT commands to bottle modules

### 2. **System Update Management** (`update-flow`)
- **Update Status API**: `/api/update/status` - Check for updates
- **Install Update API**: `/api/update/now` - Trigger updates
- **Auto-check Timer**: Checks for updates every 10 minutes
- **Update Logic**: Downloads and installs system updates

### 3. **Web Dashboard UI** (`dashboard-flow`)
- **Bottle Status Display**: Real-time bottle monitoring UI
- **Update Management UI**: Update buttons and status display
- **Auto-refresh Timers**: Keep UI updated

## 🌐 API Endpoints

Node-RED provides these API endpoints:

| Endpoint | Method | Description |
|----------|---------|-------------|
| `/api/recipe/execute` | POST | Execute a cocktail recipe |
| `/api/update/status` | GET | Check for system updates |
| `/api/update/now` | POST | Install available updates |
| `/ui` | GET | Node-RED Dashboard UI |
| `/admin` | GET | Node-RED Flow Editor (Admin) |

## 🔧 Configuration

### MQTT Topics

The flows monitor these MQTT topics:
- `cocktail/module/+/status` - Bottle module online/offline status
- `cocktail/module/+/level` - Bottle liquid level updates
- `cocktail/alerts/low_level` - Low level alerts (outgoing)
- `cocktail/module/+/pump/command` - Pump control commands (outgoing)

### Required Modules

Additional Node-RED modules (installed via `settings/package.json`):
- `node-red-dashboard` - Web UI dashboard
- `node-red-contrib-influxdb` - Database connectivity
- `node-red-contrib-ui-level` - Level indicators
- `node-red-contrib-throttle` - Rate limiting

## 🚀 Deployment

Node-RED flows are automatically deployed with the main system:

1. **Development**: Edit flows in this repository
2. **Deployment**: Flows are packaged and sent to Pi via deployment workflow
3. **Installation**: Pi receives and loads new flows automatically

## 💡 Usage

### Access the Dashboard
```bash
# Node-RED Dashboard (User Interface)
http://your-pi-ip:1880/ui

# Node-RED Flow Editor (Admin/Development)
http://your-pi-ip:1880/admin
```

### Check Update Status
```bash
curl http://your-pi-ip:1880/api/update/status
```

### Trigger Update
```bash
curl -X POST http://your-pi-ip:1880/api/update/now
```

### Execute Recipe
```bash
curl -X POST http://your-pi-ip:1880/api/recipe/execute \
  -H "Content-Type: application/json" \
  -d '{
    "id": "mojito",
    "name": "Mojito",
    "ingredients": [
      {"bottle_id": "bottle1", "amount": 50},
      {"bottle_id": "bottle2", "amount": 30}
    ]
  }'
```

## 🔄 Update Process

The Node-RED flows include a built-in update system:

1. **Auto-check**: Every 10 minutes, checks for new versions
2. **Manual check**: Via dashboard button or API
3. **Update notification**: Shows available updates in UI
4. **One-click install**: Installs updates via dashboard or API
5. **System restart**: Automatically restarts services after update

## 🛠️ Development

To modify the flows:

1. **Edit locally**: Modify `flows.json` in this repository
2. **Test changes**: Import flows into local Node-RED for testing
3. **Commit changes**: Push to dev repository
4. **Deploy**: Use deployment workflow to send to production

## 📊 Monitoring

The flows provide comprehensive monitoring:
- **Bottle Status**: Real-time online/offline status
- **Liquid Levels**: Current levels with low-level alerts
- **Recipe Execution**: Track cocktail preparation progress
- **System Health**: Update status and version information
- **MQTT Connectivity**: Monitor communication with bottle modules

---

*These flows form the core automation system for the Cocktail Machine, handling everything from bottle monitoring to system updates.*
