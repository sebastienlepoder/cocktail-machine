# 🍹 Cocktail Machine - Automated Cocktail Dispensing System

A professional-grade automated cocktail machine with modular bottle controllers, centralized management, and remote update capabilities.

## 🎯 Overview

This project implements a complete cocktail dispensing system using ESP32 microcontrollers for individual bottle control and a Raspberry Pi 5 as the main controller. The system features automatic recipe execution, real-time inventory tracking, and a modern web interface.

## ✨ Features

### Hardware
- **Modular Design**: Each bottle has its own ESP32-S3 controller
- **Precise Dispensing**: Reversible DC pumps for accurate pouring
- **Level Monitoring**: Ultrasonic sensors track liquid levels
- **Visual Feedback**: Individual displays show bottle status
- **Wireless Communication**: MQTT over WiFi for all modules

### Software
- **Docker Deployment**: All services containerized for easy deployment
- **Auto-Updates**: Git-based automatic update system
- **Web Dashboard**: Modern React interface with Supabase backend
- **Node-RED Automation**: Flexible recipe and control logic
- **Remote Management**: Full system control via web interface
- **Backup System**: Automatic daily backups with rotation

## 🏗️ Architecture

```
cocktail-machine/
├── esp32/              # ESP32 firmware for bottle modules
├── node-red/           # Node-RED flows and automation
├── web/                # Web dashboard (React + Supabase)
├── deployment/         # Docker configs and setup scripts
│   ├── docker-compose.yml
│   ├── setup-raspberry-pi.sh
│   ├── mosquitto/      # MQTT broker configuration
│   ├── updater/        # Auto-update service
│   └── nginx/          # Reverse proxy config
├── data/               # Recipe databases
├── docs/               # Documentation
├── DEPLOYMENT.md       # Deployment guide
├── WARP.md            # Warp terminal guide
└── README.md          # This file
```

## 🚀 Quick Start

### For Raspberry Pi Deployment

```bash
# One-line installation
curl -fsSL https://raw.githubusercontent.com/sebastienlepoder/cocktail-deploy/main/scripts/setup-raspberry-pi.sh | bash
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions.

### Hardware Components Required

#### Per Bottle Module:
- ESP32-S3 Development Board
- HC-SR04 Ultrasonic Sensor
- Waveshare 1.5" ST7789 Display (240x280)
- Reversible DC Pump
- Power supply (5V/12V depending on pump)

#### Main Controller:
- Raspberry Pi 5 (4GB+ RAM)
- 5" HDMI Display
- MicroSD Card (32GB+)
- Network connection

## 💻 Development

### ESP32 Firmware Development

```bash
cd esp32
# Configure WiFi and MQTT settings in config.h
pio run -t upload
```

### Local Testing with Docker

```bash
cd deployment
docker-compose up -d
```

Access services:
- Node-RED: http://localhost:1880
- Web Dashboard: http://localhost:3000
- MQTT: localhost:1883

## 📡 System Communication

### MQTT Topics

```
cocktail/module/{id}/status     # Module online/offline
cocktail/module/{id}/level      # Liquid level (0-100%)
cocktail/module/{id}/pump       # Pump control
cocktail/system/recipe          # Recipe execution
cocktail/system/status          # System status
```

## 🔄 Updates & Maintenance

### Automatic Updates

The system automatically checks for updates every hour and applies them without downtime.

### Manual Update

```bash
/home/pi/cocktail-machine/update.sh
```

### Backup

```bash
/home/pi/cocktail-machine/backup.sh
```

## 📊 Services

| Service | Port | Description |
|---------|------|-------------|
| Web Dashboard | 3000 | User interface |
| Node-RED | 1880 | Automation flows |
| MQTT Broker | 1883 | Device communication |
| PostgreSQL | 5432 | Database |
| Nginx | 80/443 | Reverse proxy |

## 🌟 Roadmap

- [x] Docker deployment infrastructure
- [x] Automated setup scripts
- [x] Git-based update system
- [ ] ESP32 OTA updates
- [ ] Recipe marketplace
- [ ] Mobile app
- [ ] Voice control integration
- [ ] Advanced analytics dashboard

## 🛠️ Troubleshooting

See [DEPLOYMENT.md](DEPLOYMENT.md#troubleshooting) for common issues and solutions.

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## 📞 Support

- **Documentation**: See [DEPLOYMENT.md](DEPLOYMENT.md)
- **Issues**: [GitHub Issues](https://github.com/sebastienlepoder/cocktail-machine/issues)
- **Discussions**: [GitHub Discussions](https://github.com/sebastienlepoder/cocktail-machine/discussions)

## 👥 Author

**Sebastien Le Poder**
- GitHub: [@sebastienlepoder](https://github.com/sebastienlepoder)

---

<p align="center">
  <i>Crafting perfect cocktails, one byte at a time! 🍹✨</i>
</p>
