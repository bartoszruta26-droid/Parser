const responseBox = document.querySelector('#response');
const payloadBox = document.querySelector('#payload');
const sensorIdBox = document.querySelector('#sensor-id');
const sensorPayloadBox = document.querySelector('#sensor-payload');
const effectorIdBox = document.querySelector('#effector-id');
const effectorPayloadBox = document.querySelector('#effector-payload');

function showResponse(data) {
  responseBox.textContent = JSON.stringify(data, null, 2);
}

async function sendCommand(command, requiresId = false, requiresConfig = false) {
  let payload = '{}';
  let sensorId = '';
  let effectorId = '';

  // Obsługa komend wymagających ID sensora/efektora
  if (requiresId) {
    sensorId = sensorIdBox.value.trim();
    effectorId = effectorIdBox.value.trim();

    if (command.startsWith('sensor.') && !sensorId) {
      responseBox.textContent = 'Błąd: Podaj ID sensora w polu "ID Sensora"';
      return;
    }
    if (command.startsWith('effector.') && command !== 'effector.list' && !effectorId) {
      responseBox.textContent = 'Błąd: Podaj ID efektora w polu "ID Efektora"';
      return;
    }

    // Budowanie payloadu z ID
    if (command.startsWith('sensor.')) {
      const basePayload = sensorPayloadBox.value.trim() || '{}';
      try {
        const parsed = JSON.parse(basePayload);
        parsed.sensor_id = sensorId;
        payload = JSON.stringify(parsed);
      } catch (e) {
        payload = JSON.stringify({ sensor_id: sensorId });
      }
    } else if (command.startsWith('effector.')) {
      const basePayload = effectorPayloadBox.value.trim() || '{}';
      try {
        const parsed = JSON.parse(basePayload);
        parsed.effector_id = effectorId;
        payload = JSON.stringify(parsed);
      } catch (e) {
        payload = JSON.stringify({ effector_id: effectorId });
      }
    }
  } else if (requiresConfig) {
    // Komendy konfigurujące używają odpowiednich payloadów
    if (command.startsWith('sensor.')) {
      payload = sensorPayloadBox.value.trim() || '{}';
    } else if (command.startsWith('effector.')) {
      payload = effectorPayloadBox.value.trim() || '{}';
    }
  } else if (command === 'frontend.event') {
    payload = payloadBox.value.trim() || '{}';
  }

  responseBox.textContent = `Wysyłanie komendy: ${command}...`;

  const body = new URLSearchParams();
  body.set('command', command);
  body.set('payload', payload);

  const response = await fetch('api/daemon.php', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
    },
    body,
  });

  const text = await response.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    data = {
      status: 'error',
      code: 'INVALID_JSON_RESPONSE',
      message: text,
    };
  }

  showResponse(data);
}

document.querySelectorAll('[data-command]').forEach((button) => {
  button.addEventListener('click', () => {
    const command = button.dataset.command;
    const requiresId = button.dataset.requiresId === 'true';
    const requiresConfig = button.dataset.requiresConfig === 'true';

    sendCommand(command, requiresId, requiresConfig).catch((error) => {
      showResponse({
        status: 'error',
        code: 'WEBUI_FETCH_FAILED',
        message: error.message,
      });
    });
  });
});
