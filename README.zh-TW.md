<div align="center">
  <img src="docs/images/readme/app-icon.png" width="160" height="160" alt="Alcove App 圖示">
  <h1>Alcove</h1>
  <p>原生 macOS 選單列工具，可在桌面上放置、移動及調整資料夾面板。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <strong>繁體中文</strong> ·
    <a href="README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Alcove 是什麼

Alcove 會把本機資料夾顯示成桌面層上的輕量面板。每個面板都有原生圖示格狀檢視，可以捲動瀏覽，並支援多個分頁、接近 Finder 的選取操作、快速查看，以及顯示器配置變更後的自動復原。面板位於一般 App 視窗下方、桌面圖示上方。

**Alcove 不是 Finder 的替代品。** 它讓常用資料夾留在桌面上，需要時可以立即開啟。

## 功能

<table>
  <tr>
    <td width="32%">
      <strong>桌面資料夾面板</strong><br><br>
      把常用的本機資料夾放在桌面上。面板可以移動、調整大小，也可以用多個分頁切換資料夾。
    </td>
    <td width="68%"><img src="docs/images/readme/portal-overview.png" alt="顯示兩個分頁與原生圖示格狀檢視的 Alcove 資料夾面板"></td>
  </tr>
  <tr>
    <td>
      <strong>Finder 風格的檔案操作</strong><br><br>
      在原生右鍵選單中開啟、預覽、顯示位置、重新命名、壓縮、複製、移到垃圾桶、AirDrop、複製路徑，或在終端機中開啟。
    </td>
    <td><img src="docs/images/readme/file-actions.png" alt="包含常用檔案操作的 Alcove 右鍵選單"></td>
  </tr>
  <tr>
    <td>
      <strong>拖曳建立面板</strong><br><br>
      直接在桌面上拖出新面板。建立時會顯示即時格狀預覽，完成後再選擇 Mac 上的資料夾。
    </td>
    <td><img src="docs/images/readme/portal-creation.png" alt="帶有即時格狀預覽的 Alcove 面板建立介面"></td>
  </tr>
  <tr>
    <td>
      <strong>多個資料夾分頁</strong><br><br>
      每個面板最多可加入四個資料夾，並能切換、排序及移除。各分頁會保留自己的瀏覽位置與選取狀態。
    </td>
    <td align="center"><img src="docs/images/readme/folder-tabs.png" width="420" alt="顯示兩個資料夾分頁的 Alcove 面板設定"></td>
  </tr>
  <tr>
    <td>
      <strong>面板控制</strong><br><br>
      固定面板位置、更改排序方式、開啟面板設定，或從桌面移除面板。
    </td>
    <td><img src="docs/images/readme/panel-controls.png" alt="包含固定、排序、設定和刪除操作的 Alcove 面板選單"></td>
  </tr>
  <tr>
    <td>
      <strong>外觀設定</strong><br><br>
      調整透明度、內容大小、圓角、面板間距和視窗陰影。主要選項使用固定級距，方便維持一致。
    </td>
    <td align="center"><img src="docs/images/readme/appearance-settings.png" width="420" alt="包含透明度和面板樣式選項的 Alcove 外觀設定"></td>
  </tr>
  <tr>
    <td>
      <strong>語言與啟動</strong><br><br>
      支援登入時自動啟動。介面可跟隨 macOS，也可以單獨選擇英文、簡體中文或繁體中文。
    </td>
    <td align="center"><img src="docs/images/readme/language-settings.png" width="420" alt="包含登入啟動和 App 語言選項的 Alcove 一般設定"></td>
  </tr>
</table>

## 目前狀態

> **MVP 功能已完成**

App 主體、自動化測試和 arm64 建置檢查已完成。第一次公開發佈前仍需手動驗證最終 DMG 的安裝、Gatekeeper 行為，以及多顯示器、Spaces 和「幕前調度」環境下的系統表現。

## 系統需求

| 項目 | 需求 |
|---|---|
| 最低系統 | macOS 26 Tahoe |
| 相容目標 | macOS 26 和 macOS 27 Golden Gate |
| 處理器 | Apple Silicon（arm64） |
| App 類型 | 選單列 LSUIElement App，不顯示 Dock 圖示，不使用沙盒 |
| 資料夾範圍 | 僅支援內建固定磁碟上的本機資料夾 |
| 發佈方式 | GitHub Releases 提供一個經 Apple Development 簽署、未經公證的 DMG |

## 安裝與發佈

每個 GitHub Release 只包含一個 `Alcove.<版本號>.dmg`。開啟 DMG，把 `Alcove.app` 拖入 `Applications`。目前版本使用免費的 Apple Development 憑證簽署，但未經 Apple 公證。第一次開啟前，請依 Release Notes 的說明移除下載隔離屬性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

版本格式支援 `x.y.z`、`x.y.z-alpha.n` 和 `x.y.z-beta.n`。詳細變更請參閱 [CHANGELOG.md](CHANGELOG.md)。

## 主要設計

- 使用原生 AppKit，不使用 WidgetKit。
- 面板採用穩定的靜態半透明背景，支援五段透明度與每個面板獨立配色。
- 檔案選取、快速查看、拖放和右鍵選單盡量維持 Finder 的操作方式。
- 全域外觀與語言儲存在 `UserDefaults`；面板配置使用版本化 JSON 檔案儲存。
- 不包含遙測、分析或網路請求，所有狀態只儲存在本機。

## 文件

| 文件 | 內容 |
|---|---|
| [目前交接](docs/HANDOFF.md) | 目前需求、實作進度、已知風險和交接記錄 |
| [產品需求](docs/PRODUCT_REQUIREMENTS.md) | 產品目標、互動規則和驗收標準 |
| [架構](docs/ARCHITECTURE.md) | 模組邊界、資料模型、持久化和並行設計 |
| [研究記錄](docs/RESEARCH.md) | API 資料、技術驗證和參考專案 |
| [交付計畫](docs/DELIVERY_PLAN.md) | 開發階段、測試矩陣和發佈門檻 |

## 授權條款

Copyright © 2025–2026 SlippinDylan Studio。Alcove 採用 [Apache License 2.0](LICENSE) 開放原始碼授權條款。
