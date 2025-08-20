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
import android.provider.Settings;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.util.LinkedHashSet;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

/** Foreground service: WebSocket + read-only commands (list/read files, logs, roots). */
public class RemoteService extends Service {

    private static final String TAG = "RemoteAccess";
    private static final String CH  = "remote_access_chan";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static final AtomicBoolean STARTED = new AtomicBoolean(false);

    private OkHttpClient http;
    private WebSocket socket;

    @Override public void onCreate() {
        super.onCreate();
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CH, "RemoteAccess", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Foreground service for RemoteAccess");
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.createNotificationChannel(channel);
        }
        http = new OkHttpClient.Builder()
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .pingInterval(20, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        Notification n = new NotificationCompat.Builder(this, CH)
                .setContentTitle("RemoteAccess is active")
                .setContentText("Running as a foreground service")
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setOngoing(true)
                .build();
        startForeground(1, n);

        if (STARTED.getAndSet(true)) return START_STICKY;
        mainHandler.postDelayed(this::initAsync, 1500);
        return START_STICKY;
    }

    private void initAsync() { connectWebSocket(); }

    // ---------------- WebSocket ----------------

    private void connectWebSocket() {
        final String url = wsUrl();
        Request req = new Request.Builder().url(url).build();
        socket = http.newWebSocket(req, new WebSocketListener() {
            @Override public void onOpen(WebSocket ws, Response r) {
                Log.i(TAG, "WS open: " + r.code());
                try {
                    sendJson(new JSONObject()
                            .put("action","hello")
                            .put("deviceId", deviceId())
                            .put("model", Build.MODEL));
                } catch (JSONException ignore) {}
            }

            @Override public void onMessage(WebSocket ws, String text) {
                try { handleCommand(new JSONObject(text)); }
                catch (JSONException e) { Log.w(TAG, "WS invalid JSON: " + e.getMessage()); }
            }

            @Override public void onClosed(WebSocket ws, int code, String reason) {
                Log.i(TAG, "WS closed: " + code + " " + reason);
                reconnectSoon();
            }

            @Override public void onFailure(WebSocket ws, Throwable t, Response r) {
                Log.w(TAG, "WS failure: " + (t != null ? t.getMessage() : "unknown"));
                reconnectSoon();
            }
        });
    }

    private void reconnectSoon() {
        mainHandler.postDelayed(() -> { try { connectWebSocket(); } catch (Throwable ignore) {} }, 3000);
    }

    private void sendJson(JSONObject obj) {
        try { if (socket != null) socket.send(obj.toString()); }
        catch (Throwable t) { Log.w(TAG, "WS send failed: " + t.getMessage()); }
    }

    // ---------------- Command handler ----------------

    private void handleCommand(JSONObject msg) {
        try {
            final String action = msg.optString("action", "");
            final String cid    = msg.optString("correlationId", "");
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
                    reply.put("result", getOwnLogs(lines));
                    break;
                }

                case "list_files": {
                    String path = (params != null) ? params.optString("path", "/storage/emulated/0")
                                                   : "/storage/emulated/0";
                    // return an ARRAY in "result"
                    reply.put("result", listFilesJson(path));
                    break;
                }

                case "read_file": {
                    String path = (params != null) ? params.optString("path", "") : "";
                    try {
                        File f = new File(path);
                        if (!f.exists() || f.isDirectory()) {
                            reply.put("result", new JSONObject()
                                    .put("name", f.getName())
                                    .put("size", 0)
                                    .put("base64", ""));
                        } else {
                            byte[] data = new byte[(int) f.length()];
                            try (FileInputStream fis = new FileInputStream(f)) {
                                int off = 0, read;
                                while (off < data.length &&
                                        (read = fis.read(data, off, data.length - off)) > 0) {
                                    off += read;
                                }
                            }
                            String b64 = android.util.Base64.encodeToString(
                                    data, android.util.Base64.NO_WRAP);
                            reply.put("result", new JSONObject()
                                    .put("name", f.getName())
                                    .put("size", data.length)
                                    .put("base64", b64));
                        }
                    } catch (Throwable t) {
                        Log.w(TAG, "read_file failed: " + t.getMessage());
                        try {
                            reply.put("result", new JSONObject()
                                    .put("name", "(error)")
                                    .put("size", 0)
                                    .put("base64", ""));
                        } catch (JSONException ignore) {}
                    }
                    break;
                }

                case "list_storage_roots": {
                    reply.put("result", new JSONObject()
                            .put("roots", listStorageRoots()));
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

    // ---------------- Helpers ----------------

    private String deviceId() {
        return Settings.Secure.getString(getContentResolver(), Settings.Secure.ANDROID_ID);
    }

    /** Build JSON array of a directory contents. Never throws checked exceptions. */
    private JSONArray listFilesJson(String path) {
        JSONArray arr = new JSONArray();
        try {
            File dir = new File(path);
            if (!dir.exists() || !dir.isDirectory()) {
                arr.put(new JSONObject()
                        .put("name","(error)")
                        .put("error","Not a directory: " + path));
                return arr;
            }
            File[] files = dir.listFiles();
            if (files == null) {
                arr.put(new JSONObject()
                        .put("name","(error)")
                        .put("error","Not readable (permission/IO): " + path));
                return arr;
            }
            for (File f : files) {
                arr.put(new JSONObject()
                        .put("name", f.getName())
                        .put("path", f.getAbsolutePath())
                        .put("isDir", f.isDirectory())
                        .put("size", f.isFile() ? f.length() : 0)
                        .put("lastModified", f.lastModified()));
            }
        } catch (Throwable t) {
            try {
                arr.put(new JSONObject()
                        .put("name","(error)")
                        .put("error", String.valueOf(t.getMessage())));
            } catch (JSONException ignore) {}
        }
        return arr;
    }

    /** Return primary + removable storage roots that are readable. */
    private JSONArray listStorageRoots() throws JSONException {
        LinkedHashSet<String> roots = new LinkedHashSet<>();

        File primary = Environment.getExternalStorageDirectory(); // /storage/emulated/0
        if (primary != null && primary.exists() && primary.canRead()) {
            roots.add(primary.getAbsolutePath());
        }

        File[] extFilesDirs = getExternalFilesDirs(null);
        if (extFilesDirs != null) {
            for (File f : extFilesDirs) {
                if (f == null) continue;
                String abs = f.getAbsolutePath();
                int idx = abs.indexOf("/Android/");
                if (idx > 0) {
                    String root = abs.substring(0, idx); // e.g. /storage/1234-5678
                    File rf = new File(root);
                    if (rf.exists() && rf.canRead()) roots.add(rf.getAbsolutePath());
                }
            }
        }

        File sdcard = new File("/sdcard");
        if (sdcard.exists() && sdcard.canRead()) roots.add(sdcard.getAbsolutePath());

        JSONArray out = new JSONArray();
        for (String p : roots) {
            String name;
            if ("/storage/emulated/0".equals(p) || "/sdcard".equals(p)) {
                name = "internal";
            } else {
                int slash = p.lastIndexOf('/');
                name = (slash >= 0 && slash < p.length() - 1) ? p.substring(slash + 1) : p;
            }
            out.put(new JSONObject().put("name", name).put("path", p));
        }
        return out;
    }

    /** Dump our logs (RemoteAccess tag). */
    private String getOwnLogs(int maxLines) {
        if (maxLines <= 0) maxLines = 200;
        if (maxLines > 2000) maxLines = 2000;
        StringBuilder out = new StringBuilder();
        Process p = null;
        try {
            p = new ProcessBuilder()
                    .command("/system/bin/logcat", "-d", "-t", String.valueOf(maxLines),
                            "RemoteAccess:I", "*:S")
                    .redirectErrorStream(true)
                    .start();
            try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = r.readLine()) != null) out.append(line).append('\n');
            }
            p.waitFor();
        } catch (Throwable t) {
            out.append("logcat failed: ").append(t.getMessage());
        } finally {
            if (p != null) try { p.destroy(); } catch (Throwable ignore) {}
        }
        String s = out.toString();
        return (s.length() > 120_000) ? s.substring(Math.max(0, s.length() - 120_000)) : s;
    }

    /** Point this to your server. Using ADB reverse → localhost on the PC. */
    private String wsUrl() {
        // With: adb reverse tcp:8080 tcp:8080
        return "ws://127.0.0.1:8080/device?id=" + deviceId();
        // For LAN: return "ws://<YOUR_PC_IP>:8080/device?id=" + deviceId();
    }

    @Override public void onDestroy() {
        STARTED.set(false);
        try { if (socket != null) { socket.close(1000, "bye"); socket = null; } } catch (Throwable ignore) {}
        try { if (http != null) { http.dispatcher().executorService().shutdown(); } } catch (Throwable ignore) {}
        super.onDestroy();
    }

    @Override public android.os.IBinder onBind(Intent intent) { return null; }
}
