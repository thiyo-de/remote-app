import { log, warn } from "../utils/logger.js";

const devices = new Map(); // deviceId -> WebSocket

export function attachDevice(deviceId, ws) {
  devices.set(deviceId, ws);
  log(`device connected: ${deviceId} (total ${devices.size})`);
  ws.on("close", () => {
    devices.delete(deviceId);
    warn(`device disconnected: ${deviceId} (total ${devices.size})`);
  });
}

export function getDevice(deviceId) {
  return devices.get(deviceId);
}

export function listDevices() {
  return Array.from(devices.keys());
}
