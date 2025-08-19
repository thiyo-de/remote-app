@echo off
setlocal
if not exist ".env" (
  echo No .env found. Copying .env.example to .env
  copy /Y .env.example .env >NUL
)
echo Starting RemoteAccessServer in watch mode...
node --watch server.js
