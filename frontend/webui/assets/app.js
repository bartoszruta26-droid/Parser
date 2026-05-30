const responseBox = document.querySelector('#response');
const payloadBox = document.querySelector('#payload');

function showResponse(data) {
  responseBox.textContent = JSON.stringify(data, null, 2);
}

async function sendCommand(command) {
  responseBox.textContent = `Wysyłanie komendy: ${command}...`;

  const body = new URLSearchParams();
  body.set('command', command);
  body.set('payload', command === 'frontend.event' ? payloadBox.value : '{}');

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
    sendCommand(button.dataset.command).catch((error) => {
      showResponse({
        status: 'error',
        code: 'WEBUI_FETCH_FAILED',
        message: error.message,
      });
    });
  });
});
