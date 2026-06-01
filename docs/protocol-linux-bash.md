# Założenia komunikacji: Bash i aplikacje linuksowe

Ten projekt nie zakłada użycia Pythona w daemonie, klientach lokalnych ani narzędziach instalacyjnych. Warstwa komunikacji referencyjnej jest oparta o Bash Shell Script oraz standardowe mechanizmy Linux.

## Zasady nadrzędne

- Daemon pozostaje skryptem Bash i nie importuje ani nie uruchamia Pythona.
- Klienci lokalni komunikują się przez FIFO i pliki odpowiedzi w katalogu runtime.
- Format logiczny wiadomości jest kanoniczny, ale transport lokalny pozostaje prosty: `request_id|source|command|payload`.
- JSON, CSV i komunikaty medyczne są danymi wejściowymi/wyjściowymi, a nie powodem do dodawania runtime Python.
- Walidacja w instalacjach docelowych powinna korzystać z dostępnych aplikacji linuksowych, na przykład `jq`, `awk`, `sed`, `grep`, `php`, `curl`, `openssl` albo narzędzi systemowych.

## Transport lokalny

Referencyjny transport lokalny:

```text
client bash/linux app -> COMMAND_FIFO -> daemon bash -> RESPONSE_DIR/request_id.json
```

Minimalna linia transportowa:

```text
request_id|source|command|payload
```

Do wysłania pojedynczej komendy można użyć pomocnika:

```bash
./protocol/bin/daemon-send.sh --source cli --command status
./protocol/bin/daemon-send.sh --source medical --command medical.message --payload '{"profile":"fhir"}'
```

## Rola poszczególnych opcji protokołu

- `json` — domyślny format payloadów i odpowiedzi; w Bashu jest przekazywany jako tekst, a walidacja może być wykonana przez `jq` poza gorącą ścieżką daemona.
- `api` — profil ekspozycji przez HTTP, np. Apache2/PHP WebUI; daemon nadal może pozostać lokalnym procesem Bash.
- `csv` — format importu/eksportu obsługiwany narzędziami typu `awk`, `sed`, `cut` albo dedykowanym importerem shellowym.
- `medical` — profil danych medycznych, np. HL7 v2-like jako tekst segmentowy lub FHIR-like JSON; dane wrażliwe muszą być maskowane w logach.

## Granice odpowiedzialności

Daemon powinien przyjmować komendy, utrzymywać stan, zapisywać odpowiedzi i delegować cięższą integrację do osobnych aplikacji linuksowych, jeśli projekt docelowy tego wymaga. Dodanie parsera lub adaptera branżowego nie powinno zmieniać założenia, że główny daemon jest czystym Bash Shell Script.
