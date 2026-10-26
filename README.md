# DropSqueeze for macOS

DropSqueeze is a menu bar utility that compresses screenshots and recordings locally. It keeps source files intact and creates a sidecar output only when the result is smaller.

## Features

- Watches the clipboard for newly copied PNG, JPEG, HEIC, TIFF, and WebP images. It replaces the clipboard image only after successful compression and adds a private marker to prevent a processing loop. The previous clipboard image can be restored until the clipboard changes again.
- Handles Finder-copied image, MOV, and MP4 file URLs automatically. The clipboard is changed to the compressed copies only when at least one copy was produced.
- Watches user-authorized folders using security-scoped bookmarks. It processes files named like screenshots or recordings, and keeps the original file.
- Shows a floating drop zone near the top edge while dragging. A free user can drop one file at a time; batch drops open the Pro purchase screen.
- Re-encodes PNG and TIFF without lossy quality changes; JPEG, HEIC, and WebP use high quality lossy encoding. WebP output is enabled when the installed macOS image encoder supports it.
- Converts MOV and MP4 to a smaller 720p MP4. When the Pro GIF rule is enabled, MOV files up to 15 seconds are converted to a GIF with at most 30 frames per second. Results that are not smaller are discarded.
- Shows recent output, daily compression counts, total savings, and the current week's saved space. History is stored locally and can be cleared from Settings.

## Free and Pro

- Free: up to 15 successful automatic image compressions and 3 successful automatic video compressions per day, plus manual one-file drops.
- Pro: no automatic daily quotas, batch drops, multiple monitored folders, Retina 2× downscaling, WebP output, and MOV-to-GIF conversion.
- StoreKit 2 reads localized product names and prices from the App Store. The app uses these product identifiers:
  - `com.dropsqueeze.pro.annual` — auto-renewable annual subscription.
  - `com.dropsqueeze.pro.lifetime` — non-consumable lifetime purchase.
- Purchases are verified using StoreKit transactions. Restore uses `AppStore.sync()` and current entitlements; no payment credentials are handled by the app.

## Build

Open `DropSqueeze.xcodeproj`, select the `DropSqueeze` scheme, and build for macOS 13 or later. The project supports both Apple silicon and Intel Macs.

For a local purchase-flow check, create a StoreKit Configuration in Xcode with the two product identifiers above, assign annual subscription and non-consumable types, and select it under the scheme's Run options. For sandbox purchase testing, create and submit the products in App Store Connect first.

## Before App Store submission

1. Create the annual subscription group and the lifetime non-consumable product in App Store Connect. Set the localizations and prices there; the app intentionally does not hard-code prices.
2. Configure the App Store Connect privacy-policy URL and support contact. The in-app Settings screen includes a local privacy disclosure, but App Store listing metadata still needs a publicly accessible policy URL.
3. Configure the Developer Team, App Store provisioning, and distribution signing in Xcode. The checked-in target uses local ad-hoc signing for development; that identity cannot be submitted to the Mac App Store.
4. Complete sandbox purchase, restore, quota, folder-bookmark, and release smoke checks on supported macOS versions before submitting.

## Privacy and permissions

Media processing runs on the Mac. Clipboard content, source files, and compression history are not sent to a developer server. Clipboard monitoring and folder monitoring can be disabled in Settings. Folder access is granted by the user through `NSOpenPanel`; the app stores a security-scoped bookmark locally so access can be restored on later launches. StoreKit communicates with Apple for product and purchase state.

The app has no account system or analytics backend. Local preferences include monitoring toggles, folder bookmarks, quota counters, history, and aggregate space-saved statistics.
