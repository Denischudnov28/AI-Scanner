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

# Android Russian OCR: use Tesseract4Android locally, without a network service.
# Flutter's generated settings.gradle.kts does not always declare
# dependencyResolutionManagement; in that case add JitPack to the root
# project's allprojects.repositories block instead.
jitpack_added = False
for settings in (root / "android" / "settings.gradle.kts", root / "android" / "settings.gradle"):
    if settings.exists():
        text = settings.read_text()
        marker = "dependencyResolutionManagement {"
        if marker in text and "https://jitpack.io" not in text:
            start = text.index(marker)
            repo_marker = "repositories {"
            repo_start = text.find(repo_marker, start)
            if repo_start >= 0:
                insert_at = repo_start + len(repo_marker)
                if settings.name.endswith(".kts"):
                    repository = '\\n            maven { url = uri("https://jitpack.io") }'
                else:
                    repository = "\\n            maven { url 'https://jitpack.io' }"
                text = text[:insert_at] + repository + text[insert_at:]
                settings.write_text(text)
                jitpack_added = True
                break

if not jitpack_added:
    root_gradle = root / "android" / "build.gradle.kts"
    if root_gradle.exists():
        text = root_gradle.read_text()
        if "https://jitpack.io" not in text:
            match = re.search(r"allprojects\\s*\\{\\s*repositories\\s*\\{", text)
            if not match:
                raise RuntimeError("Could not find allprojects.repositories in android/build.gradle.kts")
            insert_at = match.end()
            text = text[:insert_at] + '\\n        maven { url = uri("https://jitpack.io") }' + text[insert_at:]
            root_gradle.write_text(text)
            jitpack_added = True
        else:
            jitpack_added = True

if not jitpack_added:
    raise RuntimeError("Could not configure JitPack in generated Android Gradle files")

app_gradle = root / "android" / "app" / "build.gradle.kts"
if app_gradle.exists():
    text = app_gradle.read_text()
    if "tesseract4android:tesseract4android" not in text:
        text += (
            '\n\ndependencies {\n'
            '    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")\n'
            '}\n'
        )
        app_gradle.write_text(text)

for activity in (root / "android" / "app" / "src" / "main").rglob("MainActivity.kt"):
    package_match = re.search(r"^package\s+[\w.]+", activity.read_text(), re.MULTILINE)
    package_line = package_match.group(0) if package_match else "package com.example.ai_scanner"
    activity.write_text(
        package_line
        + '''

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "ai_scanner/russian_ocr"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "recognizeRussian") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val imagePath = call.argument<String>("imagePath")
                if (imagePath.isNullOrBlank()) {
                    result.error("BAD_ARGUMENT", "Image path is missing", null)
                    return@setMethodCallHandler
                }
                Thread {
                    var api: TessBaseAPI? = null
                    try {
                        val root = File(filesDir, "ai_scanner_tesseract")
                        val data = File(root, "tessdata")
                        if (!data.exists()) data.mkdirs()
                        val model = File(data, "rus.traineddata")
                        if (!model.exists()) {
                            assets.open("tessdata/rus.traineddata").use { input ->
                                model.outputStream().use { output -> input.copyTo(output) }
                            }
                        }
                        api = TessBaseAPI()
                        if (!api.init(root.absolutePath, "rus")) {
                            throw IllegalStateException("Не удалось загрузить русскую OCR-модель")
                        }
                        val bitmap = BitmapFactory.decodeFile(imagePath)
                            ?: throw IllegalArgumentException("Не удалось открыть изображение")
                        try {
                            api.setImage(bitmap)
                            val recognized = api.getUTF8Text() ?: ""
                            Handler(Looper.getMainLooper()).post { result.success(recognized) }
                        } finally {
                            bitmap.recycle()
                        }
                    } catch (error: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("OCR_FAILED", error.message, null)
                        }
                    } finally {
                        api?.recycle()
                    }
                }.start()
            }
    }
}
'''
    )

print("Native Face ID / biometric settings and offline Russian Android OCR configured.")
