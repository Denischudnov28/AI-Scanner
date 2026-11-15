# AI Scanner

Privacy-first document scanner prototype for iPhone and Android.

## Implemented in the current prototype

- Import document pages from the camera or photo library.
- Organize multiple pages in one document and remove unwanted pages (also deletes the encrypted page file).
- Export pages to a PDF and share it.
- Run on-device OCR on an individual page and copy the recognized text.
- Encrypt stored page images locally with AES-256-GCM; keep the encryption key in iOS Keychain / Android Keystore via secure storage.
- Require Face ID / Touch ID or the device passcode before opening the local vault.
- Hide document previews when the app becomes inactive and require re-authentication after it is backgrounded.
- Remove stale OCR/PDF temporary files on the next app launch after an interrupted operation.
- OCR uses native on-device frameworks (Apple Vision on iOS and ML Kit on Android); images are not uploaded to a cloud service by this feature.

## Important limitations

- OCR accuracy must be verified on real devices. The current plugin does not expose language selection. Its Android ML Kit implementation uses the Latin recognizer by default, so Russian/Cyrillic OCR is not supported on Android in this prototype; a separate offline Cyrillic OCR engine is required. iOS uses Apple Vision, but Russian recognition still needs real-device testing.
- Perspective correction, automatic edge detection, and document-wide text search are not implemented yet.
- App-switcher privacy masking and re-authentication on background/foreground transitions are implemented in Flutter lifecycle handling but still require real-device testing. iOS does not provide a general guarantee against screenshots taken while the app is actively visible.
- OCR temporarily decrypts a page to an app temporary file; PDF export creates a readable PDF in temporary storage for sharing. These temporary files are not encrypted by the current prototype.
- This is an early development scaffold, not a production-ready medical-document storage product. Do not store sensitive patient information in this prototype until security review, real-device testing, backup behavior review, and release hardening are complete.
- No release build or device test has been completed yet.

## Build

Install Flutter, then run:

```sh
flutter pub get
flutter analyze
flutter run
```

iOS builds require macOS and Xcode. The OCR plugin supports iOS 13+ and Android; Android build settings may need compileSdk 35 and Java 11 or newer.