# Schematyczny protokół komunikacji dla Medical Data Daemon

## 1. Przegląd architektury

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WARSTWA KLIENTÓW                                  │
├──────────────┬──────────────┬──────────────┬──────────────┬────────────────┤
│   WebUI      │    TUI       │    Mobile    │  Biosensor   │  Biofeedback   │
│   (Apache)   │   (Bash)     │   (Android)  │  Devices     │  Devices       │
└──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┴───────┬────────┘
       │              │              │              │               │
       └──────────────┴──────────────┴──────────────┴───────────────┘
                                │
                    COMMAND_FIFO (Unix FIFO)
                    /tmp/medical-daemon/commands.fifo
                                │
       ┌────────────────────────▼────────────────────────┐
       │         MEDICAL DATA MANAGEMENT DAEMON          │
       │         (medical-daemon.sh)                     │
       ├─────────────────────────────────────────────────┤
       │  Command Handler:                               │
       │  - ping, status, shutdown                       │
       │  - patient.data (podmiotowe/przedmiotowe)       │
       │  - biosensor.data (ECG, EEG, EMG, SpO2, itp.)   │
       │  - biofeedback.data (HRV, GSR, fale mózgowe)    │
       │  - medical.message (FHIR, HL7v2 auto-detect)    │
       │  - swarm.sensor/effector/forward                │
       └─────────────────────────────────────────────────┘
                                │
       ┌────────────────────────┼────────────────────────┐
       │                        │                        │
       ▼                        ▼                        ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ Queue Files     │   │ Response Files  │   │ Log Files       │
│ (JSONL)         │   │ (JSON)          │   │ (text)          │
├─────────────────┤   ├─────────────────┤   ├─────────────────┤
│ patient-data    │   │ responses/      │   │ daemon.log      │
│ biosensor-      │   │ {request_id}.   │   │                 │
│ events.jsonl    │   │ json            │   │                 │
│ biofeedback-    │   │                 │   │                 │
│ events.jsonl    │   │                 │   │                 │
│ fhir-messages   │   │                 │   │                 │
│ .jsonl          │   │                 │   │                 │
│ hl7-messages    │   │                 │   │                 │
│ .jsonl          │   │                 │   │                 │
│ swarm-events    │   │                 │   │                 │
│ .jsonl          │   │                 │   │                 │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

## 2. Format wiadomości żądania

### Struktura podstawowa (przez COMMAND_FIFO)

Format: `request_id|source|command|payload_json`

Przykład:
```
req-001-20260105-143022|biosensor-device|biosensor.data|{"sensor_id":"ecg-01","sensor_type":"ecg","value":1.2,"unit":"mV","timestamp":"2026-01-05T14:30:22Z"}
```

### Pola wiadomości:

| Pole | Typ | Opis | Przykład |
|------|-----|------|----------|
| request_id | string | Unikalny identyfikator żądania | `req-001-20260105-143022` |
| source | string | Źródło wiadomości | `biosensor-device`, `webui`, `fhir-server` |
| command | string | Polecenie dla daemona | `biosensor.data`, `patient.data`, `medical.fhir` |
| payload | JSON | Dane biznesowe polecenia | Zobacz sekcję 3 |

## 3. Typy poleceń i payload

### 3.1. patient.data - Dane pacjenta

**Podmiotowe dane (wywiad):**
```json
{
  "patient_id": "PAT-2026-00123",
  "data_type": "podmiotowe",
  "timestamp": "2026-01-05T14:30:00Z",
  "provider": "Dr Jan Kowalski",
  "data": {
    "chief_complaint": "Ból w klatce piersiowej",
    "history_present_illness": "Ból pojawił się 2 godziny temu...",
    "past_medical_history": ["nadciśnienie", "cukrzyca typu 2"],
    "medications": ["Metformin 500mg", "Amlodipine 5mg"],
    "allergies": ["penicylina"],
    "family_history": ["choroba wieńcowa u ojca"],
    "social_history": "Palenie: 10 papierosów/dzień przez 20 lat"
  }
}
```

**Przedmiotowe dane (badanie):**
```json
{
  "patient_id": "PAT-2026-00123",
  "data_type": "przedmiotowe",
  "timestamp": "2026-01-05T14:35:00Z",
  "provider": "Pielęgniarka Anna Nowak",
  "data": {
    "vital_signs": {
      "blood_pressure": "140/90 mmHg",
      "heart_rate": 85,
      "respiratory_rate": 18,
      "temperature": 36.6,
      "spo2": 98
    },
    "physical_exam": {
      "general": "Pacjent przytomny, zorientowany",
      "cardiovascular": "Szmer skurczowy nad koniuszkiem",
      "respiratory": "Szmer pęcherzykowy obustronnie",
      "neurological": "Bez ogniskowych objawów neurologicznych"
    }
  }
}
```

### 3.2. biosensor.data - Dane z czujników biosensor

**ECG (Elektrokardiogram):**
```json
{
  "sensor_id": "ecg-device-01",
  "sensor_type": "ecg",
  "value": 1.234,
  "unit": "mV",
  "timestamp": "2026-01-05T14:30:22.123Z",
  "sample_rate": 250,
  "quality": 95,
  "lead": "II",
  "patient_id": "PAT-2026-00123"
}
```

**EEG (Elektroencefalogram):**
```json
{
  "sensor_id": "eeg-device-01",
  "sensor_type": "eeg",
  "value": 45.6,
  "unit": "μV",
  "timestamp": "2026-01-05T14:30:22.456Z",
  "sample_rate": 500,
  "quality": 88,
  "channel": "Fp1",
  "frequency_band": "alpha",
  "patient_id": "PAT-2026-00123"
}
```

**SpO2 (Saturation):**
```json
{
  "sensor_id": "spo2-sensor-01",
  "sensor_type": "spo2",
  "value": 98,
  "unit": "%",
  "timestamp": "2026-01-05T14:30:23Z",
  "sample_rate": 1,
  "quality": 99,
  "pulse_rate": 72,
  "patient_id": "PAT-2026-00123"
}
```

### 3.3. biofeedback.data - Dane z czujników biofeedback

**HRV (Heart Rate Variability):**
```json
{
  "sensor_id": "hrv-monitor-01",
  "feedback_type": "hrv",
  "value": 65.4,
  "unit": "ms",
  "timestamp": "2026-01-05T14:30:25Z",
  "session_id": "SESSION-2026-001",
  "target_value": 70,
  "progress_percent": 78,
  "rmssd": 42.3,
  "sdnn": 58.7,
  "lf_hf_ratio": 2.1,
  "patient_id": "PAT-2026-00123"
}
```

**GSR (Galvanic Skin Response):**
```json
{
  "sensor_id": "gsr-sensor-01",
  "feedback_type": "gsr",
  "value": 12.5,
  "unit": "μS",
  "timestamp": "2026-01-05T14:30:26Z",
  "session_id": "SESSION-2026-001",
  "target_value": 10,
  "progress_percent": 65,
  "patient_id": "PAT-2026-00123"
}
```

**Fale mózgowe (Neurofeedback):**
```json
{
  "sensor_id": "neurofeedback-01",
  "feedback_type": "alpha_waves",
  "value": 15.2,
  "unit": "μV",
  "timestamp": "2026-01-05T14:30:27Z",
  "session_id": "SESSION-2026-001",
  "target_value": 18,
  "progress_percent": 82,
  "channel": "Pz",
  "patient_id": "PAT-2026-00123"
}
```

### 3.4. medical.fhir - Wiadomość FHIR

```json
{
  "resourceType": "Bundle",
  "type": "message",
  "identifier": {
    "system": "urn:medical-daemon:message",
    "value": "msg-2026-001"
  },
  "entry": [
    {
      "resource": {
        "resourceType": "MessageHeader",
        "eventCoding": {
          "system": "http://terminology.hl7.org/CodeSystem/v2-0003",
          "code": "ORU^R01"
        },
        "source": {
          "name": "biosensor-gateway"
        }
      }
    },
    {
      "resource": {
        "resourceType": "Observation",
        "id": "ecg-observation-001",
        "status": "final",
        "category": [
          {
            "coding": [
              {
                "system": "http://terminology.hl7.org/CodeSystem/observation-category",
                "code": "vital-signs"
              }
            ]
          }
        ],
        "code": {
          "coding": [
            {
              "system": "http://loinc.org",
              "code": "11524-6",
              "display": "EKG study"
            }
          ]
        },
        "subject": {
          "reference": "Patient/PAT-2026-00123"
        },
        "effectiveDateTime": "2026-01-05T14:30:22Z",
        "valueQuantity": {
          "value": 1.234,
          "unit": "mV"
        }
      }
    }
  ]
}
```

### 3.5. medical.hl7 - Wiadomość HL7v2

```json
{
  "message_type": "ORU^R01",
  "raw_message": "MSH|^~\\&|SENDING_APP|SENDING_FACILITY|RECEIVING_APP|RECEIVING_FACILITY|20260105143022||ORU^R01|MSG001|P|2.5\rPID|1||PAT-2026-00123^^^MEDICAL^MR||TEST^PATIENT||19800101|M\rOBR|1||ORDER001|ECG^Electrocardiogram^LNR\rOBX|1|NM|ECG^EKG Lead II||1.234|mV|||||F",
  "parsed_segments": {
    "MSH": {...},
    "PID": {...},
    "OBR": {...},
    "OBX": {...}
  }
}
```

## 4. Format odpowiedzi

Odpowiedzi są zapisywane w plikach: `/tmp/medical-daemon/responses/{request_id}.json`

### Odpowiedź sukcesu:
```json
{
  "protocol": "1",
  "request_id": "req-001-20260105-143022",
  "status": "accepted",
  "code": "BIOSENSOR_DATA",
  "message": "Biosensor data accepted",
  "payload": {
    "queued": true,
    "event_file": "/tmp/medical-daemon/biosensor-events.jsonl"
  }
}
```

### Odpowiedź błędu:
```json
{
  "protocol": "1",
  "request_id": "req-002-20260105-143025",
  "status": "error",
  "code": "UNKNOWN_COMMAND",
  "message": "Unsupported command: invalid.cmd"
}
```

## 5. Sekwencje komunikacji

### 5.1. Rejestracja danych biosensora

```
Client                              Daemon
  │                                   │
  │─── req-001|biosensor-device ─────>│
  │    |biosensor.data|{...}          │
  │                                   │ (walidacja)
  │                                   │ (zapis do queue)
  │<── {"status":"accepted", ...} ────│
  │                                   │
  │                          [biosensor-events.jsonl]
  │                          {"timestamp_utc":"...",
  │                           "node":"local",
  │                           "source":"biosensor-device",
  │                           "command":"biosensor.data",
  │                           "payload":{...}}
```

### 5.2. Przetwarzanie wiadomości FHIR

```
FHIR Client                       Daemon                      Backend
    │                               │                            │
    │─── req-fhir-001|fhir-server ─>│                            │
    │    |medical.fhir|{Bundle}     │                            │
    │                               │ (auto-detect FHIR)         │
    │                               │ (zapis do fhir-queue)      │
    │<── {"status":"accepted"} ────>│                            │
    │                               │                            │
    │                               │──────── job.trigger ──────>│
    │                               │                            │ (parsowanie)
    │                               │                            │ (integracja z EHR)
```

### 5.3. Sesja biofeedback z pętlą sprzężenia zwrotnego

```
Biofeedback Device    Daemon         Analytics      Feedback Device
       │                │                │                │
       │── session.start ──────────────>│                │
       │                │                │                │
       │── data.stream ─>│                │                │
       │                │ (real-time)    │                │
       │                │───────────────>│ (analiza HRV)  │
       │                │                │                │
       │                │<───────────────│ (target update)│
       │<── feedback.set ─────────────────────────────────│
       │                │                │                │
       │── session.end ─────────────────>│ (raport)       │
```

## 6. Kolejki zdarzeń (Queue Files)

Wszystkie dane są kolejkowane w formacie JSONL (JSON Lines):

### patient-data.jsonl
```json
{"timestamp_utc":"2026-01-05T14:30:00Z","node":"local","role":"main","source":"webui","command":"patient.data","payload":{"patient_id":"PAT-001","data_type":"podmiotowe",...}}
{"timestamp_utc":"2026-01-05T14:35:00Z","node":"local","role":"main","source":"webui","command":"patient.data","payload":{"patient_id":"PAT-001","data_type":"przedmiotowe",...}}
```

### biosensor-events.jsonl
```json
{"timestamp_utc":"2026-01-05T14:30:22Z","node":"local","role":"main","source":"biosensor-device","command":"biosensor.data","payload":{"sensor_id":"ecg-01","sensor_type":"ecg","value":1.234,...}}
```

### biofeedback-events.jsonl
```json
{"timestamp_utc":"2026-01-05T14:30:25Z","node":"local","role":"main","source":"biofeedback-device","command":"biofeedback.data","payload":{"sensor_id":"hrv-01","feedback_type":"hrv","value":65.4,...}}
```

### fhir-messages.jsonl
```json
{"timestamp_utc":"2026-01-05T14:40:00Z","node":"local","role":"main","source":"fhir-server","command":"medical.fhir","payload":{"resourceType":"Bundle",...}}
```

### hl7-messages.jsonl
```json
{"timestamp_utc":"2026-01-05T14:45:00Z","node":"local","role":"main","source":"hl7-system","command":"medical.hl7","payload":{"message_type":"ORU^R01","raw_message":"MSH|..."}}
```

## 7. Integracja z Raspberry Pi Swarm

### Topologia sieci:
```
                    ┌─────────────────┐
                    │   RPi Main      │
                    │   192.168.1.10  │
                    │   (koordynator) │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼────────┐  ┌───────▼────────┐  ┌───────▼────────┐
│  RPi Worker 01 │  │  RPi Worker 02 │  │  RPi Worker 03 │
│  192.168.1.11  │  │  192.168.1.12  │  │  192.168.1.13  │
│  (biosensors)  │  │ (biofeedback)  │  │  (interface)   │
└────────────────┘  └────────────────┘  └────────────────┘
```

### Forwarding między węzłami:
```json
{
  "protocol": "1",
  "request_id": "fwd-001",
  "source": "rpi-worker-01",
  "command": "swarm.forward",
  "payload": {
    "target_node": "rpi-main",
    "original_command": "biosensor.data",
    "original_payload": {...}
  }
}
```

## 8. Bezpieczeństwo i zgodność

### Wymagania HIPAA/GDPR:
- Szyfrowanie danych pacjentów w spoczynku
- Logowanie dostępu do danych medycznych
- Automatyczne usuwanie danych po okresie retencji
- Anonimizacja danych do celów badawczych

### Konfiguracja bezpieczeństwa:
```bash
# W pliku daemon.conf
PATIENT_DATA_ENCRYPTION="true"
PATIENT_DATA_RETENTION_DAYS="365"
LOG_ACCESS_EVENTS="true"
AUDIT_TRAIL_ENABLED="true"
```

## 9. Komendy systemowe

| Komenda | Opis | Przykład użycia |
|---------|------|-----------------|
| `ping` | Test połączenia | `echo "req-1|cli|ping|{}" > commands.fifo` |
| `status` | Status daemona | `echo "req-2|cli|status|{}" > commands.fifo` |
| `shutdown` | Bezpieczne zatrzymanie | `echo "req-3|admin|shutdown|{}" > commands.fifo` |
| `frontend.event` | Zdarzenie z UI | `echo "req-4|webui|frontend.event|{...}" > commands.fifo` |
| `backend.job` | Zadanie backendowe | `echo "req-5|api|backend.job|{...}" > commands.fifo` |

## 10. Przykłady użycia

### Wysyłanie danych ECG:
```bash
#!/bin/bash
REQUEST_ID="ecg-$(date +%Y%m%d-%H%M%S)-$$"
COMMAND_FIFO="/tmp/medical-daemon/commands.fifo"

PAYLOAD='{
  "sensor_id": "ecg-01",
  "sensor_type": "ecg",
  "value": 1.234,
  "unit": "mV",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "sample_rate": 250,
  "quality": 95,
  "patient_id": "PAT-2026-00123"
}'

echo "${REQUEST_ID}|biosensor-device|biosensor.data|${PAYLOAD}" > "$COMMAND_FIFO"

# Odczyt odpowiedzi
sleep 0.5
cat "/tmp/medical-daemon/responses/${REQUEST_ID}.json"
```

### Wysyłanie danych wywiadu (podmiotowe):
```bash
#!/bin/bash
REQUEST_ID="anamnesis-$(date +%Y%m%d-%H%M%S)-$$"
COMMAND_FIFO="/tmp/medical-daemon/commands.fifo"

PAYLOAD='{
  "patient_id": "PAT-2026-00123",
  "data_type": "podmiotowe",
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "provider": "Dr Jan Kowalski",
  "data": {
    "chief_complaint": "Ból głowy",
    "history_present_illness": "Od 3 dni...",
    "past_medical_history": ["nadciśnienie"],
    "medications": ["Ramipril 5mg"]
  }
}'

echo "${REQUEST_ID}|webui|patient.data|${PAYLOAD}" > "$COMMAND_FIFO"
```

### Integracja z FHIR Server:
```bash
#!/bin/bash
REQUEST_ID="fhir-$(date +%Y%m%d-%H%M%S)-$$"
COMMAND_FIFO="/tmp/medical-daemon/commands.fifo"

PAYLOAD='{
  "resourceType": "Bundle",
  "type": "message",
  "entry": [{
    "resource": {
      "resourceType": "Observation",
      "status": "final",
      "code": {"coding": [{"system": "http://loinc.org", "code": "8867-4", "display": "Heart rate"}]},
      "valueQuantity": {"value": 72, "unit": "beats/minute"},
      "subject": {"reference": "Patient/PAT-2026-00123"}
    }
  }]
}'

echo "${REQUEST_ID}|fhir-server|medical.fhir|${PAYLOAD}" > "$COMMAND_FIFO"
```
