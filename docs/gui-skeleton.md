# Szkielet aplikacji GUI

Ten dokument opisuje schematyczny frontend GUI do komunikacji z daemonem projektu. Implementacja referencyjna znajduje się w `frontend/gui/parser-gui.sh` i wykorzystuje dostępne w systemie narzędzie dialogowe `zenity` albo `kdialog`.

## Cel

GUI jest cienką aplikacją operatorską. Jej zadaniem jest prezentowanie okien, pobieranie decyzji użytkownika i wysyłanie komend do daemona. Logika systemowa, walidacja operacji, obsługa sprzętu oraz kolejkowanie zadań powinny pozostać po stronie daemona albo komponentów backendowych.

## Plik startowy

```bash
./frontend/gui/parser-gui.sh
```

W trybie interaktywnym wymagane jest jedno z narzędzi:

- `zenity` — typowe dla środowisk GTK,
- `kdialog` — typowe dla środowisk KDE/Qt.

Wybór można wymusić zmienną albo argumentem:

```bash
GUI_DIALOG_TOOL=zenity ./frontend/gui/parser-gui.sh
./frontend/gui/parser-gui.sh --tool kdialog
```

## Komunikacja z daemonem

GUI używa tego samego protokołu co CLI i TUI:

```text
request_id|source|command|payload
```

Dla GUI pole `source` ma wartość `gui`, a `request_id` zaczyna się od prefiksu `gui-`. Odpowiedź jest odczytywana z katalogu `RESPONSE_DIR` jako dokument JSON przygotowany przez daemona.

## Akcje interaktywne

Referencyjne menu GUI zawiera:

- `ping` — sprawdzenie, czy daemon odpowiada,
- `status` — pobranie aktualnego statusu,
- `frontend.event` — wysłanie przykładowego zdarzenia z payloadem JSON,
- `show.last` — pokazanie ostatniej odpowiedzi,
- `exit` — zamknięcie GUI bez zatrzymywania daemona.

## Tryb jednorazowy

Tryb jednorazowy nie wymaga `zenity` ani `kdialog`, dlatego nadaje się do testów automatycznych:

```bash
./frontend/gui/parser-gui.sh --once ping
./frontend/gui/parser-gui.sh --once status
./frontend/gui/parser-gui.sh --once frontend.event --payload '{"source":"gui"}'
```

## Kierunki rozbudowy

- Podmiana skryptowego GUI na natywną aplikację C, C++ lub C# przy zachowaniu tego samego kontraktu komunikacyjnego.
- Dodanie ekranów diagnostyki, konfiguracji i operacji serwisowych.
- Dodanie autoryzacji operatora przed wysłaniem komend wrażliwych.
- Dodanie mapowania kodów odpowiedzi daemona na czytelne komunikaty w oknach GUI.
