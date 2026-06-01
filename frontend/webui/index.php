<?php
/** Reference Apache/PHP WebUI for the template daemon. */
declare(strict_types=1);

$title = getenv('WEBUI_TITLE') ?: 'Parser Template WebUI';
?>
<!doctype html>
<html lang="pl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= htmlspecialchars($title, ENT_QUOTES, 'UTF-8') ?></title>
  <link rel="stylesheet" href="assets/style.css">
</head>
<body>
  <main class="shell">
    <header class="hero">
      <p class="eyebrow">Frontend WebUI</p>
      <h1><?= htmlspecialchars($title, ENT_QUOTES, 'UTF-8') ?></h1>
      <p>Referencyjny panel Apache/PHP do komunikacji z daemonem przez wspólny protokół FIFO.</p>
    </header>

    <section class="panel" aria-labelledby="actions-title">
      <h2 id="actions-title">Akcje daemona</h2>
      <div class="actions">
        <button type="button" data-command="ping">Ping</button>
        <button type="button" data-command="status">Status</button>
        <button type="button" data-command="frontend.event">Wyślij zdarzenie WebUI</button>
      </div>

      <label for="payload">Payload JSON dla <code>frontend.event</code></label>
      <textarea id="payload" rows="6">{"source":"webui","action":"operator-click"}</textarea>
    </section>

    <section class="panel" aria-labelledby="response-title">
      <h2 id="response-title">Odpowiedź daemona</h2>
      <pre id="response" aria-live="polite">Brak odpowiedzi. Wybierz akcję powyżej.</pre>
    </section>
  </main>

  <script src="assets/app.js" defer></script>
</body>
</html>
