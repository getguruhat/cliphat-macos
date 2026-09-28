# ClipHat

**Your clipboard, always at hand.**

ClipHat is a native macOS clipboard-history utility from GuruHat. It stores recent text, links, images, and documents locally so they can be found, copied, restored, or dragged into another app such as Codex.

It is built with Swift, SwiftUI, AppKit, and SQLite. It has no accounts, cloud service, analytics, or downloaded runtime dependencies.

## Features

- Capture clipboard text, web links, images, PDFs, DOCX, CSV, XLSX, and other regular files.
- Search clipboard history and filter it by all items, text, links, images, documents, or audio.
- Restore an item with a click or Return, then paste with `⌘V` in the previous app.
- Open copied web links directly in the default browser.
- Drag text, links, images, and documents out of ClipHat. Images and documents are exported as real files, which can be dropped into Codex or Finder.
- Preserve original file names and paths for copied Finder files. Hover a card to view its stored path.
- Display thumbnails for images and Quick Look previews for supported documents.
- Switch between compact cards and enlarged image/document preview cards from the bottom toolbar or Settings. Compact is the default.
- In enlarged top/bottom panels, consecutive text and link cards stack in pairs to use the available space.
- Use light, dark, or system appearance.
- Attach the panel to the left, right, top, or bottom of the active screen.
- Keep the panel open, pause capture, clear history, pin important entries, and configure retention from the app.
- Launch ClipHat at login.

## Use

Copy an item, then press **⌘⇧V** to open ClipHat. Use the filter icons, search when needed, select an entry, and press **Return** or click it to restore it.

- **Esc:** close the picker.
- **⌘F:** show and focus search.
- **⌘Delete:** delete the selected entry.
- **Right-click a card:** copy, pin/unpin, or delete it.
- **Bottom toolbar:** toggle compact/large previews, pause/resume capture, keep the panel open, and open Settings.
- **Large-preview toggle:** enlarges only image and document cards; text and links remain compact.

Document and image cards can be dragged directly from ClipHat into Codex. Clicking a document card also places a real exported file on the pasteboard.

## Settings

Settings let you choose:

- System, light, or dark appearance.
- Left, right, top, or bottom panel placement.
- Compact or 2× image/document previews.
- Retained history count, from 10 to 5,000 items.
- Whether ClipHat stores text, links, images, and documents/files.
- Apps that ClipHat should ignore.
- Launch-at-login behavior.

## File behavior and limits

ClipHat stores regular files, not folders or app bundles. It captures images up to 10 MB and documents/other files up to 20 MB. Unsupported, unreadable, oversized, or folder selections are skipped with an error instead of being mistaken for image previews.

Copied files are stored locally so they remain usable if the original file is moved or deleted. File paths are retained as metadata and are updated when the same file contents are copied from a new location. Exported drag files receive unique temporary directories so files with the same name never overwrite one another.

Quick Look provides document previews when macOS supports the file type. A standard document icon is shown when no preview is available.

## Build and run

Requires macOS 13 or later and Apple Swift command-line tools (Swift 5.9 or later).

### Install the latest build

Download the ready-to-install package: [ClipHat-1.0.2-install.dmg](ClipHat-1.0.2-install.dmg).

Open the DMG, drag **ClipHat** to Applications, and launch it. macOS may ask you to confirm opening an ad-hoc signed app built for this Mac.

```sh
./build-app.sh
open ClipHat.app
```

To install locally:

```sh
ditto --rsrc --extattr --acl ClipHat.app /Applications/ClipHat.app
open /Applications/ClipHat.app
```

Run the test suite with:

```sh
./test.sh
```

The app is locally ad-hoc signed for the current Mac architecture. Distribution to other Macs requires Developer ID signing and notarization.

## Storage and privacy

History is local at `~/Library/Application Support/GuruHat/ClipHat/history.sqlite`. Preferences use the `com.guruhat.ClipHat` domain. The database has owner-only file permissions, but is not application-encrypted; it is protected by the Mac's disk encryption and backup policies.

The default history limit is 500 items. The oldest unpinned entries are removed first. Pins can exceed the configured count. Text and URLs are limited to 1 MiB per item; images to 10 MB; documents and other files to 20 MB. Unpinned image and file payloads share a 200 MB budget. Pinned payloads are exempt.

ClipHat checks the clipboard every 750 ms and only reads changed content. It does not import clipboard content present before launch or resume, so very brief clipboard changes can be missed.

The privacy filter skips transient, concealed, auto-generated, and known sensitive clipboard markers. Common password-manager apps are ignored by default, and additional apps can be excluded in Settings. Filters affect future captures; clearing existing history is separate.

No network code is included.

## Architecture

- `ClipHatCore/ClipboardItem`: history model and privacy policy.
- `ClipHatCore/HistoryDatabase`: SQLite persistence, deduplication, retention, and deletion.
- `ClipboardStore`: serialized storage, thumbnails, previews, drag exports, and metadata.
- `ClipboardMonitor`: clipboard polling, file detection, privacy filtering, capture, and restoration.
- `ClipboardHistoryView` and `PickerController`: panel layout, filters, cards, search, preview modes, and keyboard navigation.
- `Preferences` and `SettingsView`: local app preferences and configuration UI.
