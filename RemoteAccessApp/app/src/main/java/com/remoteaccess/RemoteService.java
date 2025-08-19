package com.remoteaccess;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
// import android.os.PowerManager; // <-- uncomment if you keep wakelock + add WAKE_LOCK permission
import android.provider.Settings;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

/** 24/7 Foreground service. Posts notification ASAP; defers heavy work a bit; connects WS. */
public class RemoteService extends Service {

    private static final String TAG = "RemoteAccess";
    private static final String CH  = "remote_access_chan";

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
            if (nm != null) nm.createNotificationChannel(channel);
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

        // --- OPTIONAL wakelock (needs WAKE_LOCK permission in manifest) ---
        /*
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                PowerManager.WakeLock wl = pm.newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK, "RemoteAccess:bootStart");
                wl.acquire(5000); // auto-release after 5s
            }
        } catch (Throwable t) {
            Log.w(TAG, "Wakelock acquire failed (ok to ignore): " + t.getMessage());
        }
        */
        // ------------------------------------------------------------------

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
                Log.w(TAG, "WS failure: " + t.getMessage());
                reconnectSoon();
            }
        });
    }

    private void reconnectSoon() {
        mainHandler.postDelayed(() -> {
            try { connectWebSocket(); } catch (Throwable ignored) {}
        }, 3000);
    }

    private void sendJson(JSONObject obj) {
        try {
            if (socket != null) socket.send(obj.toString());
        } catch (Throwable t) {
            Log.w(TAG, "WS send failed: " + t.getMessage());
        }
    }

    private void handleCommand(JSONObject msg) {
        try {
            final String action = msg.optString("action", "");
            final String cid = msg.optString("correlationId", "");

            JSONObject reply = new JSONObject()
                    .put("correlationId", cid)
                    .put("action", action);

            switch (action) {
                case "ping":
                    reply.put("result", "pong");
                    break;

                case "get_device_info":
                    reply.put("result", new JSONObject()
                            .put("deviceId", deviceId())
                            .put("brand", Build.BRAND)
                            .put("model", Build.MODEL)
                            .put("sdk", Build.VERSION.SDK_INT));
                    break;

                default:
                    reply.put("error", "unknown action: " + action);
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

    /** Point this to your server. Choose ONE option below. */
    private String wsUrl() {
        // Option A (USB, easiest): use ADB reverse so phone can hit PC localhost
        //   adb reverse tcp:8080 tcp:8080
        // return "ws://127.0.0.1:8080/device?id=" + deviceId();

        // Option B (Wi-Fi/LAN): replace YOUR_PC_IP with your computer’s IPv4
        //   find with `ipconfig`, e.g. 192.168.1.50
        return "ws://YOUR_PC_IP:8080/device?id=" + deviceId();
    }

    // --------------------------------

    @Override
    public void onDestroy() {
        Log.i(TAG, "RemoteService.onDestroy");
        STARTED.set(false);
        try { if (socket != null) { socket.close(1000, "bye"); socket = null; } } catch (Throwable ignored) {}
        try { if (http != null) { http.dispatcher().executorService().shutdown(); } } catch (Throwable ignored) {}
        super.onDestroy();
    }

    @Override
    public android.os.IBinder onBind(Intent intent) { return null; }
}
