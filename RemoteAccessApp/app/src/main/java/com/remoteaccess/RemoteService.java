package com.remoteaccess;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
// import android.os.PowerManager; // if you use a wakelock, also add WAKE_LOCK permission
import android.provider.Settings;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

/**
 * 24/7 Foreground service. Posts notification ASAP; connects WS; supports
 * read-only actions.
 */
public class RemoteService extends Service {

    private static final String TAG = "RemoteAccess";
    private static final String CH = "remote_access_chan";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static final AtomicBoolean STARTED = new AtomicBoolean(false);

    // --- WS fields ---
    private OkHttpClient http;
    private WebSocket socket;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "RemoteService.onCreate: creating notification channel");

        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CH, "RemoteAccess", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Foreground service for RemoteAccess");
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null)
                nm.createNotificationChannel(channel);
        }

        // OkHttp client for WebSocket (keep-alive pings)
        http = new OkHttpClient.Builder()
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .pingInterval(20, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "RemoteService.onStartCommand: posting foreground notification ASAP");

        // Foreground notification (Android 12+ requirement)
        Notification n = new NotificationCompat.Builder(this, CH)
                .setContentTitle("RemoteAccess is active")
                .setContentText("Running as a foreground service")
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setOngoing(true)
                .build();
        startForeground(1, n);
        Log.i(TAG, "RemoteService.onStartCommand: now running in FOREGROUND");

        // Ensure heavy init only runs once
        if (STARTED.getAndSet(true)) {
            Log.i(TAG, "RemoteService.onStartCommand: already initialized, skipping init");
            return START_STICKY;
        }

        // Defer heavy work slightly; improves reliability right after boot
        mainHandler.postDelayed(this::initAsync, 1500);

        return START_STICKY; // ask system to restart if killed
    }

    /** Heavy init: connect the WebSocket and register message handler. */
    private void initAsync() {
        Log.i(TAG, "RemoteService.initAsync: start managers / network here");
        connectWebSocket();
    }

    // ---------- WebSocket -----------

    private void connectWebSocket() {
        final String url = wsUrl();
        Log.i(TAG, "WS connect → " + url);

        Request req = new Request.Builder().url(url).build();
        socket = http.newWebSocket(req, new WebSocketListener() {
            @Override
            public void onOpen(WebSocket webSocket, Response response) {
                Log.i(TAG, "WS open: " + response.code());
                try {
                    JSONObject hello = new JSONObject()
                            .put("action", "hello")
                            .put("deviceId", deviceId())
                            .put("model", Build.MODEL);
                    sendJson(hello);
                } catch (JSONException e) {
                    Log.w(TAG, "JSON build failed on open: " + e.getMessage());
                }
            }

            @Override
            public void onMessage(WebSocket webSocket, String text) {
                try {
                    JSONObject msg = new JSONObject(text);
                    handleCommand(msg);
                } catch (JSONException e) {
                    Log.w(TAG, "WS invalid JSON: " + e.getMessage());
                }
            }

            @Override
            public void onClosed(WebSocket webSocket, int code, String reason) {
                Log.i(TAG, "WS closed: " + code + " " + reason);
                reconnectSoon();
            }

            @Override
            public void onFailure(WebSocket webSocket, Throwable t, Response r) {
                Log.w(TAG, "WS failure: " + (t != null ? t.getMessage() : "unknown"));
                reconnectSoon();
            }
        });
    }

    private void reconnectSoon() {
        mainHandler.postDelayed(() -> {
            try {
                connectWebSocket();
            } catch (Throwable ignored) {
            }
        }, 3000);
    }

    private void sendJson(JSONObject obj) {
        try {
            if (socket != null)
                socket.send(obj.toString());
        } catch (Throwable t) {
            Log.w(TAG, "WS send failed: " + t.getMessage());
        }
    }

    private void handleCommand(JSONObject msg) {
        try {
            final String action = msg.optString("action", "");
            final String cid = msg.optString("correlationId", "");
            final JSONObject params = msg.optJSONObject("params");

            JSONObject reply = new JSONObject()
                    .put("correlationId", cid)
                    .put("action", action);

            switch (action) {
                case "ping": {
                    reply.put("result", "pong");
                    break;
                }

                case "get_device_info": {
                    reply.put("result", new JSONObject()
                            .put("deviceId", deviceId())
                            .put("brand", Build.BRAND)
                            .put("model", Build.MODEL)
                            .put("sdk", Build.VERSION.SDK_INT));
                    break;
                }

                case "get_logs": {
                    int lines = (params != null) ? params.optInt("lines", 200) : 200;
                    String logs = getOwnLogs(lines);
                    reply.put("result", logs);
                    break;
                }

                case "list_files": {
                    String path = msg.optJSONObject("params") != null
                            ? msg.optJSONObject("params").optString("path", "/storage/emulated/0")
                            : "/storage/emulated/0";

                    File dir = new File(path);
                    JSONArray out = new JSONArray();

                    if (!dir.exists()) {
                        reply.put("error", "Not found: " + path);
                    } else if (!dir.isDirectory()) {
                        reply.put("error", "Not a directory: " + path);
                    } else {
                        File[] kids = dir.listFiles();
                        if (kids == null) {
                            // listFiles() == null ⇒ not readable (permissions or IO)
                            reply.put("error", "Not readable (permission/IO): " + path);
                        } else {
                            for (File f : kids) {
                                JSONObject row = new JSONObject();
                                row.put("name", f.getName());
                                row.put("path", f.getAbsolutePath());
                                row.put("isDir", f.isDirectory());
                                row.put("size", f.isFile() ? f.length() : 0);
                                row.put("lastModified", f.lastModified());
                                out.put(row);
                            }
                            reply.put("result", out); // <— IMPORTANT: array, not object
                        }
                    }
                    sendJson(reply);
                    break;
                }

                case "read_file": {
                    JSONObject p = msg.optJSONObject("params");
                    String path = (p != null) ? p.optString("path", "") : "";
                    try {
                        java.io.File f = new java.io.File(path);
                        if (!f.exists() || f.isDirectory()) {
                            reply.put("result", new JSONObject()
                                    .put("name", f.getName())
                                    .put("size", 0)
                                    .put("base64", ""));
                        } else {
                            java.io.FileInputStream fis = new java.io.FileInputStream(f);
                            byte[] data;
                            try {
                                data = new byte[(int) f.length()];
                                int read = 0, off = 0;
                                while (off < data.length && (read = fis.read(data, off, data.length - off)) > 0) {
                                    off += read;
                                }
                            } finally {
                                fis.close();
                            }
                            String b64 = android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP);
                            reply.put("result", new JSONObject()
                                    .put("name", f.getName())
                                    .put("size", data.length)
                                    .put("base64", b64));
                        }
                    } catch (Throwable t) {
                        reply.put("result", new JSONObject()
                                .put("name", "(error)")
                                .put("size", 0)
                                .put("base64", ""));
                        Log.w(TAG, "read_file failed: " + t.getMessage());
                    }
                    break;
                }

                default: {
                    reply.put("error", "unknown action: " + action);
                }
            }

            sendJson(reply);
        } catch (JSONException e) {
            Log.w(TAG, "handleCommand error: " + e.getMessage());
        }
    }

    // ---------- Helpers -----------

    private String deviceId() {
        return Settings.Secure.getString(
                getContentResolver(), Settings.Secure.ANDROID_ID);
    }

    /** Dump our own logs (tag RemoteAccess) via logcat -d. */
    private String getOwnLogs(int maxLines) {
        if (maxLines <= 0)
            maxLines = 200;
        if (maxLines > 2000)
            maxLines = 2000;

        StringBuilder out = new StringBuilder();
        Process p = null;
        try {
            p = new ProcessBuilder()
                    .command("/system/bin/logcat", "-d", "-t", String.valueOf(maxLines),
                            "RemoteAccess:I", "*:S")
                    .redirectErrorStream(true)
                    .start();
            BufferedReader r = new BufferedReader(
                    new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) {
                out.append(line).append('\n');
            }
            p.waitFor();
        } catch (Throwable t) {
            out.append("logcat failed: ").append(t.getMessage());
        } finally {
            if (p != null)
                try {
                    p.destroy();
                } catch (Throwable ignored) {
                }
        }
        String s = out.toString();
        if (s.length() > 120_000) {
            s = s.substring(Math.max(0, s.length() - 120_000));
        }
        return s;
    }

    /** Build JSON listing for a directory — never throws checked exceptions. */
    private JSONArray listFilesJson(String path) {
        JSONArray arr = new JSONArray();
        try {
            File dir = new File(path);
            if (!dir.exists() || !dir.isDirectory()) {
                JSONObject err = new JSONObject();
                try {
                    err.put("name", "(error)");
                    err.put("error", "Not a directory: " + path);
                } catch (JSONException ignore) {
                }
                arr.put(err);
                return arr;
            }

            File[] files = dir.listFiles();
            if (files == null)
                return arr;

            for (File f : files) {
                JSONObject o = new JSONObject();
                try {
                    o.put("name", f.getName());
                    o.put("path", f.getAbsolutePath());
                    o.put("isDir", f.isDirectory());
                    o.put("size", f.isFile() ? f.length() : 0);
                    o.put("lastModified", f.lastModified());
                } catch (JSONException ignore) {
                }
                arr.put(o);
            }
        } catch (Throwable t) {
            JSONObject err = new JSONObject();
            try {
                err.put("name", "(error)");
                err.put("error", String.valueOf(t.getMessage()));
            } catch (JSONException ignore) {
            }
            arr.put(err);
        }
        return arr;
    }

    /** Point this to your server. We’re using ADB reverse → localhost on the PC. */
    private String wsUrl() {
        // With: adb reverse tcp:8080 tcp:8080
        return "ws://127.0.0.1:8080/device?id=" + deviceId();
        // For Wi-Fi/LAN, use: return "ws://<YOUR_PC_IP>:8080/device?id=" + deviceId();
    }

    // --------------------------------

    @Override
    public void onDestroy() {
        Log.i(TAG, "RemoteService.onDestroy");
        STARTED.set(false);
        try {
            if (socket != null) {
                socket.close(1000, "bye");
                socket = null;
            }
        } catch (Throwable ignored) {
        }
        try {
            if (http != null) {
                http.dispatcher().executorService().shutdown();
            }
        } catch (Throwable ignored) {
        }
        super.onDestroy();
    }

    @Override
    public android.os.IBinder onBind(Intent intent) {
        return null;
    }
}
