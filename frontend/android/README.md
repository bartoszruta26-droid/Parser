# Android App - Szkielet aplikacji mobilnej

## 1. Cel i przeznaczenie

Ten katalog zawiera szkielet aplikacji Android, która stanowi frontend mobilny dla systemu. Aplikacja umożliwia obsługę daemona z poziomu telefonu lub tabletu z systemem Android.

### Typowe zastosowania:
- szybki podgląd statusu daemona,
- zdalne uruchomienie funkcji systemu,
- otrzymywanie powiadomień,
- obsługa w terenie,
- konfiguracja prostych parametrów,
- skanowanie kodów, identyfikatorów lub etykiet (jeśli projekt docelowy tego wymaga).

## 2. Architektura

Aplikacja Android jest **osobnym frontendem**, który komunikuje się z daemonem przez oficjalny interfejs systemu. Nie modyfikuje bezpośrednio plików wewnętrznych bez uzgodnionego protokołu.

### Kluczowe założenia:
- Aplikacja **nie ma zaszytego na stałe adresu usługi**.
- Adres serwera, port, protokół i ścieżkę bazową API odczytuje z pliku konfiguracyjnego.
- Serwer, z którym łączy się aplikacja, jest **podaplikacją** tego repozytorium.
- Aplikacja może pracować z różnymi instancjami środowiska (dev, test, prod, Raspberry Pi).

## 3. Struktura katalogów

```
frontend/android/
├── README.md                  # Ten plik
├── android-app-config.example # Przykładowy plik konfiguracyjny
├── app/                       # Kod źródłowy aplikacji (szkielet)
│   ├── src/
│   │   └── main/
│   │       ├── java/          # Kod Java/Kotlin
│   │       ├── res/           # Zasoby aplikacji
│   │       └── AndroidManifest.xml
│   ├── build.gradle           # Konfiguracja budowania
│   └── proguard-rules.pro     # Reguły ProGuard
├── gradle/                    # Narzędzia Gradle
│   └── wrapper/
├── build.gradle               # Główny plik build.gradle
├── settings.gradle            # Ustawienia projektu
└── gradle.properties          # Właściwości Gradle
```

## 4. Konfiguracja

Plik `android-app-config.example` zawiera przykładową konfigurację, którą należy skopiować i dostosować do środowiska wdrożeniowego.

### Zawartość pliku konfiguracyjnego:

```properties
# Adres hosta lub nazwa DNS serwera
SERVER_HOST=192.168.1.100

# Port serwera
SERVER_PORT=8080

# Protokół komunikacji (HTTP lub HTTPS)
SERVER_PROTOCOL=http

# Bazowa ścieżka API (jeśli serwer ją stosuje)
API_BASE_PATH=/api/v1

# Nazwa profilu środowiskowego (dev, test, prod)
ENVIRONMENT_PROFILE=dev

# Limit czasu połączenia w milisekundach
CONNECTION_TIMEOUT_MS=5000

# Tryb zaufania dla certyfikatów (true dla środowisk lokalnych z self-signed certs)
ALLOW_SELF_SIGNED_CERTS=true
```

### Walidacja konfiguracji:

Aplikacja powinna walidować konfigurację przy starcie i prezentować czytelny komunikat, jeżeli:
- serwer z pliku konfiguracyjnego jest niedostępny,
- konfiguracja jest niepoprawna,
- wersja API jest niezgodna z oczekiwaną.

**Nie należy używać ukrytych wartości domyślnych**, które mogłyby przypadkowo skierować aplikację na niewłaściwy serwer.

## 5. Komunikacja z daemonem

Aplikacja komunikuje się z daemonem poprzez **serwer-podaplikację**, który wskazuje w pliku konfiguracyjnym.

### Mechanizmy komunikacji (do wyboru w projekcie docelowym):
- HTTP REST API,
- WebSocket,
- TCP socket z własnym protokołem tekstowym,
- lokalny socket Unix (jeśli aplikacja działa na tym samym urządzeniu).

### Przykładowe endpointy API:

```
GET  /api/v1/status          - Pobierz status daemona
POST /api/v1/command/ping    - Wyślij polecenie ping
POST /api/v1/command/shutdown - Wyślij polecenie shutdown
GET  /api/v1/events          - Pobierz zdarzenia
```

## 6. Budowanie i wdrażanie

### Wymagania:
- Android Studio Arctic Fox lub nowsze,
- JDK 11 lub nowsze,
- Android SDK (API level 21 lub wyższy),
- Gradle 7.0 lub nowsze.

### Kompilacja debug:

```bash
cd /workspace/frontend/android
./gradlew assembleDebug
```

### Kompilacja release:

```bash
./gradlew assembleRelease
```

### Instalacja na urządzeniu:

```bash
adb install app/build/outputs/apk/debug/app-debug.apk
```

## 7. Testowanie

### Testy jednostkowe:

```bash
./gradlew test
```

### Testy integracyjne:

```bash
./gradlew connectedAndroidTest
```

### Testy z daemonem:

1. Uruchom daemona w tle.
2. Uruchom serwer dla Android App jako podaplikację.
3. Skonfiguruj plik `android-app-config` z adresem serwera.
4. Uruchom aplikację na emulatorze lub urządzeniu fizycznym.

## 8. Bezpieczeństwo

### Zalecenia:
- Nie przechowuj sekretów, haseł, tokenów ani kluczy prywatnych w repozytorium.
- Plik konfiguracyjny z danymi wdrożeniowymi powinien być ignorowany przez Git (`.gitignore`).
- W środowisku produkcyjnym używaj HTTPS z valid certyfikatami.
- Implementuj mechanizm sesji lub tokenów dostępu.
- Loguj istotne operacje użytkownika.

## 9. Integracja z systemd

Serwer dla aplikacji Android powinien być uruchamiany jako usługa systemd, podobnie jak daemon główny.

Przykładowa jednostka usługi:

```ini
[Unit]
Description=Android App Communication Server
After=network.target parser-template-daemon.service

[Service]
Type=simple
ExecStart=/opt/template-project/bin/android-server
Restart=on-failure
RestartSec=5
User=template
Group=template
WorkingDirectory=/var/lib/template-project

[Install]
WantedBy=multi-user.target
```

## 10. Dalszy rozwój

Ten szkielet stanowi podstawę do implementacji pełnej aplikacji Android. Projekty docelowe powinny:

1. Dodać konkretny kod Java/Kotlin realizujący logikę biznesową.
2. Zaimplementować interfejs użytkownika zgodny z wytycznymi Material Design.
3. Dodać mechanizm autoryzacji i zarządzania sesjami.
4. Zaimplementować obsługę powiadomień push (opcjonalnie).
5. Dodać testy jednostkowe i integracyjne.
6. Przygotować procedurę code signing dla wersji release.
7. Udokumentować specyficzne wymagania projektu docelowego.

## 11. Powiązane dokumenty

- [readme.md](../../readme.md) - Główny dokument projektu
- [protocol-schema.md](../../docs/protocol-schema.md) - Schemat protokołu komunikacyjnego
- [daemon-skeleton.md](../../docs/daemon-skeleton.md) - Szkielet daemona
- [webui-skeleton.md](../../docs/webui-skeleton.md) - Szkielet WebUI
