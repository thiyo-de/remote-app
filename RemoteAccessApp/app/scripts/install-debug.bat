@echo off
cd /d %~dp0\..\..
adb install -r app\build\outputs\apk\debug\app-debug.apk
