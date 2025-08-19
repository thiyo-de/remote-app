package com.remoteaccess;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

public class LauncherActivity extends Activity {
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Forward to SetupActivity (permission flow + start service)
        startActivity(new Intent(this, SetupActivity.class));
        finish(); // close the launcher activity
    }
}
