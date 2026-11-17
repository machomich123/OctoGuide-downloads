import fs from 'node:fs';
import path from 'node:path';

export const CHARACTER_READY_FILENAME = 'CrewCharacterReady.flag';

export function readyFile(gameDir) {
  return path.join(gameDir, 'WTF', CHARACTER_READY_FILENAME);
}

export function clearReadyFile(gameDir) {
  const file = readyFile(gameDir);
  if (!fs.existsSync(file)) return;
  if (fs.lstatSync(file).isSymbolicLink())
    throw new Error('Linked WoW readiness file is not supported.');
  if (fs.statSync(file).size > 4096)
    throw new Error('Unexpected readiness file; refusing to remove it.');
  fs.unlinkSync(file);
}

export function characterReady(gameDir) {
  const file = readyFile(gameDir);
  try {
    const info = fs.lstatSync(file);
    if (!info.isFile() || info.isSymbolicLink() || info.size > 4096) return false;
    return fs.readFileSync(file, 'utf8').includes('CREW_CHARACTER_LIST_READY');
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    throw error;
  }
}

export async function waitForCharacterSelection(gameDir, {
  timeoutMs = 25000, intervalMs = 100,
  isGameRunning = () => true,
} = {}) {
  const started = Date.now();
  return new Promise(resolve => {
    const monitor = setInterval(() => {
      let status;
      try {
        status = characterReady(gameDir) ? 'ready' :
          !isGameRunning() ? 'exited' :
          Date.now() - started >= timeoutMs ? 'timeout' : null;
      } catch {
        status = 'error';
      }
      if (!status) return;
      clearInterval(monitor);
      resolve({ status, elapsedMs: Date.now() - started });
    }, intervalMs);
  });
}
