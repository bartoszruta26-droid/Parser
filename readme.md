# Template projektu wieloaplikacyjnego dla Linux/Raspberry Pi

## 1. Cel dokumentu

Ten plik opisuje podstawowe założenia profesjonalnego szablonu projektu przeznaczonego do budowania kolejnych, niezależnych rozwiązań aplikacyjnych. Projekt ma charakter **template**, czyli bazowej struktury referencyjnej, z której można tworzyć nowe produkty, warianty wdrożeniowe, systemy usługowe, narzędzia operatorskie oraz aplikacje działające na urządzeniach klasy Linux i Raspberry Pi.

Szablon nie jest pojedynczą monolityczną aplikacją. Jest to uporządkowany projekt wielomodułowy, składający się z wielu niezależnie działających aplikacji, procesów, interfejsów użytkownika, podaplikacji oraz komponentów pomocniczych. Każda część systemu powinna być możliwa do rozwijania, budowania, testowania, wdrażania i uruchamiania możliwie niezależnie od pozostałych części.

Dokument określa założenia architektoniczne, organizacyjne, technologiczne i eksploatacyjne. Powinien służyć jako punkt wyjścia dla zespołów tworzących kolejne projekty na bazie tego repozytorium.

## 2. Charakter projektu

Projekt jest szablonem dla systemów, które:

- działają głównie w środowisku Linux,
- mogą być uruchamiane na komputerach jednopłytkowych Raspberry Pi,
- wykorzystują skrypty powłoki Bash do automatyzacji, instalacji, utrzymania i integracji,
- mogą okazjonalnie zawierać komponenty napisane w C, C++ lub C#,
- nie wykorzystują języka Python jako technologii projektowej,
- posiadają daemona działającego w tle,
- posiadają wiele frontendów obsługujących tę samą logikę systemową,
- pozwalają uruchamiać niezależne podaplikacje lub załączniki z poziomu frontendów,
- są przygotowane do rozszerzania o kolejne warianty sprzętowe, komunikacyjne i funkcjonalne.

Projekt powinien być traktowany jako baza dla systemów embedded, narzędzi automatyzacyjnych, usług lokalnych, paneli operatorskich, aplikacji narzędziowych, systemów nadzoru oraz projektów integrujących sprzęt z warstwą użytkownika.

## 3. Główne założenia architektoniczne

### 3.1. Niezależność aplikacji

Repozytorium może zawierać wiele aplikacji, ale każda z nich powinna być projektowana jako możliwie samodzielny komponent. Oznacza to, że aplikacje powinny mieć jasno określony zakres odpowiedzialności, własny punkt uruchomienia, własną konfigurację oraz własne zasady budowania i wdrażania.

Niezależność aplikacji oznacza w szczególności:

- możliwość uruchomienia pojedynczej aplikacji bez konieczności startowania całego systemu,
- minimalizowanie zależności między aplikacjami,
- jednoznaczne interfejsy komunikacyjne,
- brak ukrytych zależności od globalnego stanu systemu,
- możliwość wymiany lub wyłączenia wybranego komponentu bez przebudowy całego projektu,
- możliwość rozwijania frontendów niezależnie od daemona i podaplikacji.

### 3.2. Warstwowość

Projekt powinien być organizowany warstwowo. Zalecany podział logiczny obejmuje:

1. **Warstwę systemową** — skrypty instalacyjne, usługi systemowe, integracja z systemd, konfiguracja uprawnień, katalogów i logów.
2. **Warstwę daemona** — proces działający w tle, odpowiedzialny za podstawową logikę, stan systemu, komunikację i obsługę zadań.
3. **Warstwę frontendów** — osobne aplikacje TUI, WebUI, GUI i Android App służące do obsługi systemu przez użytkownika.
4. **Warstwę podaplikacji** — niezależne narzędzia, załączniki lub rozszerzenia uruchamiane przez frontend albo daemona.
5. **Warstwę konfiguracji** — pliki ustawień, profile środowiskowe, konfiguracje sprzętowe i parametry uruchomieniowe.
6. **Warstwę dokumentacji** — opisy architektury, instrukcje użytkownika, procedury operatorskie i dokumenty utrzymaniowe.

### 3.3. Separacja logiki i interfejsów

Daemon powinien zawierać lub koordynować główną logikę systemu, natomiast frontendy powinny być wyłącznie interfejsami obsługi. Frontendy nie powinny implementować krytycznej logiki biznesowej, której brak uniemożliwiłby działanie systemu z innego interfejsu.

TUI, WebUI, GUI i aplikacja Android powinny komunikować się z daemonem przez jawnie zdefiniowany mechanizm, na przykład:

- lokalny socket Unix,
- TCP na interfejsie lokalnym lub sieciowym,
- pliki poleceń i odpowiedzi w kontrolowanym katalogu,
- kolejkę komunikatów,
- prosty lokalny protokół tekstowy,
- interfejs HTTP lub WebSocket, jeżeli uzasadnia to architektura.

Wybrany mechanizm komunikacji powinien być opisany w dokumentacji projektu docelowego.

## 4. Środowisko technologiczne

### 4.1. System operacyjny

Podstawowym środowiskiem uruchomieniowym jest Linux. Projekt powinien zakładać zgodność z typowymi dystrybucjami używanymi na serwerach, stacjach roboczych i urządzeniach embedded.

Szczególnie istotnym środowiskiem docelowym jest Raspberry Pi OS lub inna dystrybucja Linux przeznaczona dla Raspberry Pi. Należy brać pod uwagę ograniczenia urządzeń jednopłytkowych, takie jak:

- ograniczona moc obliczeniowa,
- ograniczona pamięć RAM,
- ograniczona trwałość kart SD,
- konieczność bezpiecznego zamykania usług,
- możliwość pracy bez monitora,
- praca w sieci lokalnej,
- dostęp przez SSH,
- integracja z GPIO, magistralami sprzętowymi lub urządzeniami USB, jeżeli projekt docelowy tego wymaga.

### 4.2. Bash Shell Script

Bash jest podstawowym narzędziem automatyzacji projektu. Skrypty powłoki mogą być używane do:

- instalacji zależności systemowych,
- przygotowania katalogów roboczych,
- konfiguracji usług systemd,
- uruchamiania aplikacji,
- wykonywania czynności serwisowych,
- pakowania artefaktów,
- backupu i przywracania konfiguracji,
- diagnostyki środowiska,
- wykonywania prostych testów integracyjnych,
- obsługi zadań cyklicznych.

Skrypty powinny być pisane w sposób bezpieczny, przewidywalny i odporny na błędy. Zaleca się stosowanie:

```bash
set -euo pipefail
```

Tam, gdzie jest to właściwe, skrypty powinny sprawdzać wymagane polecenia, uprawnienia użytkownika, istnienie katalogów, dostępność urządzeń oraz poprawność parametrów wejściowych.

### 4.3. C, C++ i C#

Projekt może okazjonalnie wykorzystywać C, C++ lub C# w miejscach, w których uzasadnia to funkcjonalność, wydajność, integracja sprzętowa albo dostępność bibliotek.

Typowe zastosowania:

- C: niskopoziomowa obsługa systemu, integracja z urządzeniami, małe narzędzia wykonywalne.
- C++: bardziej złożone komponenty natywne, przetwarzanie danych, moduły wymagające wydajności.
- C#: aplikacje narzędziowe, GUI lub komponenty uruchamiane w środowisku, w którym dostępna jest odpowiednia platforma wykonawcza.

Kod w tych językach powinien być izolowany w osobnych modułach i nie powinien wymuszać zależności na całym repozytorium, jeżeli nie jest to konieczne.

### 4.4. Brak Pythona

Projekt z założenia **nie wykorzystuje języka Python**. Oznacza to, że:

- skrypty automatyzacyjne powinny być pisane w Bashu albo innym jawnie zaakceptowanym narzędziu,
- narzędzia generujące, instalacyjne i diagnostyczne nie powinny wymagać Pythona,
- zależności projektowe nie powinny zakładać środowiska Python,
- dokumentacja nie powinna opisywać Pythona jako wymaganego elementu stacku technologicznego.

Jeżeli projekt docelowy wymaga wyjątku od tej zasady, wyjątek powinien zostać wyraźnie udokumentowany wraz z uzasadnieniem technicznym.

## 5. Daemon systemowy

### 5.1. Rola daemona

Aplikacja posiada daemona działającego w tle. Daemon jest centralnym procesem odpowiedzialnym za stałą pracę systemu. Powinien uruchamiać się automatycznie po starcie systemu operacyjnego i działać bez konieczności aktywnej sesji użytkownika.

Do typowych obowiązków daemona należą:

- inicjalizacja środowiska aplikacji,
- utrzymywanie stanu systemu,
- obsługa żądań z frontendów,
- harmonogramowanie zadań,
- uruchamianie podaplikacji,
- monitorowanie procesów pomocniczych,
- zapis logów,
- obsługa błędów,
- zarządzanie konfiguracją runtime,
- bezpieczne zatrzymywanie systemu,
- komunikacja z urządzeniami lub usługami zewnętrznymi.

### 5.2. Integracja z systemd

W środowisku Linux zalecanym sposobem uruchamiania daemona jest systemd. Projekt powinien przewidywać plik jednostki usługi, na przykład:

```ini
[Unit]
Description=Template Project Daemon
After=network.target

[Service]
Type=simple
ExecStart=/opt/template-project/bin/template-daemon
Restart=on-failure
RestartSec=5
User=template
Group=template
WorkingDirectory=/var/lib/template-project

[Install]
WantedBy=multi-user.target
```

W projekcie docelowym należy dostosować nazwę usługi, ścieżki, użytkownika, grupę, zależności sieciowe oraz politykę restartu.

### 5.3. Stabilność i odporność

Daemon powinien być projektowany z myślą o długotrwałej pracy. Należy uwzględnić:

- odporność na chwilowe błędy komunikacji,
- kontrolowane ponawianie operacji,
- brak nieograniczonego wzrostu zużycia pamięci,
- rotację logów,
- bezpieczne zamykanie po sygnale `SIGTERM`,
- możliwość diagnostyki stanu,
- czytelne kody błędów,
- przewidywalne zachowanie po restarcie.

## 6. Frontendy systemu

Projekt zakłada istnienie kilku niezależnych interfejsów frontendowych. Każdy frontend powinien korzystać z tych samych mechanizmów komunikacji z daemonem i nie powinien wymagać osobnego wariantu logiki backendowej.

### 6.1. TUI

TUI, czyli tekstowy interfejs użytkownika, jest przeznaczony do pracy w terminalu. Powinien być lekki, szybki i wygodny przy administracji przez SSH.

Przykładowe funkcje TUI:

- podgląd statusu daemona,
- przegląd logów,
- uruchamianie podaplikacji,
- edycja podstawowej konfiguracji,
- wykonywanie komend serwisowych,
- diagnostyka połączeń,
- wyświetlanie stanu urządzeń,
- restart wybranych komponentów.

TUI jest szczególnie ważne na Raspberry Pi oraz w środowiskach bez graficznego pulpitu.

### 6.2. WebUI

WebUI jest interfejsem przeglądarkowym. Powinien umożliwiać wygodną obsługę systemu z poziomu sieci lokalnej albo bezpiecznie skonfigurowanego dostępu zdalnego.

Przykładowe funkcje WebUI:

- dashboard systemowy,
- podgląd stanu usług,
- konfiguracja użytkownika,
- przegląd historii zdarzeń,
- uruchamianie podaplikacji,
- pobieranie raportów,
- zarządzanie załącznikami,
- prezentacja danych w formie tabel, wykresów lub kart.

WebUI powinno mieć jasno określone zasady autoryzacji i uwierzytelniania, szczególnie jeśli system jest dostępny poza hostem lokalnym.

### 6.3. GUI

GUI jest klasycznym interfejsem graficznym uruchamianym lokalnie na komputerze użytkownika lub na urządzeniu z ekranem. Może być używany w scenariuszach operatorskich, serwisowych albo demonstracyjnych.

GUI powinno zapewniać:

- intuicyjną obsługę podstawowych funkcji,
- dostęp do konfiguracji,
- kontrolę nad podaplikacjami,
- wizualizację stanu systemu,
- komunikaty błędów zrozumiałe dla operatora,
- możliwość pracy w trybie offline, jeżeli pozwala na to architektura.

### 6.4. Android App

Aplikacja Android jest osobnym frontendem mobilnym. Jej zadaniem jest umożliwienie obsługi systemu z telefonu lub tabletu.

Typowe zastosowania aplikacji Android:

- szybki podgląd statusu,
- zdalne uruchomienie funkcji,
- otrzymywanie powiadomień,
- obsługa w terenie,
- konfiguracja prostych parametrów,
- skanowanie kodów, identyfikatorów lub etykiet, jeżeli projekt docelowy tego wymaga.

Aplikacja Android powinna komunikować się z daemonem przez oficjalny interfejs systemu, a nie przez bezpośrednie modyfikowanie plików wewnętrznych bez uzgodnionego protokołu.

## 7. Podaplikacje i załączniki wykonywane przez frontend

Projekt zakłada istnienie osobnych podaplikacji będących załącznikami lub rozszerzeniami funkcjonalnymi. Podaplikacje mogą być uruchamiane przez frontend, ale ich cykl życia, parametry i uprawnienia powinny być kontrolowane przez system.

### 7.1. Charakter podaplikacji

Podaplikacje mogą pełnić funkcje:

- narzędzi diagnostycznych,
- kreatorów konfiguracji,
- modułów raportujących,
- procesów importu lub eksportu danych,
- narzędzi serwisowych,
- rozszerzeń demonstracyjnych,
- zadań jednorazowych,
- komponentów integrujących urządzenia zewnętrzne.

### 7.2. Zasady uruchamiania

Podaplikacje powinny być uruchamiane w sposób kontrolowany. Zaleca się, aby frontend zgłaszał intencję uruchomienia podaplikacji do daemona, a daemon podejmował decyzję o wykonaniu. Dzięki temu można zachować spójność uprawnień, logowania i kontroli błędów.

Każde uruchomienie podaplikacji powinno mieć:

- identyfikator zadania,
- nazwę podaplikacji,
- wersję lub ścieżkę artefaktu,
- parametry wejściowe,
- użytkownika lub źródło żądania,
- czas rozpoczęcia i zakończenia,
- kod zakończenia,
- log wykonania,
- wynik możliwy do odczytania przez frontend.

### 7.3. Izolacja

Podaplikacje powinny być możliwie izolowane od siebie. Nie powinny zakładać współdzielenia katalogów tymczasowych, globalnych zmiennych środowiskowych ani niejawnych plików stanu. Jeżeli podaplikacja potrzebuje danych wejściowych, powinny być one przekazane przez jawny interfejs.

## 8. Proponowana struktura repozytorium

Poniższa struktura jest propozycją organizacji projektu template. Może być dostosowana do potrzeb projektu docelowego.

```text
.
├── README.md
├── readme.md
├── docs/
│   ├── architecture.md
│   ├── deployment.md
│   ├── operations.md
│   └── security.md
├── scripts/
│   ├── install.sh
│   ├── uninstall.sh
│   ├── build.sh
│   ├── run.sh
│   ├── test.sh
│   └── diagnostics.sh
├── daemon/
│   ├── README.md
│   ├── src/
│   ├── config/
│   └── systemd/
├── frontends/
│   ├── tui/
│   ├── webui/
│   ├── gui/
│   └── android/
├── apps/
│   ├── app-example-one/
│   └── app-example-two/
├── attachments/
│   ├── tools/
│   ├── jobs/
│   └── examples/
├── config/
│   ├── default.conf
│   ├── profiles/
│   └── hardware/
├── native/
│   ├── c/
│   ├── cpp/
│   └── csharp/
├── packaging/
│   ├── systemd/
│   ├── debian/
│   └── release/
├── tests/
│   ├── smoke/
│   ├── integration/
│   └── hardware/
└── var/
    ├── log/
    ├── run/
    └── data/
```

## 9. Konfiguracja

Konfiguracja powinna być jawna, wersjonowalna tam, gdzie jest to bezpieczne, oraz rozdzielona na konfigurację domyślną i lokalną.

Zalecane typy konfiguracji:

- konfiguracja domyślna dostarczana z projektem,
- konfiguracja lokalna zależna od urządzenia,
- profile środowiskowe,
- konfiguracja sprzętowa,
- konfiguracja sieciowa,
- konfiguracja frontendów,
- konfiguracja podaplikacji,
- konfiguracja polityk bezpieczeństwa.

Sekrety, hasła, tokeny i klucze prywatne nie powinny być przechowywane w repozytorium. Projekt powinien przewidywać mechanizm dostarczania sekretów poza kodem źródłowym.

## 10. Logowanie i diagnostyka

Każdy istotny komponent powinien generować logi w sposób spójny i użyteczny dla operatora. Logi powinny umożliwiać odtworzenie przebiegu działania systemu bez konieczności uruchamiania debuggera.

Zalecane kategorie logów:

- start i zatrzymanie komponentów,
- błędy krytyczne,
- ostrzeżenia,
- zdarzenia użytkownika,
- uruchomienia podaplikacji,
- zmiany konfiguracji,
- komunikacja z urządzeniami,
- komunikacja między frontendami a daemonem,
- operacje administracyjne.

Na Raspberry Pi należy ograniczać nadmierny zapis na kartę SD. Warto stosować rotację logów, buforowanie lub kierowanie części logów do journald.

## 11. Bezpieczeństwo

Bezpieczeństwo powinno być uwzględnione od początku projektu. Nawet jeżeli system działa wyłącznie w sieci lokalnej, należy zakładać, że błędna konfiguracja, nieautoryzowany użytkownik lub podatna usługa mogą doprowadzić do naruszenia integralności systemu.

Podstawowe zasady:

- uruchamianie daemona na dedykowanym użytkowniku systemowym,
- minimalne wymagane uprawnienia,
- brak wykonywania komend z niezweryfikowanych danych wejściowych,
- walidacja parametrów przekazywanych do podaplikacji,
- kontrola dostępu do WebUI,
- bezpieczna komunikacja, jeżeli system jest dostępny przez sieć,
- separacja danych użytkownika od plików wykonywalnych,
- ochrona sekretów,
- audyt operacji administracyjnych,
- jawne procedury aktualizacji.

## 12. Instalacja i wdrożenie

Projekt template powinien zawierać skrypty instalacyjne, które można dostosować do projektu docelowego. Typowy proces instalacji może obejmować:

1. sprawdzenie systemu operacyjnego,
2. sprawdzenie architektury CPU,
3. instalację zależności systemowych,
4. utworzenie użytkownika i grupy systemowej,
5. utworzenie katalogów w `/opt`, `/etc`, `/var/lib` i `/var/log`,
6. skopiowanie plików wykonywalnych,
7. zainstalowanie jednostki systemd,
8. wczytanie konfiguracji domyślnej,
9. aktywowanie usługi,
10. wykonanie testu startowego,
11. zapis raportu instalacji.

Wdrożenie powinno być powtarzalne. Ten sam zestaw skryptów powinien umożliwiać instalację na nowym urządzeniu bez ręcznego wykonywania nieudokumentowanych kroków.

## 13. Budowanie i wydania

Ponieważ projekt może zawierać wiele niezależnych aplikacji, proces budowania powinien umożliwiać budowę całego systemu lub pojedynczych komponentów.

Zalecane tryby:

- `build all` — budowa wszystkich komponentów,
- `build daemon` — budowa daemona,
- `build tui` — budowa TUI,
- `build webui` — budowa WebUI,
- `build gui` — budowa GUI,
- `build android` — budowa aplikacji Android,
- `build apps` — budowa podaplikacji,
- `build native` — budowa komponentów C, C++ lub C#.

Wydanie powinno zawierać numer wersji, changelog, artefakty binarne, konfigurację domyślną, instrukcję migracji i informację o kompatybilności.

## 14. Testowanie

Projekt template powinien promować testowanie na kilku poziomach:

- testy składni skryptów Bash,
- testy uruchomieniowe skryptów instalacyjnych w trybie suchym,
- testy smoke dla daemona,
- testy komunikacji frontend-daemon,
- testy uruchamiania podaplikacji,
- testy integracyjne na Linux,
- testy sprzętowe na Raspberry Pi,
- testy odporności na restart usługi,
- testy poprawności logowania i konfiguracji.

Testy sprzętowe powinny być wyraźnie oznaczone, ponieważ mogą wymagać fizycznych urządzeń, uprawnień lub specyficznego środowiska.

## 15. Zasady projektowania interfejsów komunikacyjnych

Każdy interfejs między komponentami powinien być stabilny, udokumentowany i możliwy do testowania. Dotyczy to szczególnie komunikacji między frontendami a daemonem.

Dobrze zaprojektowany interfejs powinien określać:

- format żądań,
- format odpowiedzi,
- kody błędów,
- limity czasowe,
- wersję protokołu,
- sposób autoryzacji,
- sposób obsługi przerwania operacji,
- zasady kompatybilności wstecznej,
- przykłady użycia.

Zmiana interfejsu powinna być traktowana jako zmiana kontraktu między aplikacjami.

## 16. Obsługa błędów

System powinien rozróżniać błędy użytkownika, błędy środowiskowe, błędy programistyczne i błędy sprzętowe.

Przykładowe kategorie:

- brak wymaganej konfiguracji,
- brak uprawnień,
- niedostępne urządzenie,
- błąd komunikacji,
- niepoprawne dane wejściowe,
- nieznana podaplikacja,
- przekroczenie limitu czasu,
- nieoczekiwane zakończenie procesu,
- niespójność stanu systemu.

Komunikaty błędów powinny być przydatne zarówno dla użytkownika końcowego, jak i dla administratora systemu.

## 17. Utrzymanie i eksploatacja

Projekt powinien zawierać procedury utrzymaniowe opisujące codzienną obsługę systemu. Operator powinien wiedzieć, jak:

- sprawdzić status daemona,
- zatrzymać i uruchomić usługę,
- przejrzeć logi,
- zmienić konfigurację,
- uruchomić diagnostykę,
- wykonać backup,
- przywrócić konfigurację,
- zaktualizować aplikację,
- zweryfikować wersję,
- sprawdzić miejsce na dysku,
- zidentyfikować przyczynę awarii.

Dokumentacja utrzymaniowa powinna być praktyczna i oparta na konkretnych poleceniach.

## 18. Raspberry Pi jako środowisko docelowe

Raspberry Pi wymaga szczególnej uwagi projektowej. System powinien być lekki i odporny na typowe problemy urządzeń brzegowych.

Zalecenia:

- ograniczać liczbę stale działających procesów,
- unikać intensywnego zapisu na kartę SD,
- stosować watchdog tam, gdzie jest to uzasadnione,
- zapewnić start po zaniku zasilania,
- logować kluczowe błędy do journald lub rotowanych plików,
- przewidzieć pracę bez monitora i klawiatury,
- zapewnić możliwość konfiguracji przez SSH lub WebUI,
- testować aktualizacje na docelowej architekturze ARM,
- dokumentować wymagane wersje systemu i bibliotek.

## 19. Standardy jakości

Każdy projekt utworzony na bazie tego template powinien dążyć do wysokiej jakości technicznej. Oznacza to:

- czytelną strukturę katalogów,
- jednoznaczne nazewnictwo,
- powtarzalne skrypty,
- minimalne zależności,
- dokumentowanie decyzji architektonicznych,
- jasny podział odpowiedzialności,
- przewidywalne zachowanie po błędzie,
- możliwość uruchomienia diagnostyki,
- brak ukrytych wymagań środowiskowych,
- łatwość przenoszenia między urządzeniami.

## 20. Minimalny zakres projektu startowego

Minimalna wersja projektu tworzonego na podstawie tego szablonu powinna zawierać:

- dokumentację podstawową,
- skrypt instalacyjny,
- skrypt uruchomieniowy,
- definicję daemona,
- przykładową konfigurację,
- co najmniej jeden frontend referencyjny,
- przykład podaplikacji,
- opis komunikacji między komponentami,
- instrukcję wdrożenia,
- instrukcję diagnostyczną.

Dopiero na tej bazie należy dodawać kolejne frontendy, integracje sprzętowe i rozszerzenia.

## 21. Zasada rozszerzalności

Szablon powinien umożliwiać rozszerzanie bez łamania istniejących komponentów. Nowa funkcja powinna być dodawana jako osobny moduł, nowa podaplikacja, nowy endpoint, nowy widok frontendowy albo nowy profil konfiguracji, jeżeli pozwala na to charakter zmiany.

Nie należy traktować template jako jednorazowego zestawu plików. Powinien być utrzymywany jako standard organizacyjny, który można ulepszać wraz z kolejnymi projektami.

## 22. Podsumowanie

Ten projekt jest profesjonalnym szablonem dla rozwiązań wieloaplikacyjnych działających w środowisku Linux i Raspberry Pi. Jego fundamentem jest daemon pracujący w tle, zestaw niezależnych frontendów, podaplikacje wykonywane jako załączniki oraz automatyzacja oparta głównie na Bashu. Projekt dopuszcza użycie C, C++ i C# tam, gdzie jest to technicznie uzasadnione, ale nie zakłada użycia Pythona.

Najważniejsze zasady template to:

- modułowość,
- niezależność aplikacji,
- separacja frontendu od logiki systemowej,
- kontrolowane uruchamianie podaplikacji,
- powtarzalne wdrożenia,
- przewidywalna eksploatacja,
- zgodność z Linux i Raspberry Pi,
- ograniczanie zależności,
- profesjonalna dokumentacja,
- gotowość do dalszego rozwoju.

Szablon powinien być bazą dla kolejnych projektów, w których istotne są stabilność, przejrzystość, możliwość utrzymania oraz jasne rozdzielenie odpowiedzialności między komponentami systemu.
