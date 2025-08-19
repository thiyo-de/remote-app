package com.remoteaccess;

import android.util.Log;

import androidx.annotation.NonNull;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.TimeUnit;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

public class DeviceSocket {

    public interface Handler {
        void onMessage(JSONObject msg);
        void onOpen();
        void onClosed();
    }

    private static final String TAG = "RemoteAccess";

    private final OkHttpClient client;
    private final String url;
    private final Handler handler;
    private WebSocket ws;
    private Timer pingTimer;

    public DeviceSocket(String url, Handler handler) {
        this.url = url;
        this.handler = handler;
        this.client = new OkHttpClient.Builder()
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .pingInterval(20, TimeUnit.SECONDS)
                .retryOnConnectionFailure(true)
                .build();
    }

    public void connect() {
        Request req = new Request.Builder().url(url).build();
        ws = client.newWebSocket(req, new WebSocketListener() {
            @Override public void onOpen(@NonNull WebSocket webSocket, @NonNull Response response) {
                Log.i(TAG, "WS open");
                try {
                    JSONObject hello = new JSONObject()
                            .put("action", "hello")
                            .put("device", android.os.Build.MODEL);
                    sendJson(hello);
                } catch (JSONException e) {
                    Log.w(TAG, "JSON build failed on open: " + e.getMessage());
                }
                startHeartbeat();
                if (handler != null) handler.onOpen();
            }

            @Override public void onMessage(@NonNull WebSocket webSocket, @NonNull String text) {
                try {
                    JSONObject msg = new JSONObject(text);
                    if (handler != null) handler.onMessage(msg);
                } catch (JSONException e) {
                    Log.w(TAG, "WS invalid JSON: " + e.getMessage());
                }
            }

            @Override public void onClosed(@NonNull WebSocket webSocket, int code, @NonNull String reason) {
                Log.i(TAG, "WS closed: " + code + " " + reason);
                stopHeartbeat();
                if (handler != null) handler.onClosed();
                reconnectSoon();
            }

            @Override public void onFailure(@NonNull WebSocket webSocket, @NonNull Throwable t, Response r) {
                Log.w(TAG, "WS failure: " + t.getMessage());
                stopHeartbeat();
                if (handler != null) handler.onClosed();
                reconnectSoon();
            }
        });
    }

    private void reconnectSoon() {
        new Thread(() -> {
            try { Thread.sleep(3000); } catch (InterruptedException ignored) {}
            connect();
        }).start();
    }

    private void startHeartbeat() {
        stopHeartbeat();
        pingTimer = new Timer();
        pingTimer.scheduleAtFixedRate(new TimerTask() {
            @Override public void run() {
                try {
                    sendJson(new JSONObject().put("action", "ping"));
                } catch (JSONException ignored) {}
            }
        }, 15000, 15000);
    }

    private void stopHeartbeat() {
        if (pingTimer != null) { pingTimer.cancel(); pingTimer = null; }
    }

    public void sendJson(JSONObject obj) {
        try {
            if (ws != null) ws.send(obj.toString());
        } catch (Throwable t) {
            Log.w(TAG, "WS send failed: " + t.getMessage());
        }
    }

    public void close() {
        stopHeartbeat();
        if (ws != null) { ws.close(1000, "bye"); ws = null; }
    }
}
