# AI Scanner

Privacy-first document scanner prototype for iPhone and Android.

## Implemented in the current prototype

- Import document pages from the camera or photo library.
- Organize multiple pages into named documents, move pages between documents without re-encrypting their image data, and remove unwanted pages (also deletes the encrypted page file).
- Save encrypted pages through an atomic staging-file rename; interrupted writes are ignored and cleaned up on the next unlock.
- Detect document edges and correct perspective locally during photo import; if detection fails, preserve the original image.
- Verify AES-GCM encryption, per-file nonce uniqueness, tamper detection, and malformed-key handling with unit tests.
- Export pages to a PDF and share it.
- Convert selected JPG/PNG images into a multi-page PDF locally, and render PDF pages into JPG images on-device for sharing or saving.
- Run on-device OCR on an individual page and copy the recognized text. iOS uses Apple Vision; Android uses the bundled Russian Tesseract model offline.
- Encrypt stored page images locally with AES-256-GCM; protect the AES key itself with OS authentication: iOS Keychain access control (`userPresence`, Face ID / Touch ID or device passcode, Secure Enclave-backed protection where available) and Android Keystore biometric storage.
- Protect the AES key at rest with OS authentication and drop its in-memory Dart reference when the app is backgrounded. iOS Keychain `userPresence` is checked when the key is read. Android uses `flutter_secure_storage` v11.2 with `requireBiometricsPerOperation: true`, requesting authentication for each protected-storage operation. Dart does not guarantee immediate zeroization of previously allocated memory.
- Migrate the existing AES key to a new authentication-gated storage entry without changing the key; verify the protected copy before deleting the legacy copy. If authentication or verification fails, keep the legacy key and leave the vault locked.
- Disable Android app backup so device-bound Keystore material is not restored without its matching key.
- Hide document previews when the app becomes inactive and require re-authentication after it is backgrounded.
- Remove stale OCR/PDF temporary files on the next app launch after an interrupted operation.

## Converter scope and limitations

- The first converter version supports JPG/PNG to PDF and PDF to JPG on iOS and Android. Output is passed to the native share sheet, where it can be saved to Files or shared.
- PDF-to-image conversion rasterizes each page; selectable text and vector content are not preserved in JPG output. PDF input is limited to 100 pages per operation to control memory use.
- DOCX-to-PDF, PDF merging/splitting, and PNG export from PDF are not included in this first version.

## Important limitations

- Russian OCR on Android is implemented with Tesseract4Android and the `rus` model bundled into the APK; it runs locally without a network request. iOS uses Apple Vision's on-device text recognition. OCR quality, memory use, and processing speed still need testing on physical devices and varied document photos.
- Automatic edge detection and perspective correction run on imported still images; live camera edge tracking, manual corner adjustment, and document-wide text search are not implemented yet.
- App-switcher privacy masking and Dart-key clearing on background/foreground transitions are implemented in Flutter lifecycle handling but still require real-device testing. Android biometric key protection requires API 28 or newer; Android 11+ supports the configured biometric-or-device-credential policy, while Android 9–10 may require a strong biometric. iOS does not provide a general guarantee against screenshots taken while the app is actively visible.
- OCR temporarily decrypts a page to an app temporary file; PDF export creates a readable PDF in temporary storage for sharing. These temporary files are not encrypted by the current prototype.
- The protected-key migration and authentication-gated storage are covered by unit tests and CI builds. Face ID / Touch ID / Android Keystore behavior, including the v10-to-v11 storage migration and per-operation prompt behavior, has not yet been exercised on physical devices. This is an early development prototype, not a production-ready secure document vault. Do not store highly sensitive documents until independent security review, real-device testing, backup behavior review, and release hardening are complete.
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
