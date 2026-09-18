<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Alcove App 圖示">
  <h1>Alcove</h1>
</div>

<div align="center">
  <p>把常用的本機資料夾放進可移動、可調整大小的桌面面板。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <strong>繁體中文</strong> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

Alcove 是原生 macOS 選單列 App，能將選定的本機資料夾留在桌面上。面板位於一般 App 視窗下方、桌面圖示上方。它不是 Finder 的替代品，而是讓你隨時回到常用資料夾的入口。

## 功能

<table>
  <tr>
    <td width="32%"><strong>桌面資料夾面板</strong><br><br>在桌面上拖出面板，選擇資料夾後可移動、調整大小、固定或移除。每個面板最多可放四個資料夾分頁。</td>
    <td width="68%"><img src="images/readme/portal-overview.png" alt="包含兩個分頁和圖示格狀檢視的 Alcove 資料夾面板"></td>
  </tr>
  <tr>
    <td><strong>在面板中處理檔案</strong><br><br>瀏覽資料夾，使用接近 Finder 的選取、快速查看和拖放；右鍵選單可開啟、重新命名、複製、壓縮、移到垃圾桶、在 Finder 中顯示、透過 AirDrop 傳送和複製路徑。</td>
    <td><img src="images/readme/file-actions.png" alt="Alcove 檔案右鍵選單"></td>
  </tr>
  <tr>
    <td><strong>隨處建立</strong><br><br>直接在桌面上拖曳決定新面板大小，即時查看格狀預覽，再連接至資料夾。</td>
    <td><img src="images/readme/portal-creation.png" alt="帶格狀預覽的 Alcove 面板建立介面"></td>
  </tr>
  <tr>
    <td><strong>資料夾分頁</strong><br><br>每個面板最多可加入四個資料夾，可切換、排序或移除。每個分頁各自保留瀏覽位置與選取狀態。</td>
    <td align="center"><img src="images/readme/folder-tabs.png" width="420" alt="帶資料夾分頁的 Alcove 面板設定"></td>
  </tr>
  <tr>
    <td><strong>面板控制</strong><br><br>固定面板、變更排序方式、開啟設定，或將面板從桌面移除。</td>
    <td><img src="images/readme/panel-controls.png" alt="Alcove 面板控制選單"></td>
  </tr>
  <tr>
    <td><strong>外觀</strong><br><br>可調整內容大小、透明度、圓角、面板間距和視窗陰影。</td>
    <td align="center"><img src="images/readme/appearance-settings.png" width="420" alt="Alcove 外觀設定"></td>
  </tr>
  <tr>
    <td><strong>啟動和語言</strong><br><br>支援登入時啟動。介面可跟隨 macOS，也可選擇英文、簡體中文或繁體中文。</td>
    <td align="center"><img src="images/readme/language-settings.png" width="420" alt="Alcove 登入啟動和語言設定"></td>
  </tr>
</table>

## 下載和安裝

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask alcove@beta
```

### DMG

目前公開版本仍是 Beta。請從 [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases) 下載最新 DMG，開啟後將 `Alcove.app` 拖入 `Applications`。

這個 beta 版本使用 Apple Development 憑證簽署，但沒有經過公證。macOS 會為從網路下載的 App 加上隔離屬性，因此 Gatekeeper 可能阻止第一次開啟。如果你信任下載來源，請先按住 Control 點按 App 並選擇「打開」。若隔離屬性仍阻止啟動，可執行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

可用版本列在 [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases)，變更記錄見 [CHANGELOG.md](../CHANGELOG.md)。

## 系統需求和限制

| 項目 | 說明 |
|---|---|
| macOS | macOS 26 或以上版本 |
| Mac | Apple Silicon（`arm64`） |
| App 類型 | 選單列 App，不顯示 Dock 圖示 |
| 資料夾 | 僅支援內建非可移動磁碟上的本機資料夾 |
| 顯示器 | 面板會保留在主顯示器上 |

不支援外接式、可移動、可退出或網路磁碟。存取桌面、文件或下載等受保護位置時，macOS 可能要求授予 Alcove 權限。

## 從原始碼建置

安裝含 macOS 26 SDK 的 Xcode，然後複製儲存庫並建置共用 scheme：

```bash
git clone https://github.com/SlippinDylan/Alcove.git
cd Alcove
xcodebuild -project Alcove.xcodeproj -scheme Alcove -configuration Debug build
```

## 文件

| 文件 | 內容 |
|---|---|
| [產品需求](PRODUCT_REQUIREMENTS.md) | 產品範圍和互動約定 |
| [架構](ARCHITECTURE.md) | 元件、持久化和版面模型 |
| [開發指南](development.md) | 建置、測試、CI、發布和清理流程 |
| [研究記錄](RESEARCH.md) | 平台研究和引用來源 |
| [更新日誌](../CHANGELOG.md) | 發布歷史 |

## 授權條款

Copyright © 2025–2026 SlippinDylan Studio。Alcove 採用 [Apache License 2.0](../LICENSE) 開放原始碼授權條款。
