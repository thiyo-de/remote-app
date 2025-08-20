// server.js
import http from "http";
import { WebSocketServer } from "ws";
import express from "express";
import cors from "cors";
import helmet from "helmet";
import dotenv from "dotenv";
import apiRouter from "./routes/api.js";
import { httpLogger, log, warn } from "./utils/logger.js";
import { attachDevice } from "./ws/connectionManager.js";

dotenv.config();

const PORT      = process.env.PORT       || 8080;
const WS_PATH   = process.env.WS_PATH    || "/device";
const API_PREFIX= process.env.API_PREFIX || "/api";
const ORIGIN    = process.env.CORS_ORIGIN|| "*";

const app = express();
app.use(helmet());
app.use(cors({ origin: ORIGIN, credentials: true }));
app.use(express.json({ limit: "10mb" }));
app.use(httpLogger());
app.use(API_PREFIX, apiRouter);

const server = http.createServer(app);

// --- WebSocket for devices (APK connects here) ---
const wss = new WebSocketServer({ server, path: WS_PATH });

// Heartbeat (server-driven): mark alive on pong; ping every 30s
function heartbeat() { this.isAlive = true; }

wss.on("connection", (ws, req) => {
  // Parse device id from query
  const url = new URL(req.url, `http://${req.headers.host}`);
  const deviceId = url.searchParams.get("id");
  if (!deviceId) {
    ws.close(1008, "missing id");
    return;
  }

  // Attach to device registry / routing
  attachDevice(deviceId, ws);

  // Init heartbeat state and handlers
  ws.isAlive = true;
  ws.on("pong", heartbeat);

  // Optional logging of device messages
  ws.on("message", (raw) => {
    try {
      const data = JSON.parse(raw.toString());
      log(`← from ${deviceId}`, data.action ?? "unknown_action");
      // Broadcast to dashboards here if needed
    } catch (e) {
      warn("invalid device message", e.message);
    }
  });

  ws.on("close", (code, reason) => {
    // connectionManager should clean up on 'close' via its own handlers
    warn(`WS closed for ${deviceId}`, `${code} ${reason}`);
  });

  ws.on("error", (err) => {
    warn(`WS error for ${deviceId}`, err?.message || String(err));
  });
});

// Ping all clients every 30s; terminate if they don’t pong
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      warn("WS client unresponsive, terminating…", "");
      return ws.terminate();
    }
    ws.isAlive = false;
    try { ws.ping(); } catch { /* ignore */ }
  });
}, 30000);

wss.on("close", () => clearInterval(heartbeatInterval));

server.listen(PORT, () => {
  log(`HTTP   listening on http://localhost:${PORT}${API_PREFIX}`);
  log(`WS     listening on ws://localhost:${PORT}${WS_PATH}?id=<deviceId>`);
});
