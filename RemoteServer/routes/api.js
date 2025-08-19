import express from "express";
import { sendCommandToDevice } from "../ws/messageRouter.js";
import { listDevices } from "../ws/connectionManager.js";

const router = express.Router();

// Health
router.get("/health", (_req, res) => res.json({ ok: true }));

// Connected devices
router.get("/devices", (_req, res) => res.json({ devices: listDevices() }));

// Command: POST /api/command/:deviceId
router.post("/command/:deviceId", async (req, res) => {
  const { deviceId } = req.params;
  const payload = req.body; // e.g., { action: "list_files", params: { path: "/Download" } }
  try {
    const result = await sendCommandToDevice(deviceId, payload, 20000);
    res.json(result);
  } catch (e) {
    res.status(504).json({ error: e.message });
  }
});

export default router;
