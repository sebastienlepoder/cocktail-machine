#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <TFT_eSPI.h>
#include <SPIFFS.h>
#include <ArduinoOTA.h>
#include "config.h"

// Hardware objects
TFT_eSPI tft = TFT_eSPI();
WiFiClient espClient;
PubSubClient client(espClient);

// State variables
float currentLevel = 0.0;
bool pumpRunning = false;
unsigned long pumpStartTime = 0;
unsigned long lastSensorRead = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastDisplayUpdate = 0;
bool systemOnline = false;

// Calibration values (loaded from SPIFFS or defaults)
float levelCalEmpty = LEVEL_CALIBRATION_EMPTY;
float levelCalFull = LEVEL_CALIBRATION_FULL;

// Function declarations
void setupWiFi();
void setupMQTT();
void setupDisplay();
void setupOTA();
void readSensorLevel();
void updateDisplay();
void handlePumpCommand(const char* payload);
void publishStatus();
void publishLevel();
void publishHeartbeat();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void reconnectMQTT();

void setup() {
  Serial.begin(115200);
  Serial.println("🍹 Cocktail Machine - Bottle Module Starting...");
  
  // Initialize SPIFFS for configuration storage
  if (!SPIFFS.begin(true)) {
    Serial.println("SPIFFS Mount Failed");
  }
  
  // Initialize hardware pins
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(PUMP_PIN1, OUTPUT);
  pinMode(PUMP_PIN2, OUTPUT);
  pinMode(PUMP_PWM, OUTPUT);
  
  // Initialize pump as stopped
  digitalWrite(PUMP_PIN1, LOW);
  digitalWrite(PUMP_PIN2, LOW);
  analogWrite(PUMP_PWM, 0);
  
  // Setup components
  setupDisplay();
  setupWiFi();
  setupMQTT();
  setupOTA();
  
  Serial.println("✅ Module initialized successfully");
  systemOnline = true;
  
  // Initial sensor reading and status publish
  readSensorLevel();
  publishStatus();
  publishLevel();
}

void loop() {
  unsigned long currentTime = millis();
  
  // Handle OTA updates
  ArduinoOTA.handle();
  
  // Handle MQTT connection
  if (!client.connected()) {
    reconnectMQTT();
  }
  client.loop();
  
  // Read sensor periodically
  if (currentTime - lastSensorRead >= SENSOR_READ_MS) {
    readSensorLevel();
    publishLevel();
    lastSensorRead = currentTime;
  }
  
  // Update display periodically
  if (currentTime - lastDisplayUpdate >= DISPLAY_UPDATE_MS) {
    updateDisplay();
    lastDisplayUpdate = currentTime;
  }
  
  // Send heartbeat
  if (currentTime - lastHeartbeat >= HEARTBEAT_MS) {
    publishHeartbeat();
    lastHeartbeat = currentTime;
  }
  
  // Safety check for pump timeout
  if (pumpRunning && (currentTime - pumpStartTime > PUMP_MAX_TIME_MS)) {
    Serial.println("⚠️ Pump safety timeout - stopping pump");
    digitalWrite(PUMP_PIN1, LOW);
    digitalWrite(PUMP_PIN2, LOW);
    analogWrite(PUMP_PWM, 0);
    pumpRunning = false;
    
    // Publish pump stopped status
    StaticJsonDocument<200> doc;
    doc["status"] = "stopped";
    doc["reason"] = "safety_timeout";
    doc["timestamp"] = millis();
    
    char buffer[256];
    serializeJson(doc, buffer);
    client.publish(TOPIC_PUMP_STATUS, buffer);
  }
  
  delay(10); // Small delay to prevent watchdog issues
}

void setupWiFi() {
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);
  
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  WiFi.setHostname((String(HOSTNAME_PREFIX) + MODULE_ID).c_str());
  
  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    
    if (millis() - startTime > WIFI_TIMEOUT_MS) {
      Serial.println("\\n❌ WiFi connection timeout");
      return;
    }
  }
  
  Serial.println("\\n✅ WiFi connected");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
}

void setupMQTT() {
  client.setServer(MQTT_SERVER, MQTT_PORT);
  client.setCallback(mqttCallback);
  
  // Set buffer size for larger messages
  client.setBufferSize(1024);
}

void setupDisplay() {
  tft.init();
  tft.setRotation(DISPLAY_ROTATION);
  tft.fillScreen(TFT_BLACK);
  
  // Show startup screen
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.drawString("COCKTAIL", 40, 60);
  tft.drawString("MACHINE", 40, 90);
  
  tft.setTextSize(1);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.drawString(MODULE_NAME, 20, 140);
  tft.drawString("Initializing...", 20, 160);
}

void setupOTA() {
  ArduinoOTA.setHostname((String(HOSTNAME_PREFIX) + MODULE_ID).c_str());
  ArduinoOTA.setPassword(OTA_PASSWORD);
  ArduinoOTA.setPort(OTA_PORT);
  
  ArduinoOTA.onStart([]() {
    String type;
    if (ArduinoOTA.getCommand() == U_FLASH) {
      type = "sketch";
    } else {
      type = "filesystem";
    }
    Serial.println("Start updating " + type);
    
    // Show OTA screen
    tft.fillScreen(TFT_BLACK);
    tft.setTextColor(TFT_CYAN, TFT_BLACK);
    tft.setTextSize(2);
    tft.drawString("OTA UPDATE", 20, 100);
    tft.setTextSize(1);
    tft.drawString("Do not power off", 20, 140);
  });
  
  ArduinoOTA.onEnd([]() {
    Serial.println("\\nEnd");
  });
  
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    Serial.printf("Progress: %u%%\\r", (progress / (total / 100)));
    
    // Show progress on display
    int percent = progress / (total / 100);
    tft.drawRect(20, 160, 200, 20, TFT_WHITE);
    tft.fillRect(21, 161, (198 * percent) / 100, 18, TFT_GREEN);
    
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.drawString(String(percent) + "%", 100, 200);
  });
  
  ArduinoOTA.onError([](ota_error_t error) {
    Serial.printf("Error[%u]: ", error);
    if (error == OTA_AUTH_ERROR) {
      Serial.println("Auth Failed");
    } else if (error == OTA_BEGIN_ERROR) {
      Serial.println("Begin Failed");
    } else if (error == OTA_CONNECT_ERROR) {
      Serial.println("Connect Failed");
    } else if (error == OTA_RECEIVE_ERROR) {
      Serial.println("Receive Failed");
    } else if (error == OTA_END_ERROR) {
      Serial.println("End Failed");
    }
  });
  
  ArduinoOTA.begin();
  Serial.println("✅ OTA Ready");
}

void readSensorLevel() {
  // Trigger ultrasonic sensor
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  
  // Read echo duration
  long duration = pulseIn(ECHO_PIN, HIGH, 30000); // 30ms timeout
  
  if (duration == 0) {
    Serial.println("⚠️ Sensor timeout");
    return;
  }
  
  // Calculate distance in mm
  float distance = (duration * 0.034) / 2;
  
  // Convert to liquid level percentage
  float levelRange = levelCalEmpty - levelCalFull;
  float levelPercent = ((levelCalEmpty - distance) / levelRange) * 100.0;
  
  // Clamp to 0-100%
  levelPercent = max(0.0f, min(100.0f, levelPercent));
  
  currentLevel = levelPercent;
  
  Serial.printf("📊 Distance: %.1fmm, Level: %.1f%%\\n", distance, currentLevel);
}

void updateDisplay() {
  tft.fillScreen(TFT_BLACK);
  
  // Module name
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.drawString(MODULE_NAME, 20, 20);
  
  // Connection status
  tft.setTextSize(1);
  if (WiFi.status() == WL_CONNECTED && client.connected()) {
    tft.setTextColor(TFT_GREEN, TFT_BLACK);
    tft.drawString("🟢 ONLINE", 20, 50);
  } else {
    tft.setTextColor(TFT_RED, TFT_BLACK);
    tft.drawString("🔴 OFFLINE", 20, 50);
  }
  
  // Liquid level
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.drawString("LEVEL", 20, 80);
  
  // Level percentage
  tft.setTextSize(3);
  if (currentLevel > 50) {
    tft.setTextColor(TFT_GREEN, TFT_BLACK);
  } else if (currentLevel > 20) {
    tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  } else {
    tft.setTextColor(TFT_RED, TFT_BLACK);
  }
  tft.drawString(String((int)currentLevel) + "%", 20, 110);
  
  // Level bar
  int barWidth = 180;
  int barHeight = 20;
  int barX = 30;
  int barY = 160;
  
  tft.drawRect(barX, barY, barWidth, barHeight, TFT_WHITE);
  int fillWidth = (barWidth - 2) * (currentLevel / 100.0);
  
  uint16_t fillColor = TFT_GREEN;
  if (currentLevel <= 50) fillColor = TFT_YELLOW;
  if (currentLevel <= 20) fillColor = TFT_RED;
  
  tft.fillRect(barX + 1, barY + 1, fillWidth, barHeight - 2, fillColor);
  
  // Pump status
  tft.setTextSize(1);
  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  if (pumpRunning) {
    tft.drawString("🔄 PUMP RUNNING", 20, 200);
  } else {
    tft.drawString("⏹️ PUMP IDLE", 20, 200);
  }
  
  // IP Address
  tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
  tft.drawString(WiFi.localIP().toString(), 20, 250);
}

void handlePumpCommand(const char* payload) {
  StaticJsonDocument<200> doc;
  DeserializationError error = deserializeJson(doc, payload);
  
  if (error) {
    Serial.println("❌ Invalid pump command JSON");
    return;
  }
  
  String action = doc["action"];
  float duration = doc["duration_ms"] | 0;
  int speed = doc["speed"] | 255; // PWM value 0-255
  
  Serial.printf("🔄 Pump command: %s, duration: %.0fms, speed: %d\\n", 
                action.c_str(), duration, speed);
  
  if (action == "start") {
    if (!pumpRunning) {
      // Start pump
      digitalWrite(PUMP_PIN1, HIGH);
      digitalWrite(PUMP_PIN2, LOW);
      analogWrite(PUMP_PWM, speed);
      
      pumpRunning = true;
      pumpStartTime = millis();
      
      Serial.println("✅ Pump started");
      
      // Schedule stop if duration specified
      if (duration > 0) {
        // This will be handled in the main loop
      }
    }
  } else if (action == "stop") {
    // Stop pump
    digitalWrite(PUMP_PIN1, LOW);
    digitalWrite(PUMP_PIN2, LOW);
    analogWrite(PUMP_PWM, 0);
    
    pumpRunning = false;
    Serial.println("⏹️ Pump stopped");
  }
  
  // Publish pump status
  StaticJsonDocument<200> statusDoc;
  statusDoc["status"] = pumpRunning ? "running" : "stopped";
  statusDoc["speed"] = speed;
  statusDoc["timestamp"] = millis();
  
  char buffer[256];
  serializeJson(statusDoc, buffer);
  client.publish(TOPIC_PUMP_STATUS, buffer);
}

void publishStatus() {
  StaticJsonDocument<300> doc;
  doc["module_id"] = MODULE_ID;
  doc["module_name"] = MODULE_NAME;
  doc["status"] = systemOnline ? "online" : "offline";
  doc["wifi_connected"] = (WiFi.status() == WL_CONNECTED);
  doc["mqtt_connected"] = client.connected();
  doc["ip_address"] = WiFi.localIP().toString();
  doc["rssi"] = WiFi.RSSI();
  doc["uptime"] = millis();
  doc["free_heap"] = ESP.getFreeHeap();
  doc["timestamp"] = millis();
  
  char buffer[512];
  serializeJson(doc, buffer);
  client.publish(TOPIC_STATUS, buffer, true); // Retain message
  
  Serial.println("📡 Status published");
}

void publishLevel() {
  StaticJsonDocument<200> doc;
  doc["module_id"] = MODULE_ID;
  doc["level_percent"] = currentLevel;
  doc["level_ml"] = (currentLevel / 100.0) * BOTTLE_CAPACITY_ML;
  doc["timestamp"] = millis();
  
  char buffer[256];
  serializeJson(doc, buffer);
  client.publish(TOPIC_LEVEL, buffer);
}

void publishHeartbeat() {
  StaticJsonDocument<150> doc;
  doc["module_id"] = MODULE_ID;
  doc["timestamp"] = millis();
  doc["uptime"] = millis();
  
  char buffer[200];
  serializeJson(doc, buffer);
  client.publish(TOPIC_HEARTBEAT, buffer);
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // Convert payload to string
  char message[length + 1];
  memcpy(message, payload, length);
  message[length] = '\\0';
  
  Serial.printf("📥 MQTT [%s]: %s\\n", topic, message);
  
  if (strcmp(topic, TOPIC_PUMP_CMD) == 0) {
    handlePumpCommand(message);
  } else if (strcmp(topic, TOPIC_DISPLAY) == 0) {
    // Handle display commands (future feature)
  } else if (strcmp(topic, TOPIC_CONFIG) == 0) {
    // Handle configuration updates (future feature)
  }
}

void reconnectMQTT() {
  static unsigned long lastReconnectAttempt = 0;
  unsigned long currentTime = millis();
  
  if (currentTime - lastReconnectAttempt < MQTT_RECONNECT_MS) {
    return; // Don't try too often
  }
  
  lastReconnectAttempt = currentTime;
  
  if (WiFi.status() != WL_CONNECTED) {
    return; // Don't try MQTT if WiFi is down
  }
  
  Serial.print("Attempting MQTT connection...");
  
  String clientId = String(HOSTNAME_PREFIX) + MODULE_ID;
  
  if (client.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD)) {
    Serial.println(" connected!");
    
    // Subscribe to command topics
    client.subscribe(TOPIC_PUMP_CMD);
    client.subscribe(TOPIC_DISPLAY);
    client.subscribe(TOPIC_CONFIG);
    
    // Publish online status
    publishStatus();
    
    Serial.println("✅ MQTT connected and subscribed");
  } else {
    Serial.print(" failed, rc=");
    Serial.print(client.state());
    Serial.println(". Retrying...");
  }
}
