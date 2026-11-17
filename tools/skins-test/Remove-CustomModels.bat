@echo off
rem Custom models TEST build: takes the test files out again, the kit is the official one after.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0skins-test.ps1" -Remove
