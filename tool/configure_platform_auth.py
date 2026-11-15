#!/usr/bin/env python3
"""Apply native settings required by local_auth and the OCR plugin after flutter create."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]

info = root / "ios" / "Runner" / "Info.plist"
if info.exists():
    with info.open("rb") as stream:
        data = plistlib.load(stream)
    data["NSFaceIDUsageDescription"] = (
        "AI Scanner uses Face ID or your device passcode to protect scanned documents."
    )
    data["NSCameraUsageDescription"] = (
        "AI Scanner uses the camera to capture document pages on your device."
    )
    data["NSPhotoLibraryUsageDescription"] = (
        "AI Scanner accesses selected photos so you can import document pages."
    )
    with info.open("wb") as stream:
        plistlib.dump(data, stream)

podfile = root / "ios" / "Podfile"
if podfile.exists():
    text = podfile.read_text()
    text = re.sub(r"^# platform :ios, '.*'$", "platform :ios, '13.0'", text, flags=re.MULTILINE)
    if "platform :ios," not in text:
        text = "platform :ios, '13.0'\n" + text
    podfile.write_text(text)

pbxproj = root / "ios" / "Runner.xcodeproj" / "project.pbxproj"
if pbxproj.exists():
    text = pbxproj.read_text()
    text = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 13.0;", text)
    pbxproj.write_text(text)

manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
if manifest.exists():
    text = manifest.read_text()
    permission = '<uses-permission android:name="android.permission.USE_BIOMETRIC" />'
    if "android.permission.USE_BIOMETRIC" not in text:
        text = text.replace("<manifest", "<manifest", 1)
        close = text.find(">")
        text = text[: close + 1] + "\n    " + permission + text[close + 1 :]
    manifest.write_text(text)

for activity in (root / "android" / "app" / "src" / "main").rglob("MainActivity.kt"):
    text = activity.read_text()
    text = text.replace(
        "import io.flutter.embedding.android.FlutterActivity",
        "import io.flutter.embedding.android.FlutterFragmentActivity",
    )
    text = text.replace(": FlutterActivity()", ": FlutterFragmentActivity()")
    activity.write_text(text)

for activity in (root / "android" / "app" / "src" / "main").rglob("MainActivity.java"):
    text = activity.read_text()
    text = text.replace(
        "import io.flutter.embedding.android.FlutterActivity;",
        "import io.flutter.embedding.android.FlutterFragmentActivity;",
    )
    text = text.replace("extends FlutterActivity", "extends FlutterFragmentActivity")
    activity.write_text(text)

print("Native Face ID / biometric settings configured.")
