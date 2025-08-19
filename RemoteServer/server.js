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
const PORT = process.env.PORT || 8080;
const WS_PATH = process.env.WS_PATH || "/device";
const API_PREFIX = process.env.API_PREFIX || "/api";
const ORIGIN = process.env.CORS_ORIGIN || "*";

const app = express();
app.use(helmet());
app.use(cors({ origin: ORIGIN, credentials: true }));
app.use(express.json({ limit: "10mb" }));
app.use(httpLogger());
app.use(API_PREFIX, apiRouter);

const server = http.createServer(app);

// WebSocket for devices (APK connects here)
const wss = new WebSocketServer({ server, path: WS_PATH });

wss.on("connection", (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const deviceId = url.searchParams.get("id");
  if (!deviceId) {
    ws.close(1008, "missing id");
    return;
  }
  attachDevice(deviceId, ws);

  ws.on("message", (raw) => {
    try {
      const data = JSON.parse(raw.toString());
      log(`← from ${deviceId}`, data.action ?? "unknown_action");
      // Optionally: broadcast device status updates to a dashboard here.
    } catch (e) {
      warn("invalid device message", e.message);
    }
  });
});

server.listen(PORT, () => {
  log(`HTTP   listening on http://localhost:${PORT}${API_PREFIX}`);
  log(`WS     listening on ws://localhost:${PORT}${WS_PATH}?id=<deviceId>`);
});
