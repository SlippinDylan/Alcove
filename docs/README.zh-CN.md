<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Alcove 应用图标">
  <h1>Alcove</h1>
</div>

---

<div align="center">
  <p>把常用的本地文件夹放进可移动、可调整大小的桌面面板。</p>
  <p>
    <strong>简体中文</strong> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

Alcove 是一款原生 macOS 菜单栏应用，用来把选定的本地文件夹留在桌面上。面板位于普通应用窗口下方、桌面图标上方。它不是 Finder 的替代品，而是方便你随时回到常用文件夹的入口。

## 功能

<table>
  <tr>
    <td width="32%"><strong>桌面文件夹面板</strong><br><br>在桌面上拖出面板，选择文件夹后可移动、调整大小、固定或移除。每个面板最多可放四个文件夹标签页。</td>
    <td width="68%"><img src="images/readme/portal-overview.png" alt="包含两个标签页和图标网格的 Alcove 文件夹面板"></td>
  </tr>
  <tr>
    <td><strong>在面板中处理文件</strong><br><br>浏览文件夹，使用接近 Finder 的选择、快速查看和拖放；右键菜单可打开、重命名、复制、压缩、移到废纸篓、在 Finder 中显示、通过 AirDrop 发送和复制路径。</td>
    <td><img src="images/readme/file-actions.png" alt="Alcove 文件右键菜单"></td>
  </tr>
  <tr>
    <td><strong>按需要创建</strong><br><br>直接在桌面上拖动确定新面板的大小，实时查看网格预览，再连接到文件夹。</td>
    <td><img src="images/readme/portal-creation.png" alt="带网格预览的 Alcove 面板创建界面"></td>
  </tr>
  <tr>
    <td><strong>文件夹标签页</strong><br><br>每个面板最多可添加四个文件夹，可切换、排序或移除。每个标签页各自保留浏览位置和选择状态。</td>
    <td align="center"><img src="images/readme/folder-tabs.png" width="420" alt="带文件夹标签页的 Alcove 面板设置"></td>
  </tr>
  <tr>
    <td><strong>面板控制</strong><br><br>固定面板、更改排序方式、打开设置，或将面板从桌面移除。</td>
    <td><img src="images/readme/panel-controls.png" alt="Alcove 面板控制菜单"></td>
  </tr>
  <tr>
    <td><strong>外观</strong><br><br>可调整内容大小、透明度、圆角、面板间距和窗口阴影。</td>
    <td align="center"><img src="images/readme/appearance-settings.png" width="420" alt="Alcove 外观设置"></td>
  </tr>
  <tr>
    <td><strong>启动和语言</strong><br><br>支持登录时启动。界面可以跟随 macOS，也可选择英文、简体中文或繁体中文。</td>
    <td align="center"><img src="images/readme/language-settings.png" width="420" alt="Alcove 登录启动和语言设置"></td>
  </tr>
</table>

## 下载和安装

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask alcove@beta
```

### DMG

当前公开版本仍是 Beta。请从 [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases) 下载最新 DMG，打开后将 `Alcove.app` 拖入 `Applications`。

这个 beta 版本使用 Apple Development 证书签名，但没有经过公证。macOS 会为从网络下载的应用添加隔离属性，因此 Gatekeeper 可能阻止首次打开。如果你信任下载来源，先按住 Control 点按应用并选择“打开”。若隔离属性仍阻止启动，可运行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

可用版本列在 [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases)，变更记录见 [CHANGELOG.md](../CHANGELOG.md)。

## 系统要求和限制

| 项目 | 说明 |
|---|---|
| macOS | macOS 26 或更高版本 |
| Mac | Apple Silicon（`arm64`） |
| 应用类型 | 菜单栏应用，不显示 Dock 图标 |
| 文件夹 | 仅支持内置非可移动磁盘上的本地文件夹 |
| 显示器 | 面板会保留在主显示器上 |

不支持外置、可移动、可弹出或网络磁盘。访问桌面、文稿或下载等受保护位置时，macOS 可能要求授予 Alcove 权限。

## 从源码构建

安装带有 macOS 26 SDK 的 Xcode，然后克隆仓库并构建共享 scheme：

```bash
git clone https://github.com/SlippinDylan/Alcove.git
cd Alcove
xcodebuild -project Alcove.xcodeproj -scheme Alcove -configuration Debug build
```

## 文档

| 文档 | 内容 |
|---|---|
| [产品需求](PRODUCT_REQUIREMENTS.md) | 产品范围和交互约定 |
| [架构](ARCHITECTURE.md) | 组件、持久化和布局模型 |
| [研究记录](RESEARCH.md) | 平台研究和引用来源 |
| [更新日志](../CHANGELOG.md) | 发布历史 |

## 许可证

Copyright © 2025–2026 SlippinDylan Studio。Alcove 使用 [Apache License 2.0](../LICENSE) 开源许可证。
