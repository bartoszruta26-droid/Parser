# Aplikacja Android - Medical Daemon Client

Aplikacja Android obsługująca protokół komunikacyjny z daemonem zarządzającym danymi medycznymi.

## Funkcjonalności

### Obsługiwane typy danych:
1. **Dane pacjenta** (podmiotowe i przedmiotowe)
   - ID pacjenta
   - Źródło danych (lekarz, pielęgniarka)
   - Główne dolegliwości
   - Historia chorób
   - Leki
   - Alergie
   - Dowolne dodatkowe pola (extensible)

2. **Dane Biosensora**
   - Typy sensorów: ECG, EEG, EMG, EOG, PPG, SpO2, temperatura, wilgotność, ciśnienie, akcelerometr, żyroskop
   - Wartość pomiaru
   - Jednostka
   - Częstotliwość próbkowania
   - Jakość sygnału
   - Dowolne dodatkowe parametry (extensible)

3. **Dane Biofeedback**
   - Typy: HRV, GSR, temperatura, respiration, fale mózgowe (alpha, beta, theta, delta)
   - Wartość parametru
   - Jednostka
   - ID sesji treningowej
   - Wartość docelowa
   - Postęp (%)
   - Dowolne dodatkowe parametry (extensible)

### Architektura extensibility:
- Klasa `MedicalMessage` obsługuje dowolną liczbę pól w payload poprzez:
  - `Map<String, Object>` dla danych pacjenta
  - `Map<String, Object>` dla dodatkowych parametrów sensorów
  - Metodę `addPayloadField()` dla dowolnych rozszerzeń
- Łatwe dodawanie nowych typów danych bez modyfikacji istniejącego kodu

## Struktura projektu

```
app/src/main/java/com/example/parserapp/
├── MainActivity.java          # Główna aktywność z UI
├── ConfigActivity.java        # Konfiguracja połączenia
└── MedicalMessage.java        # Model wiadomości zgodny z protokołem
```

## Protokół komunikacyjny

Wiadomości są wysyłane w formacie JSON zgodnym ze schematem `medical-daemon-message.schema.json`:

```json
{
  "protocol": "1",
  "request_id": "uuid",
  "source": "frontend",
  "command": "patient.data|biosensor.data|biofeedback.data",
  "payload": { ... },
  "meta": {
    "timestamp_utc": "ISO8601",
    "correlation_id": "...",
    "patient_id": "...",
    "encryption": false
  }
}
```

## Kompilacja

```bash
cd /workspace/frontend/android
./build.sh
```

## Konfiguracja

Przed pierwszym użyciem należy skonfigurować połączenie z serwerem:
1. Otwórz menu → Konfiguracja
2. Wprowadź adres hosta, port, protokół i ścieżkę API
3. Zapisz konfigurację

## Przykłady użycia

### Wysyłanie danych pacjenta:
```java
Map<String, Object> data = new HashMap<>();
data.put("chief_complaint", "Ból głowy");
data.put("past_medical_history", jsonArray);

MedicalMessage message = new MedicalMessage(
    MedicalMessage.COMMAND_PATIENT_DATA, 
    MedicalMessage.SOURCE_ANDROID
);
message.setPatientData("PAT-001", "podmiotowe", "Dr Kowalski", data);
```

### Wysyłanie danych biosensora:
```java
Map<String, Object> params = new HashMap<>();
params.put("sample_rate", 250.0);
params.put("quality", 95.0);

MedicalMessage message = new MedicalMessage(
    MedicalMessage.COMMAND_BIOSENSOR_DATA, 
    MedicalMessage.SOURCE_BIOSENSOR
);
message.setBiosensorData("ecg-01", "ecg", 1.234, "mV", params);
```

### Wysyłanie danych biofeedback:
```java
Map<String, Object> params = new HashMap<>();
params.put("target_value", 70.0);
params.put("progress_percent", 78.0);
params.put("rmssd", 42.3);

MedicalMessage message = new MedicalMessage(
    MedicalMessage.COMMAND_BIOFEEDBACK_DATA, 
    MedicalMessage.SOURCE_BIOFEEDBACK
);
message.setBiofeedbackData("hrv-01", "hrv", 65.4, "ms", "SESSION-001", params);
```
