#ifndef CONFIG_H
#define CONFIG_H

// WiFi Configuration
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// MQTT Configuration
#define MQTT_SERVER "192.168.1.100"  // Raspberry Pi IP
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASSWORD ""

// Module Configuration
#define MODULE_ID "vodka"  // Change per module: vodka, rum, gin, etc.
#define MODULE_NAME "Vodka Bottle"

// Hardware Pin Definitions
// Display (ST7789) - SPI
#define TFT_CS      5
#define TFT_RST     4  // Reset pin (could connect to RST pin)
#define TFT_DC      2  // Data Command control pin
#define TFT_MOSI    23 // SPI MOSI
#define TFT_SCLK    18 // SPI Clock

// HC-SR04 Ultrasonic Sensor
#define TRIG_PIN    12
#define ECHO_PIN    14

// DC Pump Control
#define PUMP_PIN1   25  // Motor driver pin 1
#define PUMP_PIN2   26  // Motor driver pin 2
#define PUMP_PWM    27  // PWM speed control

// LED Strip (WS2812B) - Future feature
#define LED_PIN     32
#define NUM_LEDS    8

// System Configuration
#define BOTTLE_HEIGHT_MM      200  // Height of bottle in mm
#define BOTTLE_CAPACITY_ML    750  // Bottle capacity in ml
#define SENSOR_OFFSET_MM      20   // Distance from sensor to full level

// Pump Configuration
#define PUMP_ML_PER_SECOND    10.0  // Pump rate calibration
#define PUMP_MAX_TIME_MS      30000 // Maximum pump time safety

// Display Configuration
#define DISPLAY_WIDTH   240
#define DISPLAY_HEIGHT  280
#define DISPLAY_ROTATION 0

// Network Configuration
#define HOSTNAME_PREFIX "cocktail-"
#define OTA_PASSWORD "cocktail123"
#define OTA_PORT 3232

// MQTT Topics
#define TOPIC_STATUS    "cocktail/module/" MODULE_ID "/status"
#define TOPIC_LEVEL     "cocktail/module/" MODULE_ID "/level"
#define TOPIC_PUMP_CMD  "cocktail/module/" MODULE_ID "/pump/command"
#define TOPIC_PUMP_STATUS "cocktail/module/" MODULE_ID "/pump/status"
#define TOPIC_DISPLAY   "cocktail/module/" MODULE_ID "/display"
#define TOPIC_CONFIG    "cocktail/module/" MODULE_ID "/config"
#define TOPIC_HEARTBEAT "cocktail/module/" MODULE_ID "/heartbeat"

// Timing Configuration
#define WIFI_TIMEOUT_MS     30000
#define MQTT_RECONNECT_MS   5000
#define SENSOR_READ_MS      1000
#define HEARTBEAT_MS        30000
#define DISPLAY_UPDATE_MS   500

// Calibration defaults (can be overridden via MQTT)
#define LEVEL_CALIBRATION_EMPTY   200  // Distance reading when empty (mm)
#define LEVEL_CALIBRATION_FULL    50   // Distance reading when full (mm)

#endif
