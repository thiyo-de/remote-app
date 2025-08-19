@echo off
cd /d %~dp0\..\..
.\gradlew clean :app:assembleDebug
