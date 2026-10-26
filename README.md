# DropSqueeze for macOS

DropSqueeze is a menu bar utility that compresses screenshots and recordings locally. It keeps source files intact and creates a sidecar output only when the result is smaller.

## Features

- Watches the clipboard for newly copied PNG, JPEG, HEIC, TIFF, WebP, and GIF images. It replaces the clipboard image only after successful compression and adds a private marker to prevent a processing loop. The previous clipboard image can be restored until the clipboard changes again.
- Handles Finder-copied image, MOV, MP4, and M4V file URLs automatically. The clipboard is changed to the compressed copies only when at least one copy was produced.
- Watches user-authorized folders using security-scoped bookmarks. Each folder can select a built-in or saved compression profile in addition to its media, recursion, filename, size, and naming rules; the original file stays intact.
- Shows a floating drop zone near the top edge while dragging. A free user can drop one file at a time; batch drops open the Pro purchase screen.
- Re-encodes PNG and TIFF without lossy quality changes; JPEG, HEIC, and WebP use adjustable quality. Static file images can be converted to JPEG, HEIC, PNG, or WebP; animated GIFs retain their frames and stay GIF. Image output can be resized to a maximum long edge and can strip EXIF, GPS, and comments. Clipboard WebP and file WebP output have independent Pro settings and require a macOS image encoder that supports WebP.
- Converts MOV, MP4, and M4V using a selectable 720p or 1080p preset. Optional 10 MB, 25 MB, or custom 1–5,000 MB limits trigger lower-output retries and a final size check; the original stays in place if the target cannot be reached or the result is not smaller. When the Pro GIF rule is enabled, MOV files up to 15 seconds are converted to a GIF with at most 30 frames per second.
- Can show an optional completion notification with before/after sizes. Clipboard notifications include an undo action that restores the prior clipboard contents if nothing has replaced them since.
- Shows live video progress for manual jobs, queues multiple drops, can stop the remaining queue, and offers Open or Reveal in Finder actions for recent outputs.
- Offers one-click compression scenes for balanced daily use, chat sharing, email attachments, web images, and high-detail archiving. WebP scene settings are Pro-gated; custom profiles can also be saved and reused.
- Lets users choose a persistent output folder for dropped, monitored, and Shortcuts files; by default, each result stays beside its source. The original remains unchanged in either mode.
- Provides a “压缩媒体文件” App Intents action for Shortcuts. Use it in a personal shortcut or a Finder Quick Action; it returns compressed copies and preserves the source files. Free users can process one file per action; batch processing requires Pro.
- Pro can optimize embedded images in PDFs while retaining text and vector content. Encrypted and digitally signed PDFs are skipped, and the source is always preserved.
- Shows recent output, daily compression counts, total savings, and the current week's saved space. History is stored locally and can be cleared from Settings.
- Shows actual format, dimensions, video codec, frame rate, audio-track presence, or PDF page count in the before/after comparison when the source can be inspected.

## Free and Pro

- Free: up to 15 successful automatic image compressions and 3 successful automatic video compressions per day, plus manual one-file drops.
- Pro: no automatic daily quotas, batch drops, multiple monitored folders, Retina 2× downscaling, separate clipboard and file WebP output rules, MOV-to-GIF conversion, and PDF compression.
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

The app has no account system or analytics backend. Local preferences include monitoring toggles, input and output folder bookmarks, image and video settings, quota counters, history, and aggregate space-saved statistics.

## Finder Quick Action

Create a shortcut in the macOS Shortcuts app, set it to receive files from Finder, add the “压缩媒体文件” DropSqueeze action, choose a built-in scene or saved profile, and optionally set a video size limit or output location. Enable “Use as Quick Action” to run it from Finder. The action returns compressed copies and never replaces the selected files.
