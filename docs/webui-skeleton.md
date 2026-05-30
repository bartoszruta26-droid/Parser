# Szkielet aplikacji WebUI

Ten dokument opisuje schematyczny frontend WebUI przeznaczony do uruchomienia pod Apache2 z obsługą PHP. Po instalacji zawartość `frontend/webui` może zostać skopiowana do katalogu HTTP serwera, na przykład `/var/www/html/parser-template`.

## Cel

WebUI jest cienkim panelem operatorskim. Nie wykonuje logiki biznesowej — prezentuje przyciski i formularze, wysyła komendy do daemona oraz wyświetla odpowiedzi JSON. Dzięki temu CLI, TUI, GUI i WebUI korzystają z tego samego kontraktu komunikacyjnego.

## Struktura

- `frontend/webui/index.php` — strona panelu operatora.
- `frontend/webui/api/daemon.php` — bramka HTTP/PHP do komunikacji z daemonem.
- `frontend/webui/assets/app.js` — obsługa kliknięć i żądań `fetch`.
- `frontend/webui/assets/style.css` — podstawowy wygląd panelu.

## Komunikacja z daemonem

Endpoint `api/daemon.php` zapisuje do FIFO linię w formacie:

```text
request_id|webui|command|payload
```

Następnie oczekuje na plik odpowiedzi w `RESPONSE_DIR` i zwraca go do przeglądarki jako JSON.

Obsługiwane komendy startowe:

- `ping`,
- `status`,
- `frontend.event`,
- `shutdown` — dostępna w API, ale niepodpięta do przycisku startowego panelu.

## Instalacja do Apache2

Skrypt `scripts/install.sh` obsługuje zmienną `APACHE_HTTP_DIR`. Domyślnie WebUI jest kopiowane do:

```bash
/var/www/html/parser-template
```

Przykład instalacji do innego katalogu HTTP:

```bash
APACHE_HTTP_DIR=/srv/http/parser-template sudo ./scripts/install.sh
```

Po instalacji należy upewnić się, że użytkownik procesu Apache ma prawo zapisu do FIFO daemona i odczytu katalogu odpowiedzi. W projekcie docelowym warto rozwiązać to przez dedykowaną grupę systemową, na przykład `parser-template`.

## Tryb testowy CLI

Bramkę PHP można uruchomić bez Apache, co ułatwia testy smoke:

```bash
WEBUI_COMMAND=status php frontend/webui/api/daemon.php
WEBUI_COMMAND=frontend.event WEBUI_PAYLOAD='{"source":"webui"}' php frontend/webui/api/daemon.php
```

## Kierunki rozbudowy

- Dodanie logowania operatora i ochrony CSRF dla operacji zmieniających stan.
- Rozdzielenie endpointów API według obszarów funkcjonalnych.
- Dodanie odczytu konfiguracji publicznej dla frontendu JavaScript.
- Dodanie WebSocket albo Server-Sent Events dla automatycznego odświeżania stanu.
