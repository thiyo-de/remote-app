package com.remoteaccess;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;

/** Starts RemoteService after boot, with a tiny delay to avoid OEM race conditions. */
public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "RemoteAccess";

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.i(TAG, "BootReceiver onReceive: " + (intent != null ? intent.getAction() : "null"));

        // Do work off the main thread and finish the pending result later.
        final PendingResult pr = goAsync();
        new Thread(() -> {
            try { Thread.sleep(1200); } catch (InterruptedException ignored) {}

            Intent svc = new Intent(context, RemoteService.class);
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(svc);
                else context.startService(svc);
                Log.i(TAG, "BootReceiver: requested start of RemoteService");
            } catch (Throwable t) {
                Log.w(TAG, "BootReceiver: startForegroundService failed: " + t.getMessage());
            } finally {
                pr.finish();
            }
        }).start();
    }
}
