import { v4 as uuidv4 } from "uuid";
import { getDevice } from "./connectionManager.js";
import { log, warn } from "../utils/logger.js";

/**
 * Forward a command to a device over WS and await a single response.
 * Returns a Promise resolved with JSON from the device or rejects on timeout.
 */
export function sendCommandToDevice(deviceId, payload, timeoutMs = 15000) {
  const ws = getDevice(deviceId);
  if (!ws || ws.readyState !== 1) {
    throw new Error("Device not connected");
  }
  const correlationId = uuidv4();
  const msg = { correlationId, ...payload };

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error("Device timeout"));
    }, timeoutMs);

    const onMessage = (raw) => {
      try {
        const data = JSON.parse(raw.toString());
        if (data.correlationId === correlationId) {
          cleanup();
          resolve(data);
        }
      } catch (e) {
        warn("invalid JSON from device", e.message);
      }
    };

    const cleanup = () => {
      clearTimeout(timer);
      ws.off("message", onMessage);
    };

    ws.on("message", onMessage);
    ws.send(JSON.stringify(msg));
    log(`→ sent to ${deviceId}`, msg.action ?? "unknown_action");
  });
}
