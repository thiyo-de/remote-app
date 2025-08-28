package com.remoteaccess;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
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
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.util.LinkedHashSet;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

/** Foreground service + WebSocket command handler. */
public class RemoteService extends Service {

    private MicManager mic;

    private static final String TAG = "RemoteAccess";
    private static final String CH  = "remote_access_chan";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static final AtomicBoolean STARTED = new AtomicBoolean(false);

    private OkHttpClient http;
    private WebSocket socket;

    @Override public void onCreate() {
        super.onCreate();
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(
                    CH, "RemoteAccess", NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Foreground service for RemoteAccess");
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.createNotificationChannel(ch);
        }
        
        http = new OkHttpClient.Builder()
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .pingInterval(20, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build();
                mic = new MicManager(this);
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

    // -------------------- WebSocket --------------------

    private void connectWebSocket() {
        final String url = wsUrl();
        Request req = new Request.Builder().url(url).build();
        socket = http.newWebSocket(req, new WebSocketListener() {
            @Override public void onOpen(WebSocket ws, Response r) {
                Log.i(TAG, "WS open: " + r.code());
                try {
                    JSONObject hello = new JSONObject()
                            .put("action", "hello")
                            .put("deviceId", deviceId())
                            .put("model", Build.MODEL);
                    sendJson(hello);
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
        mainHandler.postDelayed(() -> {
            try { connectWebSocket(); } catch (Throwable ignore) {}
        }, 3000);
    }

    private void sendJson(JSONObject obj) {
        try { if (socket != null) socket.send(obj.toString()); }
        catch (Throwable t) { Log.w(TAG, "WS send failed: " + t.getMessage()); }
    }

    // -------------------- Command Router --------------------

    private void handleCommand(JSONObject msg) {
        try {
            final String action = msg.optString("action", "");
            final String cid    = msg.optString("correlationId", "");
            final JSONObject p  = msg.optJSONObject("params");

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
                    int lines = (p != null) ? p.optInt("lines", 200) : 200;
                    reply.put("result", getOwnLogs(lines));
                    break;
                }

                case "list_files": {   // result: [ {name,path,isDir,size,lastModified}, ... ]
                    String path = (p != null) ? p.optString("path", "/storage/emulated/0")
                                              : "/storage/emulated/0";
                    reply.put("result", listFilesJson(path));
                    break;
                }

                case "read_file": {    // result: { name, size, base64 }
                    String path = (p != null) ? p.optString("path", "") : "";
                    try {
                        File f = new File(path);
                        if (!f.exists() || f.isDirectory()) {
                            reply.put("result", new JSONObject()
                                    .put("name", f.getName())
                                    .put("size", 0)
                                    .put("base64", ""));
                        } else {
                            byte[] data = readAll(f);
                            String b64 = android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP);
                            reply.put("result", new JSONObject()
                                    .put("name", f.getName())
                                    .put("size", data.length)
                                    .put("base64", b64));
                        }
                    } catch (Throwable t) {
                        Log.w(TAG, "read_file failed: " + t.getMessage());
                        reply.put("error", "read_file: " + t.getMessage());
                    }
                    break;
                }

                // ----------- WRITE / UPLOAD / DELETE / MKDIR -----------

                case "mkdirs": {       // params: { path }
                    String path = (p != null) ? p.optString("path", "") : "";
                    try {
                        if (path.isEmpty()) { reply.put("error", "mkdirs: empty path"); break; }
                        File dir = new File(path);
                        boolean ok = dir.exists() ? dir.isDirectory() : dir.mkdirs();
                        if (!ok) reply.put("error", "mkdirs failed");
                        else reply.put("result", new JSONObject().put("ok", true));
                    } catch (Throwable t) {
                        reply.put("error", "mkdirs: " + t.getMessage());
                    }
                    break;
                }

                case "write_file": {   // params: { path, base64, append? }
                    String path    = (p != null) ? p.optString("path", "")   : "";
                    String base64  = (p != null) ? p.optString("base64", "") : "";
                    boolean append = (p != null) && p.optBoolean("append", false);
                    try {
                        if (path.isEmpty()) { reply.put("error", "write_file: empty path"); break; }
                        File out = new File(path);
                        if (out.isDirectory()) { reply.put("error", "write_file: path is a directory"); break; }
                        byte[] data = base64.isEmpty()
                                ? new byte[0]
                                : android.util.Base64.decode(base64, android.util.Base64.DEFAULT);
                        ensureParentDirs(out);
                        writeFileBytes(out, data, append);
                        reply.put("result", new JSONObject().put("ok", true).put("bytes", data.length));
                    } catch (Throwable t) {
                        reply.put("error", "write_file: " + t.getMessage());
                    }
                    break;
                }

                case "delete_file": {  // params: { path }
                    String path = (p != null) ? p.optString("path", "") : "";
                    try {
                        File f = new File(path);
                        if (!f.exists() || f.isDirectory()) {
                            reply.put("error", "not a file: " + path);
                        } else {
                            boolean ok = f.delete();
                            if (!ok) reply.put("error", "delete failed");
                            else reply.put("result", new JSONObject().put("ok", true));
                        }
                    } catch (Throwable t) {
                        reply.put("error", "delete_file: " + t.getMessage());
                    }
                    break;
                }

                case "delete_dir": {   // params: { path, recursive:true|false }
                    String path = (p != null) ? p.optString("path", "") : "";
                    boolean recursive = (p != null) && p.optBoolean("recursive", false);
                    try {
                        File d = new File(path);
                        if (!d.exists() || !d.isDirectory()) {
                            reply.put("error", "not a directory: " + path);
                        } else if (!recursive) {
                            boolean ok = d.delete();
                            if (!ok) reply.put("error", "dir not empty (use recursive)");
                            else reply.put("result", new JSONObject().put("ok", true));
                        } else {
                            boolean ok = deleteDirRecursive(d);
                            if (!ok) reply.put("error", "recursive delete failed");
                            else reply.put("result", new JSONObject().put("ok", true));
                        }
                    } catch (Throwable t) {
                        reply.put("error", "delete_dir: " + t.getMessage());
                    }
                    break;
                }

                case "list_storage_roots": { // result: { roots: [ {name, path}, ... ] }
                    try {
                        JSONArray roots = listStorageRoots();
                        reply.put("result", new JSONObject().put("roots", roots));
                    } catch (Throwable t) {
                        reply.put("error", "list_storage_roots: " + t.getMessage());
                    }
                    break;
                }

                case "mic_start_stream": { // params: { wsUrl, sampleRate, frameMs }
    String wsUrl = (p != null) ? p.optString("wsUrl", "") : "";
    int sampleRate = (p != null) ? p.optInt("sampleRate", 16000) : 16000;
    int frameMs    = (p != null) ? p.optInt("frameMs", 40) : 40;
    if (wsUrl.isEmpty()) { reply.put("error", "wsUrl required"); break; }
    reply.put("result", mic.startStream(wsUrl, sampleRate, frameMs));
    break;
}
case "mic_stop_stream": {
    reply.put("result", mic.stopStream());
    break;
}
case "mic_start_record": { // params: { seconds?, filename? }
    int seconds = (p != null) ? p.optInt("seconds", 0) : 0;
    String name = (p != null) ? p.optString("filename", "") : "";
    if (name.isEmpty()) {
        name = "rec_" + System.currentTimeMillis() + ".m4a";
    }
    File out = new File("/storage/emulated/0/RemoteAccess/Recordings/" + name);
    reply.put("result", mic.startRecord(out, seconds));
    break;
}
case "mic_stop_record": {
    reply.put("result", mic.stopRecord());
    break;
}

                
                // -------------------------------------------------------

                default: {
                    reply.put("error", "unknown action: " + action);
                }
            }

            sendJson(reply);
        } catch (JSONException e) {
            Log.w(TAG, "handleCommand error: " + e.getMessage());
        }
    }

    // -------------------- Helpers --------------------

    private String deviceId() {
        return Settings.Secure.getString(getContentResolver(), Settings.Secure.ANDROID_ID);
    }

    private static byte[] readAll(File f) throws Exception {
        try (FileInputStream fis = new FileInputStream(f)) {
            long lenL = f.length();
            int len = (lenL > Integer.MAX_VALUE)
                    ? (int) Math.min(lenL, 32 * 1024 * 1024) // cap to 32MB safety
                    : (int) lenL;
            byte[] out = new byte[len];
            int off = 0, r;
            while ((r = fis.read(out, off, out.length - off)) > 0) off += r;
            if (off < out.length) {
                byte[] trimmed = new byte[off];
                System.arraycopy(out, 0, trimmed, 0, off);
                return trimmed;
            }
            return out;
        }
    }

    private static void ensureParentDirs(File f) {
        File p = f.getParentFile();
        if (p != null && !p.exists()) p.mkdirs();
    }

    private static void writeFileBytes(File f, byte[] data, boolean append) throws Exception {
        ensureParentDirs(f);
        try (FileOutputStream fos = new FileOutputStream(f, append)) {
            fos.write(data);
        }
    }

    private static boolean deleteDirRecursive(File dir) {
        File[] kids = dir.listFiles();
        if (kids != null) {
            for (File k : kids) {
                if (k.isDirectory()) {
                    if (!deleteDirRecursive(k)) return false;
                } else {
                    if (!k.delete()) return false;
                }
            }
        }
        return dir.delete();
    }

    /** Build JSON listing for a directory. */
    private JSONArray listFilesJson(String path) {
        JSONArray arr = new JSONArray();
        try {
            File dir = new File(path);
            if (!dir.exists() || !dir.isDirectory()) {
                arr.put(new JSONObject().put("name", "(error)").put("error", "Not a directory: " + path));
                return arr;
            }
            File[] files = dir.listFiles();
            if (files == null) return arr;
            for (File f : files) {
                JSONObject o = new JSONObject();
                try {
                    o.put("name", f.getName());
                    o.put("path", f.getAbsolutePath());
                    o.put("isDir", f.isDirectory());
                    o.put("size", f.isFile() ? f.length() : 0);
                    o.put("lastModified", f.lastModified());
                } catch (JSONException ignore) {}
                arr.put(o);
            }
        } catch (Throwable t) {
            try {
                arr.put(new JSONObject().put("name", "(error)").put("error", String.valueOf(t.getMessage())));
            } catch (JSONException ignore) {}
        }
        return arr;
    }

    /** Limited log dump (tag RemoteAccess). */
    private String getOwnLogs(int maxLines) {
        if (maxLines <= 0) maxLines = 200;
        if (maxLines > 2000) maxLines = 2000;
        StringBuilder out = new StringBuilder();
        Process p = null;
        try {
            p = new ProcessBuilder()
                    .command("/system/bin/logcat", "-d", "-t", String.valueOf(maxLines), "RemoteAccess:I", "*:S")
                    .redirectErrorStream(true)
                    .start();
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) out.append(line).append('\n');
            p.waitFor();
        } catch (Throwable t) {
            out.append("logcat failed: ").append(t.getMessage());
        } finally {
            if (p != null) try { p.destroy(); } catch (Throwable ignore) {}
        }
        String s = out.toString();
        if (s.length() > 120_000) s = s.substring(Math.max(0, s.length() - 120_000));
        return s;
    }

    /** Discover readable storage roots (internal + SD/OTG). */
    private org.json.JSONArray listStorageRoots() throws org.json.JSONException {
        LinkedHashSet<String> roots = new LinkedHashSet<>();

        // Primary shared storage (/storage/emulated/0)
        File primary = android.os.Environment.getExternalStorageDirectory();
        if (primary != null && primary.exists() && primary.canRead()) {
            roots.add(primary.getAbsolutePath());
        }

        // App-specific external dirs → strip "/Android/..." to get the card root
        File[] ext = getExternalFilesDirs(null);
        if (ext != null) {
            for (File f : ext) {
                if (f == null) continue;
                String abs = f.getAbsolutePath();
                int idx = abs.indexOf("/Android/");
                if (idx > 0) {
                    String root = abs.substring(0, idx);
                    File rf = new File(root);
                    if (rf.exists() && rf.canRead()) roots.add(rf.getAbsolutePath());
                }
            }
        }

        // Optional alias
        File sdcard = new File("/sdcard");
        if (sdcard.exists() && sdcard.canRead()) roots.add(sdcard.getAbsolutePath());

        org.json.JSONArray out = new org.json.JSONArray();
        for (String path : roots) {
            String name;
            if ("/storage/emulated/0".equals(path) || "/sdcard".equals(path)) {
                name = "internal";
            } else {
                int slash = path.lastIndexOf('/');
                name = (slash >= 0 && slash < path.length() - 1) ? path.substring(slash + 1) : path;
            }
            out.put(new org.json.JSONObject().put("name", name).put("path", path));
        }
        return out;
    }

    /** ADB reverse path during dev; change to LAN if needed. */
    private String wsUrl() {
        return "ws://127.0.0.1:8080/device?id=" + deviceId();
        // For LAN: return "ws://<PC-IP>:8080/device?id=" + deviceId();
    }

    @Override public void onDestroy() {
        STARTED.set(false);
        try { if (socket != null) { socket.close(1000, "bye"); socket = null; } } catch (Throwable ignore) {}
        try { if (http   != null) { http.dispatcher().executorService().shutdown(); } } catch (Throwable ignore) {}
        super.onDestroy();
    }

    @Override public android.os.IBinder onBind(Intent intent) { return null; }
}
