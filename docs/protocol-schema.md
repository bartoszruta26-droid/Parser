# Schemat protokołu komunikacji

Ten dokument definiuje wspólny kontrakt komunikacyjny dla daemona, frontendów, backendów i integracji zewnętrznych. Szkielet zakłada jeden logiczny model wiadomości oraz kilka sposobów serializacji albo ekspozycji: `json`, `api`, `csv` i profil medyczny. Implementacja referencyjna pozostaje oparta o Bash i aplikacje linuksowe, bez Pythona w daemonie ani klientach lokalnych.

## 1. Cele protokołu

- Jeden kontrakt dla CLI, TUI, GUI, WebUI, backendów i integracji zewnętrznych.
- Możliwość wyboru formatu transportowego bez zmiany logiki daemona.
- Brak zależności od Pythona w runtime daemona, klientach lokalnych i narzędziach instalacyjnych.
- Jednoznaczne pola identyfikujące żądanie, źródło, komendę, payload i metadane.
- Wsparcie dla prostych systemów embedded oraz integracji branżowych, w tym medycznych.
- Możliwość wersjonowania i zachowania kompatybilności wstecznej.

## 2. Opcje formatu

| Opcja | Zastosowanie | Format główny | Przykładowy content type |
| --- | --- | --- | --- |
| `json` | Lokalna komunikacja daemon/frontend/backend, pliki odpowiedzi, kolejki | JSON object | `application/json` |
| `api` | HTTP/REST lub wewnętrzne endpointy WebUI/backend | JSON request/response przez HTTP | `application/json` |
| `csv` | Import/eksport tabelaryczny, integracje z arkuszami, proste wsady | CSV z kolumną `payload_json` | `text/csv` |
| `medical` | Integracja z systemami medycznymi | profil HL7 v2 lub FHIR-like JSON | `application/hl7-v2`, `application/fhir+json` |

## 3. Kanoniczny model wiadomości

Każdy format powinien dać się zmapować do modelu kanonicznego:

| Pole | Wymagane | Typ | Opis |
| --- | --- | --- | --- |
| `protocol` | tak | string | Wersja kontraktu, np. `1`. |
| `request_id` | tak | string | Unikalny identyfikator żądania generowany po stronie klienta. |
| `source` | tak | enum | Źródło: `cli`, `tui`, `gui`, `webui`, `frontend`, `backend`, `api`, `medical`, `test`. |
| `command` | tak | enum/string | Komenda daemona, np. `ping`, `status`, `frontend.event`, `backend.job`, `medical.message`, `shutdown`. |
| `payload` | tak | object/string | Dane biznesowe komendy. W CSV przechowywane jako JSON w kolumnie `payload_json`. |
| `meta.timestamp_utc` | zalecane | datetime | Czas utworzenia wiadomości w UTC. |
| `meta.correlation_id` | zalecane | string | Identyfikator śledzenia procesu przekrojowego. |
| `meta.content_type` | opcjonalne | string | Format serializacji albo typ dokumentu źródłowego. |
| `meta.schema` | opcjonalne | string | Nazwa profilu walidacyjnego. |

Schemat JSON znajduje się w `protocol/schemas/daemon-message.schema.json`. Założenia wykonawcze Bash/Linux opisuje `docs/protocol-linux-bash.md`.

## 4. Opcja `json`

JSON jest formatem domyślnym dla nowych integracji. Przykład żądania znajduje się w `protocol/examples/request.json`, a przykład odpowiedzi w `protocol/examples/response.json`.

Minimalne żądanie:

```json
{
  "protocol": "1",
  "request_id": "cli-1710000000-1234",
  "source": "cli",
  "command": "status",
  "payload": {}
}
```

Minimalna odpowiedź:

```json
{
  "protocol": "1",
  "request_id": "cli-1710000000-1234",
  "status": "ok",
  "code": "STATUS",
  "message": "Daemon is running",
  "payload": {}
}
```

## 5. Opcja `api`

Opcja `api` opisuje ekspozycję tego samego kontraktu przez HTTP. Rekomendowany minimalny zestaw endpointów:

| Metoda | Ścieżka | Cel |
| --- | --- | --- |
| `GET` | `/api/v1/status` | Odczyt statusu daemona. |
| `POST` | `/api/v1/commands` | Wysłanie dowolnej komendy zgodnej z modelem kanonicznym. |
| `POST` | `/api/v1/frontend-events` | Wysłanie zdarzenia frontendu. |
| `POST` | `/api/v1/backend-jobs` | Wysłanie zadania backendowego. |
| `POST` | `/api/v1/medical/messages` | Wysłanie komunikatu w profilu medycznym. |

Rekomendowane kody odpowiedzi API:

| HTTP | Kod protokołu | Znaczenie |
| --- | --- | --- |
| `200` | `OK` / `STATUS` / `PONG` | Operacja zakończona poprawnie. |
| `202` | `ACCEPTED` | Zadanie przyjęte asynchronicznie. |
| `400` | `INVALID_REQUEST` | Błędna struktura żądania. |
| `401` | `UNAUTHORIZED` | Brak autoryzacji. |
| `403` | `FORBIDDEN` | Brak uprawnień do komendy. |
| `404` | `UNKNOWN_COMMAND` | Nieznana komenda albo endpoint. |
| `408` | `TIMEOUT` | Przekroczony czas oczekiwania. |
| `503` | `DAEMON_UNAVAILABLE` | Daemon albo transport lokalny jest niedostępny. |

## 6. Opcja `csv`

CSV jest przeznaczony do prostych importów i eksportów. Wymagany nagłówek:

```csv
protocol,request_id,source,command,payload_json,timestamp_utc,correlation_id
```

Zasady:

- Separator: przecinek.
- Kodowanie: UTF-8.
- `payload_json` musi zawierać poprawny, escapowany JSON.
- Jedna linia CSV odpowiada jednemu żądaniu kanonicznemu.
- Przykład znajduje się w `protocol/examples/request.csv`.

## 7. Opcja `medical`

Opcja `medical` jest profilem integracyjnym dla systemów medycznych. Szkielet nie implementuje pełnej certyfikowanej integracji medycznej — definiuje miejsce i mapowanie, które projekt docelowy powinien doprecyzować, zwalidować i objąć testami zgodności.

Rekomendowane warianty:

| Wariant | Zastosowanie | Plik przykładowy |
| --- | --- | --- |
| HL7 v2-like | Integracje szpitalne oparte o komunikaty tekstowe segmentowe | `protocol/examples/medical-hl7v2-message.hl7` |
| FHIR-like JSON | Nowe integracje HTTP/API i systemy zasobowe | `protocol/examples/medical-fhir-message.json` |

Mapowanie minimalne:

| Model kanoniczny | HL7 v2-like | FHIR-like JSON |
| --- | --- | --- |
| `request_id` | `MSH-10` | `Bundle.identifier.value` |
| `source` | `MSH-3` | `MessageHeader.source.name` |
| `command` | `MSH-9` albo kod w `OBR-4` | `MessageHeader.eventCoding.code` |
| `payload.patient_id` | `PID-3` | `Patient.identifier` |
| `payload.observations[]` | `OBX` | `Observation` |
| status odpowiedzi | `MSA` / `ACK` | `OperationOutcome` albo odpowiedź API |

Wymagania bezpieczeństwa dla profilu medycznego:

- Nie logować danych pacjenta w logach technicznych bez maskowania.
- Wymagać autoryzacji i audytu dostępu.
- Rozdzielić identyfikatory techniczne od identyfikatorów pacjenta.
- Walidować komunikat przed przekazaniem do dalszych systemów.
- Dla realnego produktu wykonać analizę regulacyjną, testy zgodności i dokumentację utrzymaniową.

## 8. Wersjonowanie i kompatybilność

- Zmiana dodająca opcjonalne pole nie wymaga zwiększenia głównej wersji.
- Usunięcie pola, zmiana znaczenia pola albo zmiana typu wymaga nowej wersji głównej.
- Daemon powinien akceptować co najmniej bieżącą i poprzednią wersję kontraktu, jeśli projekt docelowy wymaga kompatybilności wstecznej.
- Każda odpowiedź powinna zwracać `protocol`, `request_id`, `status`, `code`, `message` i `payload`.

## 9. Rekomendowana konfiguracja

Opcje konfiguracyjne w projekcie docelowym:

```bash
PROTOCOL_FORMAT="json"          # json | api | csv | medical
PROTOCOL_VERSION="1"
PROTOCOL_SCHEMA_DIR="/opt/parser-template/protocol/schemas"
PROTOCOL_EXAMPLES_DIR="/opt/parser-template/protocol/examples"
MEDICAL_PROTOCOL_PROFILE="fhir" # fhir | hl7v2
```

Na etapie szkieletu daemon nadal używa prostego lokalnego formatu FIFO, ale wszystkie pola można mapować do kanonicznego modelu powyżej.
