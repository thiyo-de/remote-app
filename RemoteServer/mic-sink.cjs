// mic-sink.cjs — CommonJS mic sink + auto monitor route
// deps: npm i ws express wav
const WebSocket = require('ws');
const express   = require('express');
const { spawn } = require('child_process');
const fs        = require('fs');
const path      = require('path');
const wav       = require('wav');

const HTTP_PORT   = Number(process.env.PORT || process.env.MIC_HTTP || 8081);
const SAMPLE_RATE = Number(process.env.SAMPLE_RATE || 16000);
const CHANNELS    = 1;
const BIT_DEPTH   = 16;

// Express app → / redirects to /monitor.html
const app = express();
app.get('/', (_req, res) => res.redirect('/monitor.html'));
app.get('/monitor.html', (_req, res) => res.sendFile(path.join(__dirname, 'monitor.html')));

const server = app.listen(HTTP_PORT, () => {
  console.log(`Mic HTTP on  http://0.0.0.0:${HTTP_PORT}/monitor.html`);
});

// WS hubs
const wssIngest = new WebSocket.Server({ noServer: true });
const wssListen = new WebSocket.Server({ noServer: true });
const listeners = new Set();

// Optional local playback with ffplay (for laptop, not Render)
function startFfplay() {
  const args = [
    '-autoexit','-hide_banner','-loglevel','warning',
    '-f','s16le','-ac',String(CHANNELS),'-ar',String(SAMPLE_RATE),
    '-i','pipe:0'
  ];
  const ff = spawn('ffplay', args, { stdio: ['pipe','inherit','inherit'] });
  ff.on('error', e => console.error('ffplay error:', e.message, 'Install FFmpeg or unset LOCAL_PLAY.'));
  return ff;
}
const ffplay = process.env.LOCAL_PLAY === '1' ? startFfplay() : null;

// Optional .wav recording
function createWavWriter(deviceId) {
  const dir = path.join(__dirname, 'recordings');
  fs.mkdirSync(dir, { recursive: true });
  const outPath = path.join(dir, `mic_${deviceId}_${new Date().toISOString().replace(/[:.]/g,'-')}.wav`);
  const writer = new wav.Writer({ channels: CHANNELS, sampleRate: SAMPLE_RATE, bitDepth: BIT_DEPTH });
  writer.pipe(fs.createWriteStream(outPath));
  console.log('[rec] writing', outPath);
  return writer;
}

// Upgrade handler
server.on('upgrade', (req, socket, head) => {
  let url;
  try { url = new URL(req.url, `http://${req.headers.host}`); } catch { socket.destroy(); return; }
  if (url.pathname === '/mic-pcm') {
    wssIngest.handleUpgrade(req, socket, head, ws => wssIngest.emit('connection', ws, req));
  } else if (url.pathname === '/listen') {
    wssListen.handleUpgrade(req, socket, head, ws => wssListen.emit('connection', ws, req));
  } else {
    socket.destroy();
  }
});

// Device ingest
wssIngest.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const deviceId = url.searchParams.get('deviceId') || 'dev';
  console.log('[ingest] connected:', deviceId);

  const wavWriter = process.env.RECORD === '1' ? createWavWriter(deviceId) : null;

  ws.on('message', (data) => {
    const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);

    if (ffplay && ffplay.stdin.writable) {
      try { ffplay.stdin.write(buf); } catch {}
    }
    if (wavWriter) { try { wavWriter.write(buf); } catch {} }

    for (const client of listeners) {
      if (client.readyState === WebSocket.OPEN) {
        try { client.send(buf, { binary: true }); } catch {}
      }
    }
  });

  ws.on('close', () => {
    console.log('[ingest] closed:', deviceId);
    if (wavWriter) { try { wavWriter.end(); } catch {} }
  });
});

// Browser/CLI listeners
wssListen.on('connection', (ws) => {
  listeners.add(ws);
  ws.on('close', () => listeners.delete(ws));
});

// Graceful exit
function shutdown() {
  try { server.close(); } catch {}
  for (const c of listeners) { try { c.close(); } catch {} }
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
