# ESP32 Bottle Module Firmware

This directory contains the firmware for the ESP32-S3 controllers that manage individual bottle modules.

## Hardware Components per Module

- **ESP32-S3** microcontroller
- **HC-SR04** ultrasonic sensor for liquid level detection
- **ST7789** 1.5" display (240x280) via SPI
- **DC Pump** reversible for precise pouring
- **LED Strip** (WS2812B) for visual feedback (planned)

## Pin Configuration

```cpp
// Display (ST7789)
#define TFT_CS   5
#define TFT_RST  4
#define TFT_DC   2
#define TFT_MOSI 23
#define TFT_SCLK 18

// HC-SR04 Sensor
#define TRIG_PIN 12
#define ECHO_PIN 14

// DC Pump Control
#define PUMP_PIN1 25
#define PUMP_PIN2 26
#define PUMP_PWM  27

// LED Strip (Future)
#define LED_PIN 32
```

## MQTT Topics

Each module publishes and subscribes to:

- `cocktail/module/{MODULE_ID}/status` - Module online/offline status
- `cocktail/module/{MODULE_ID}/level` - Current liquid level (0-100%)
- `cocktail/module/{MODULE_ID}/pump/command` - Pump control (subscribe)
- `cocktail/module/{MODULE_ID}/pump/status` - Pump status (publish)
- `cocktail/module/{MODULE_ID}/display` - Display update commands (subscribe)
- `cocktail/module/{MODULE_ID}/config` - Module configuration (subscribe)

## Building and Flashing

### Using PlatformIO

1. Install PlatformIO IDE or CLI
2. Open the project in PlatformIO
3. Configure WiFi credentials in `src/config.h`
4. Build and upload:
   ```bash
   pio run -t upload
   pio device monitor
   ```

### Using Arduino IDE

1. Install ESP32 board support
2. Install required libraries:
   - PubSubClient (MQTT)
   - TFT_eSPI (Display)
   - ArduinoJson
3. Configure board: ESP32-S3 Dev Module
4. Upload the sketch

## Configuration

Each module needs to be configured with:

1. **WiFi Credentials**
2. **MQTT Broker Address**
3. **Unique Module ID** (e.g., "vodka", "rum", "gin")
4. **Calibration values** for the ultrasonic sensor

## OTA Updates

The firmware supports Over-The-Air updates via:
- Arduino OTA for development
- HTTP OTA for production deployment

## Development Notes

- Use deep sleep when inactive to save power
- Implement watchdog timer for reliability
- Store calibration in SPIFFS/NVS
- Buffer MQTT messages if connection is lost
