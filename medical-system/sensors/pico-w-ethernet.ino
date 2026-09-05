// Przykładowy kod dla Raspberry Pi Pico W (Ethernet/WiFi)
// Wysyła dane przez HTTP server lub TCP socket

#include <WiFi.h>
#include <HTTPServer.h>
#include <ArduinoJson.h>
#include <DHT.h>

// Konfiguracja WiFi
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// Konfiguracja sensora
#define DHTPIN 15
#define DHTTYPE DHT11

DHT dht(DHTPIN, DHTTYPE);

// Serwer HTTP na porcie 80
WiFiServer server(80);

// Ostatnie odczyty
float lastTemp = 0.0;
float lastHumidity = 0.0;
unsigned long lastReadTime = 0;

void setup() {
  Serial.begin(115200);
  dht.begin();
  
  // Połączenie z WiFi
  Serial.print("Łączenie z WiFi");
  WiFi.begin(ssid, password);
  
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  
  Serial.println("\nPołączono!");
  Serial.print("Adres IP: ");
  Serial.println(WiFi.localIP());
  
  // Start serwera HTTP
  server.begin();
  Serial.println("Serwer HTTP uruchomiony na porcie 80");
  
  // Pierwszy odczyt
  readSensor();
}

void loop() {
  // Odczytuj sensor co 2 sekundy
  if (millis() - lastReadTime > 2000) {
    readSensor();
  }
  
  // Obsługuj połączenia HTTP
  handleHTTPClient();
  
  delay(10);
}

void readSensor() {
  float temperature = dht.readTemperature();
  float humidity = dht.readHumidity();
  
  if (!isnan(temperature) && !isnan(humidity)) {
    lastTemp = temperature;
    lastHumidity = humidity;
    lastReadTime = millis();
    
    Serial.printf("Temp: %.1f°C, Humidity: %.1f%%\n", lastTemp, lastHumidity);
  }
}

void handleHTTPClient() {
  WiFiClient client = server.available();
  
  if (client) {
    String request = client.readStringUntil('\r');
    client.readStringUntil('\n'); // Przeczytaj resztę nagłówków
    
    // Sprawdź ścieżkę żądania
    if (request.indexOf("/data") >= 0) {
      // Zwróć dane JSON
      String jsonResponse = getSensorJSON();
      
      client.println("HTTP/1.1 200 OK");
      client.println("Content-Type: application/json");
      client.println("Connection: close");
      client.println();
      client.println(jsonResponse);
    } else if (request.indexOf("/") >= 0) {
      // Strona statusu HTML
      client.println("HTTP/1.1 200 OK");
      client.println("Content-Type: text/html");
      client.println("Connection: close");
      client.println();
      client.println("<!DOCTYPE html><html><head><title>Pico Sensor</title></head><body>");
      client.println("<h1>Raspberry Pi Pico W - Sensor Data</h1>");
      client.printf("<p>Temperature: %.1f °C</p>", lastTemp);
      client.printf("<p>Humidity: %.1f %%</p>", lastHumidity);
      client.printf("<p>IP: %s</p>", WiFi.localIP().toString().c_str());
      client.println("<p><a href=\"/data\">Get JSON Data</a></p>");
      client.println("</body></html>");
    }
    
    delay(1);
    client.stop();
  }
}

String getSensorJSON() {
  StaticJsonDocument<256> doc;
  
  doc["sensor"] = "dht11";
  doc["temp"] = lastTemp;
  doc["humidity"] = lastHumidity;
  doc["unit_temp"] = "C";
  doc["unit_humidity"] = "%";
  doc["timestamp"] = millis();
  doc["ip"] = WiFi.localIP().toString();
  
  String output;
  serializeJson(doc, output);
  
  return output;
}
