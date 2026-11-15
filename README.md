# AI Scanner

Privacy-first document scanner prototype for iPhone and Android.

## Current prototype
- Import document pages from the camera or photo library.
- Organize multiple pages in one document.
- Export pages to a PDF and share it.
- Keep imported page files locally on the device; no automatic cloud upload.

## Planned / not yet implemented
- On-device Russian OCR and searchable text.
- Perspective correction and automatic edge detection.
- Production-grade encrypted storage and biometric app lock.
- App Store / Google Play signing, release builds, subscriptions.

This repository contains an early development scaffold, not a production-ready medical-document storage product. Do not store sensitive patient information in this prototype.

## Build
Install Flutter, then run `flutter pub get` and `flutter run`. iOS release builds require macOS and Xcode.
