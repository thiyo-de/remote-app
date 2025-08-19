# RemoteAccessApp (CLI-only, no launcher icon, no visible UI)
ECHO is off.
## Build and install (Windows CMD)
1. Install Java 11+ and Gradle on PATH.
2. In `RemoteAccessApp`, run: `gradle wrapper`
3. Build: `.\gradlew clean :app:assembleDebug`
4. Install: `app\scripts\install-debug.bat`
5. First run (no icon): `app\scripts\start-setup.bat`
ECHO is off.
On first run, approve: Notifications (Android 13+), Mic, Camera, Phone, Call Log.
Then Settings will open for: All Files Access (Android 11+) and Battery "Unrestricted".
The service starts foreground with a persistent notification.
