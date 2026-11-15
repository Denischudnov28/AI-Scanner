# AI Scanner

Privacy-first document scanner prototype for iPhone and Android.

## Implemented in the current prototype

- Import document pages from the camera or photo library.
- Organize multiple pages in one document and remove unwanted pages (also deletes the encrypted page file).
- Detect document edges and correct perspective locally during photo import; if detection fails, preserve the original image.
- Verify AES-GCM encryption, per-file nonce uniqueness, tamper detection, and malformed-key handling with unit tests.
- Export pages to a PDF and share it.
- Run on-device OCR on an individual page and copy the recognized text. iOS uses Apple Vision; Android uses the bundled Russian Tesseract model offline.
- Encrypt stored page images locally with AES-256-GCM; keep the encryption key in iOS Keychain / Android Keystore via secure storage.
- Require Face ID / Touch ID or the device passcode before opening the local vault.
- Hide document previews when the app becomes inactive and require re-authentication after it is backgrounded.
- Remove stale OCR/PDF temporary files on the next app launch after an interrupted operation.

## Important limitations

- Russian OCR on Android is implemented with Tesseract4Android and the `rus` model bundled into the APK; it runs locally without a network request. iOS uses Apple Vision's on-device text recognition. OCR quality, memory use, and processing speed still need testing on physical devices and varied document photos.
- Automatic edge detection and perspective correction run on imported still images; live camera edge tracking, manual corner adjustment, and document-wide text search are not implemented yet.
- App-switcher privacy masking and re-authentication on background/foreground transitions are implemented in Flutter lifecycle handling but still require real-device testing. iOS does not provide a general guarantee against screenshots taken while the app is actively visible.
- OCR temporarily decrypts a page to an app temporary file; PDF export creates a readable PDF in temporary storage for sharing. These temporary files are not encrypted by the current prototype.
- This is an early development scaffold, not a production-ready medical-document storage product. Do not store sensitive patient information in this prototype until security review, real-device testing, backup behavior review, and release hardening are complete.
- No signed release build or physical-device test has been completed yet.

## Build

Install Flutter, generate the native platform projects, then run:

```sh
flutter create --platforms=android,ios --project-name ai_scanner .
python3 tool/configure_platform_auth.py
flutter pub get
flutter analyze
flutter run
```

The CI pipeline generates platform projects and verifies Android and iOS simulator builds. iOS builds require macOS and Xcode. Installing on a physical iPhone requires an Apple Developer signing certificate and a matching provisioning profile; the current simulator artifact is not installable on a physical iPhone.
