import WebSocket from 'ws';
import express from 'express';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import wav from 'wav';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);

const HTTP_PORT  = Number(process.env.PORT || process.env.MIC_HTTP || 8081);
const SAMPLE_RATE= Number(process.env.SAMPLE_RATE || 16000);
const CHANNELS   = 1, BIT_DEPTH = 16;

const app = express();
app.get('/', (_req,res)=>res.redirect('/monitor.html'));
app.get('/monitor.html', (_req,res)=>res.sendFile(path.join(__dirname,'monitor.html')));

const server = app.listen(HTTP_PORT, ()=> {
  console.log(`Mic HTTP on  http://0.0.0.0:${HTTP_PORT}/monitor.html`);
});

const wssIngest = new WebSocket.Server({ noServer:true }); // device -> server
const wssListen = new WebSocket.Server({ noServer:true }); // browsers -> server
const listeners = new Set();

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === '/mic-pcm') {
    // OPTIONAL: gate ingestion with token
    const token = url.searchParams.get('token') || '';
    if (process.env.RA_TOKEN && token !== process.env.RA_TOKEN) {
      socket.destroy(); return;
    }
    wssIngest.handleUpgrade(req, socket, head, ws => wssIngest.emit('connection', ws, req));
  } else if (url.pathname === '/listen') {
    wssListen.handleUpgrade(req, socket, head, ws => wssListen.emit('connection', ws, req));
  } else {
    socket.destroy();
  }
});

function createWavWriter(deviceId) {
  const outDir = path.join(__dirname, 'recordings');
  fs.mkdirSync(outDir, { recursive: true });
  const out = path.join(outDir, `mic_${deviceId}_${new Date().toISOString().replace(/[:.]/g,'-')}.wav`);
  const writer = new wav.Writer({ channels: CHANNELS, sampleRate: SAMPLE_RATE, bitDepth: BIT_DEPTH });
  writer.pipe(fs.createWriteStream(out));
  console.log('[rec] writing', out);
  return writer;
}

wssIngest.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const deviceId = url.searchParams.get('deviceId') || 'dev';
  console.log('[ingest] connected:', deviceId);
  const wavWriter = process.env.RECORD === '1' ? createWavWriter(deviceId) : null;

  ws.on('message', data => {
    const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
    if (wavWriter) wavWriter.write(buf);
    for (const client of listeners) {
      if (client.readyState === WebSocket.OPEN) {
        try { client.send(buf, { binary:true }); } catch {}
      }
    }
  });

  ws.on('close', () => {
    if (wavWriter) { try { wavWriter.end(); } catch {} }
    console.log('[ingest] closed:', deviceId);
  });
});

wssListen.on('connection', ws => {
  listeners.add(ws);
  ws.on('close', () => listeners.delete(ws));
});
