<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Alcove app icon">
  <h1>Alcove</h1>
</div>

<div align="center">
  <p>Keep the local folders you use most in movable, resizable panels on your Mac desktop.</p>
  <p>
    <a href="docs/README.zh-CN.md">简体中文</a> ·
    <a href="docs/README.zh-TW.md">繁體中文</a> ·
    <strong>English</strong> ·
    <a href="docs/README.ja.md">日本語</a> ·
    <a href="docs/README.ru.md">Русский</a>
  </p>
</div>

Alcove is a native macOS menu-bar app for keeping selected local folders visible on the desktop. A portal sits below regular app windows and above desktop icons. It is not a Finder replacement; it is a convenient surface for folders you return to throughout the day.

## Features

<table>
  <tr>
    <td width="32%"><strong>Desktop folder portals</strong><br><br>Draw a panel on the desktop, choose a folder, then move, resize, pin, or remove it. Each panel can contain up to four folder tabs.</td>
    <td width="68%"><img src="docs/images/readme/portal-overview.png" alt="An Alcove folder portal with two tabs and an icon grid"></td>
  </tr>
  <tr>
    <td><strong>File work without leaving the panel</strong><br><br>Browse folders and use Finder-style selection, Quick Look, drag and drop, and a contextual menu for opening, renaming, duplicating, compressing, trashing, revealing, sending with AirDrop, and copying paths.</td>
    <td><img src="docs/images/readme/file-actions.png" alt="Alcove file context menu"></td>
  </tr>
  <tr>
    <td><strong>Create where you need it</strong><br><br>Drag on the desktop to size a new portal with a live grid preview, then connect it to a folder.</td>
    <td><img src="docs/images/readme/portal-creation.png" alt="Alcove portal creation overlay with a grid preview"></td>
  </tr>
  <tr>
    <td><strong>Folder tabs</strong><br><br>Switch, reorder, or remove up to four folders in one portal. Each tab keeps its own browsing location and selection.</td>
    <td align="center"><img src="docs/images/readme/folder-tabs.png" width="420" alt="Alcove portal settings with folder tabs"></td>
  </tr>
  <tr>
    <td><strong>Panel controls</strong><br><br>Pin a portal, choose its sort order, open its settings, or remove it from the desktop.</td>
    <td><img src="docs/images/readme/panel-controls.png" alt="Alcove portal control menu"></td>
  </tr>
  <tr>
    <td><strong>Appearance</strong><br><br>Choose the content size, transparency, corner radius, panel spacing, and window shadow.</td>
    <td align="center"><img src="docs/images/readme/appearance-settings.png" width="420" alt="Alcove appearance settings"></td>
  </tr>
  <tr>
    <td><strong>Startup and language</strong><br><br>Launch Alcove at login. The interface can follow macOS or use English, Simplified Chinese, or Traditional Chinese.</td>
    <td align="center"><img src="docs/images/readme/language-settings.png" width="420" alt="Alcove general settings for launch at login and language"></td>
  </tr>
</table>

## Download and install

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask alcove@beta
```

### DMG

The current public builds are beta releases. Download the latest DMG from [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases), open it, and drag `Alcove.app` to `Applications`.

This beta is signed with an Apple Development certificate but is not notarized. macOS marks downloaded apps with a quarantine attribute, so Gatekeeper may prevent the first launch. If you trust the download, first try Control-clicking the app and choosing **Open**. If quarantine still blocks it, run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

Available releases are listed on [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases). Changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Requirements and limits

| Item | Details |
|---|---|
| macOS | macOS 26 or later |
| Mac | Apple Silicon (`arm64`) |
| App type | Menu-bar app; it does not show a Dock icon |
| Folders | Local folders on an internal, non-removable disk only |
| Display | Portals are kept on the primary display |

External, removable, ejectable, and network volumes are not supported. macOS may request permission before Alcove can access protected locations such as Desktop, Documents, or Downloads.

## Build from source

Install Xcode with the macOS 26 SDK, then clone the repository and build the shared scheme:

```bash
git clone https://github.com/SlippinDylan/Alcove.git
cd Alcove
xcodebuild -project Alcove.xcodeproj -scheme Alcove -configuration Debug build
```

## Documentation

| Document | Description |
|---|---|
| [Product requirements](docs/PRODUCT_REQUIREMENTS.md) | Product scope and interaction contract |
| [Architecture](docs/ARCHITECTURE.md) | Components, persistence, and layout model |
| [Research](docs/RESEARCH.md) | Platform research and cited sources |
| [Changelog](CHANGELOG.md) | Release history |

## License

Copyright © 2025–2026 SlippinDylan Studio. Alcove is licensed under the [Apache License 2.0](LICENSE).
