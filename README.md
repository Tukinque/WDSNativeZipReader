# WDS Native Zip Reader (iPad)

This is an **uncompiled prototype**, not a tested iOS application. It is designed to keep the original `resources.zip` as a ZIP archive, open it through ZIPFoundation, and serve files to WKWebView via a loopback HTTP server (Swifter). It does **not** need to unpack all 5.84 GB.

## Requirements
- macOS + Xcode (iOS build/signing)
- XcodeGen (`brew install xcodegen`)
- iPadOS 16+
- `resources.zip` with `index.html`, `data/manifest/Episode.json`, `adv-player/index.html` at archive root

## Build
1. Open Terminal in this folder.
2. Run `xcodegen generate`.
3. Open `WDSNativeZipReader.xcodeproj` with Xcode.
4. Select your signing team and an iPad target, then build and install.
5. In the app, choose `resources.zip` from Files. The archive is copied into app Documents; leave at least 6 GB of free space, and potentially twice that during copying.

## Implementation notes
- ZIPFoundation is used to extract individual entries **in memory on request**; full ZIP extraction is avoided. Large entries may still cause high memory use; this prototype has no streaming/range support or cache.
- `assets/android-overrides/` from the supplied APK is included as reference in `WDSNative/Overrides`, but **not enabled**: the Android-specific JS bridge is not implemented on iOS.
- The original site may reference external APIs or require extra adjustments; full offline playback is **not yet verified**.
- iOS audio/background behavior and app lifecycle require real-device testing.
- This project has not been compiled in Xcode in this environment. Some dependency APIs may require adaptation.
- If `resources.zip` has a wrapper folder or only contains `data/`, rebuild the ZIP with the website files at the root. `scripts/check_zip.py` helps inspect structure.
- Respect the original creators' licenses and content rights; this is a local personal-use development prototype.
