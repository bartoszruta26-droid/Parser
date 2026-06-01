<?php
/**
 * Reference WebUI gateway for the template daemon.
 * It is intentionally small: validate a command, write it to the daemon FIFO,
 * wait for the JSON response file, and pass that response back to the browser.
 */

declare(strict_types=1);

function default_config_path(): string
{
    $envPath = getenv('DAEMON_CONFIG');
    if ($envPath !== false && $envPath !== '') {
        return $envPath;
    }

    return '/etc/parser-template/daemon.conf';
}

function fallback_config_path(): string
{
    return dirname(__DIR__, 3) . '/config/daemon.conf.example';
}

function expand_config_value(string $value, array $config): string
{
    return preg_replace_callback('/\$\{([A-Z0-9_]+)\}/', static function (array $matches) use ($config): string {
        return $config[$matches[1]] ?? '';
    }, $value) ?? $value;
}

function load_daemon_config(): array
{
    $path = default_config_path();
    if (!is_readable($path)) {
        $path = fallback_config_path();
    }

    $config = [];
    if (is_readable($path)) {
        $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines ?: [] as $line) {
            $line = trim($line);
            if ($line === '' || substr($line, 0, 1) === '#') {
                continue;
            }
            if (preg_match('/^([A-Z0-9_]+)=(.*)$/', $line, $matches) !== 1) {
                continue;
            }

            $key = $matches[1];
            $value = trim($matches[2]);
            if (
                strlen($value) >= 2
                && (($value[0] === '"' && substr($value, -1) === '"') || ($value[0] === "'" && substr($value, -1) === "'"))
            ) {
                $value = substr($value, 1, -1);
            }
            $config[$key] = expand_config_value($value, $config);
        }
    }

    $runDir = $config['RUN_DIR'] ?? '/tmp/parser-template';
    $config['COMMAND_FIFO'] = $config['COMMAND_FIFO'] ?? $runDir . '/commands.fifo';
    $config['RESPONSE_DIR'] = $config['RESPONSE_DIR'] ?? $runDir . '/responses';
    $config['REQUEST_TIMEOUT_SECONDS'] = $config['REQUEST_TIMEOUT_SECONDS'] ?? '10';
    $config['WEBUI_TITLE'] = $config['WEBUI_TITLE'] ?? 'Parser Template WebUI';

    return $config;
}

function request_input(): array
{
    if (PHP_SAPI === 'cli') {
        $command = getenv('WEBUI_COMMAND') ?: ($GLOBALS['argv'][1] ?? 'status');
        $payload = getenv('WEBUI_PAYLOAD') ?: ($GLOBALS['argv'][2] ?? '{}');
        return [$command, $payload];
    }

    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    if ($method !== 'POST') {
        return ['status', '{}'];
    }

    $command = isset($_POST['command']) ? (string) $_POST['command'] : 'status';
    $payload = isset($_POST['payload']) ? (string) $_POST['payload'] : '{}';

    return [$command, $payload];
}

function json_error(string $code, string $message, int $httpCode = 400): void
{
    if (PHP_SAPI !== 'cli') {
        http_response_code($httpCode);
    }

    echo json_encode([
        'protocol' => '1',
        'request_id' => null,
        'status' => 'error',
        'code' => $code,
        'message' => $message,
        'payload' => new stdClass(),
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
}

function send_daemon_command(string $command, string $payload, array $config): int
{
    $allowedCommands = ['ping', 'status', 'frontend.event', 'shutdown'];
    if (!in_array($command, $allowedCommands, true)) {
        json_error('INVALID_COMMAND', 'Nieobsługiwana komenda WebUI: ' . $command);
        return 64;
    }

    $fifo = $config['COMMAND_FIFO'];
    $responseDir = $config['RESPONSE_DIR'];
    $timeout = max(1, (int) $config['REQUEST_TIMEOUT_SECONDS']);

    if (!is_writable($fifo)) {
        json_error('DAEMON_UNAVAILABLE', 'Daemon FIFO nie jest dostępne: ' . $fifo, 503);
        return 69;
    }

    $requestId = 'webui-' . time() . '-' . getmypid() . '-' . random_int(1000, 9999);
    $responseFile = $responseDir . '/' . $requestId . '.json';
    $line = $requestId . '|webui|' . $command . '|' . $payload . PHP_EOL;

    $fifoHandle = fopen($fifo, 'wb');
    if ($fifoHandle === false) {
        json_error('FIFO_OPEN_FAILED', 'Nie można otworzyć FIFO daemona.', 503);
        return 69;
    }

    fwrite($fifoHandle, $line);
    fclose($fifoHandle);

    $deadline = microtime(true) + $timeout;
    while (!is_file($responseFile)) {
        if (microtime(true) >= $deadline) {
            json_error('TIMEOUT', 'Brak odpowiedzi daemona w limicie ' . $timeout . 's.', 504);
            return 70;
        }
        usleep(100000);
    }

    $response = file_get_contents($responseFile);
    if ($response === false) {
        json_error('RESPONSE_READ_FAILED', 'Nie można odczytać odpowiedzi daemona.', 500);
        return 74;
    }

    echo $response;
    if (substr($response, -1) !== "\n") {
        echo PHP_EOL;
    }

    return 0;
}

if (PHP_SAPI !== 'cli') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
}

[$command, $payload] = request_input();
exit(send_daemon_command($command, $payload, load_daemon_config()));
