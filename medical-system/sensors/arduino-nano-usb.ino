// Przykładowy kod dla Arduino Nano (USB)
// Wysyła dane z sensora przez port szeregowy

#include <DHT.h>

#define DHTPIN 2
#define DHTTYPE DHT11

DHT dht(DHTPIN, DHTTYPE);

void setup() {
  Serial.begin(9600);
  dht.begin();
  
  // Poczekaj na stabilizację
  delay(1000);
  
  Serial.println("{\"status\":\"initialized\",\"sensor\":\"dht11\"}");
}

void loop() {
  // Odczytaj temperaturę i wilgotność
  float temperature = dht.readTemperature();
  float humidity = dht.readHumidity();
  
  // Sprawdź czy odczyt się powiódł
  if (isnan(temperature) || isnan(humidity)) {
    Serial.println("{\"error\":\"read_failed\"}");
    delay(2000);
    return;
  }
  
  // Wyślij dane w formacie JSON
  Serial.print("{\"temp\":");
  Serial.print(temperature);
  Serial.print(",\"humidity\":");
  Serial.print(humidity);
  Serial.print(",\"timestamp\":");
  Serial.print(millis());
  Serial.println("}");
  
  // Czekaj 2 sekundy przed następnym odczytem
  delay(2000);
}
