package com.remoteaccess;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.core.app.NotificationCompat;

public class RemoteService extends Service {

    private static final String TAG = "RemoteAccess";
    private static final String CH  = "remote_access_chan";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "RemoteService.onCreate: creating notification channel");

        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CH,
                    "RemoteAccess",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Foreground service for RemoteAccess");
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.i(TAG, "RemoteService.onStartCommand: posting foreground notification ASAP");

        // --- OPTIONAL: brief wakelock to keep CPU on during boot start ---
        // If you keep this, add to AndroidManifest:
        // <uses-permission android:name="android.permission.WAKE_LOCK"/>
        PowerManager.WakeLock wl = null;
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null) {
                wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "RemoteAccess:bootStart");
                wl.acquire(5000); // auto-release after 5s
            }
        } catch (Throwable t) {
            Log.w(TAG, "Wakelock acquire failed (safe to ignore): " + t.getMessage());
        }
        // -----------------------------------------------------------------

        // Build & post the ongoing foreground notification immediately
        Notification n = new NotificationCompat.Builder(this, CH)
                .setContentTitle("RemoteAccess is active")
                .setContentText("Running as a foreground service")
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setOngoing(true)
                .build();
        startForeground(1, n);
        Log.i(TAG, "RemoteService.onStartCommand: now running in FOREGROUND");

        // Defer heavy initialization slightly (helps right after boot)
        mainHandler.postDelayed(this::initAsync, 2000);

        return START_STICKY; // ask system to restart us if killed
    }

    /** Put your real startup (sockets, WS, managers) here. Runs a bit after boot. */
    private void initAsync() {
        Log.i(TAG, "RemoteService.initAsync: start managers / network here");
        // TODO: connect WebSocket, start file/mic/camera managers, etc.
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "RemoteService.onDestroy");
        super.onDestroy();
    }

    @Override
    public android.os.IBinder onBind(Intent intent) {
        return null; // not a bound service
    }
}
