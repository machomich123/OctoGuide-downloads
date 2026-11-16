'use strict';
const key = new URL(location.href).searchParams.get('key');
const $ = id => document.getElementById(id);
const message = (text, error = false) => {
  $('message').textContent = text;
  $('message').style.color = error ? '#ffb9ad' : '';
};
async function api(action, args = {}) {
  const response = await fetch('/api', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Crew-Token': key },
    body: JSON.stringify({ action, args }),
  });
  const parsed = await response.json();
  if (!response.ok || !parsed.ok) throw new Error(parsed.error || 'Launcher request failed');
  return parsed.result;
}
async function run(action, args = {}, label = action) {
  try {
    message('Working: ' + label + '…');
    const result = await api(action, args);
    message(label + ' completed.');
    return result;
  } catch (error) {
    message(error.message, true);
    throw error;
  }
}
async function runShow(action, args = {}) {
  try {
    const result = await run(action, args, action);
    $('addonResult').textContent = JSON.stringify(result, null, 2);
  } catch (error) {
    $('addonResult').textContent = error.message;
  }
}
function protect(button, task) {
  button.addEventListener('click', async () => {
    button.disabled = true;
    try { await task(); }
    catch { /* The status line already reports errors. */ }
    finally { button.disabled = false; }
  });
}
for (const button of document.querySelectorAll('.nav')) {
  button.addEventListener('click', () => {
    for (const nav of document.querySelectorAll('.nav')) nav.classList.toggle('active', nav === button);
    for (const panel of document.querySelectorAll('.panel'))
      panel.classList.toggle('active', panel.id === button.dataset.tab);
  });
}
async function updatePresence() {
  try {
    const { online } = await api('presence');
    $('players').replaceChildren();
    for (const user of ['MICHAEL', 'JAYKE', 'BERNARD', 'AUGUST']) {
      const div = document.createElement('div');
      div.className = 'player';
      const name = document.createElement('span'), status = document.createElement('span');
      name.textContent = user;
      status.textContent = online[user] ? '● Online' : '○ Offline';
      status.className = online[user] ? 'online' : '';
      div.append(name, status);
      $('players').append(div);
    }
  } catch { $('players').textContent = 'Status unknown'; }
}
function account() { return $('account').value; }
protect($('refreshPresence'), updatePresence);
protect($('play'), async () => {
  await run('play', { username: account(), password: $('password').value,
    remember: $('remember').checked, useSaved: $('useSaved').checked }, 'Game launch');
  $('password').value = '';
});
protect($('saveClient'), async () => {
  const saved = await run('setClient', { wowPath: $('wowPath').value }, 'Client verification');
  $('wowLocation').textContent = saved.settings.wowPath;
});
protect($('changePassword'), async () => {
  if (!confirm('Change the game password for ' + account() + '?')) return;
  await run('changePassword', { current: $('currentPassword').value,
    desired: $('newPassword').value }, 'Change account password');
  $('currentPassword').value = '';
  $('newPassword').value = '';
});
protect($('loadInstalled'), () => runShow('installed'));
protect($('missing'), () => runShow('missing'));
protect($('previewImport'), () => runShow('previewImport', { source: $('source').value }));
protect($('import'), async () => {
  if (confirm('Import compatible addons with backup? Close WoW first.')) {
    await runShow('import', { source: $('source').value });
  }
});
protect($('repair'), async () => {
  if (confirm('Back up Config.wtf, repair addon folder names and check dependencies?')) await runShow('repair');
});
protect($('checkUpdates'), async () => {
  const result = await run('refreshManifest', {}, 'Official version check');
  message('Official EXE version: ' + result.version +
    (result.updatesPaused ? ' · automatic EXE updates paused.' : ' · releases available.'));
});
$('account').addEventListener('change', async () => {
  $('password').value = '';
  $('useSaved').checked = false;
  await run('setAccount', { username: account() }, 'Select account').catch(() => {});
});
async function initial() {
  if (!key || !/^[0-9a-f]{64}$/.test(key)) {
    message('Invalid localhost launcher session.', true);
    return;
  }
  const state = await run('state', {}, 'Load preferences');
  // Migration must see a real browser-to-backend handshake promptly.
  // Slow external realm-status requests must not cause a false rollback.
  await api('handshake');
  $('account').replaceChildren();
  for (const user of state.accounts) {
    const option = new Option(user, user, false, user === state.settings.username);
    $('account').add(option);
  }
  $('wowPath').value = state.settings.wowPath;
  $('wowLocation').textContent = state.settings.wowPath || 'No WoW.exe selected';
  $('useSaved').disabled = !state.savedAccounts.includes(account());
  await run('refreshManifest', {}, 'Check server settings').catch(() => {});
  try {
    await api('status');
    $('serviceStatus').textContent = '● Realm service online';
  } catch {
    $('serviceStatus').textContent = '○ Realm service unavailable';
  }
  await updatePresence();
  message('Tortoise Crew preview ready. Your v1.0.11 installation has not been changed.');
}
initial().catch(error => message(error.message, true));
