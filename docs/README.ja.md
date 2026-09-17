<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Alcove のアプリアイコン">
  <h1>Alcove</h1>
  <p>フォルダを移動・サイズ変更可能なパネルとしてデスクトップに配置する、macOS ネイティブのメニューバーアプリです。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <strong>日本語</strong> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Alcove について

Alcove は、ローカルフォルダを軽量なパネルとしてデスクトップレイヤーに表示します。各パネルにはスクロール可能なネイティブのアイコングリッドがあり、複数タブ、Finder に近い選択操作、クイックルック、ディスプレイ構成が変わったときの配置復元に対応しています。パネルは通常のアプリウインドウより下、デスクトップアイコンより上に表示されます。

**Alcove は Finder の代替ではありません。** よく使うフォルダをデスクトップからすぐ開くためのアプリです。

## 機能

<table>
  <tr>
    <td width="32%">
      <strong>デスクトップのフォルダパネル</strong><br><br>
      よく使うローカルフォルダをデスクトップに常駐させます。パネルは移動やサイズ変更ができ、複数のタブも利用できます。
    </td>
    <td width="68%"><img src="images/readme/portal-overview.png" alt="2 つのタブとネイティブのアイコングリッドを表示する Alcove パネル"></td>
  </tr>
  <tr>
    <td>
      <strong>Finder に近いファイル操作</strong><br><br>
      ネイティブのコンテキストメニューから、開く、プレビュー、Finder で表示、名前変更、圧縮、複製、ゴミ箱へ移動、AirDrop、パスのコピー、ターミナルで開く操作を実行できます。
    </td>
    <td><img src="images/readme/file-actions.png" alt="ファイル操作を表示する Alcove のコンテキストメニュー"></td>
  </tr>
  <tr>
    <td>
      <strong>ドラッグしてパネルを作成</strong><br><br>
      デスクトップ上をドラッグして新しいパネルを作ります。作成中はグリッドをプレビューでき、確定後に Mac 上のフォルダを選択します。
    </td>
    <td><img src="images/readme/portal-creation.png" alt="グリッドのプレビューを表示する Alcove のパネル作成画面"></td>
  </tr>
  <tr>
    <td>
      <strong>複数のフォルダタブ</strong><br><br>
      1 つのパネルに最大 4 個のフォルダを追加し、切り替え、並べ替え、削除ができます。閲覧位置と選択状態はタブごとに保持されます。
    </td>
    <td align="center"><img src="images/readme/folder-tabs.png" width="420" alt="2 つのフォルダタブを表示する Alcove のパネル設定"></td>
  </tr>
  <tr>
    <td>
      <strong>パネル操作</strong><br><br>
      パネルの固定、並び順の変更、設定画面の表示、パネルの削除をコンパクトなメニューから行えます。
    </td>
    <td><img src="images/readme/panel-controls.png" alt="固定、並べ替え、設定、削除を表示する Alcove のパネルメニュー"></td>
  </tr>
  <tr>
    <td>
      <strong>外観のカスタマイズ</strong><br><br>
      透明度、コンテンツサイズ、角丸、パネル間隔、ウインドウの影を段階式のコントロールで調整できます。
    </td>
    <td align="center"><img src="images/readme/appearance-settings.png" width="420" alt="透明度とパネル外観を調整する Alcove の設定画面"></td>
  </tr>
  <tr>
    <td>
      <strong>言語と自動起動</strong><br><br>
      ログイン時の自動起動に対応しています。表示言語は英語、簡体字中国語、繁体字中国語から選択でき、macOS の設定に従うこともできます。
    </td>
    <td align="center"><img src="images/readme/language-settings.png" width="420" alt="自動起動と言語を設定する Alcove の一般設定"></td>
  </tr>
</table>

## 開発状況

> **MVP の実装は完了しています**

アプリ本体、自動テスト、arm64 ビルドの検証は完了しています。最初の公開リリースまでに、最終 DMG のインストールと Gatekeeper の挙動、複数ディスプレイ、Spaces、ステージマネージャ環境での動作を手動で確認する必要があります。

## 動作環境

| 項目 | 内容 |
|---|---|
| 最低 OS | macOS 26 Tahoe |
| 対応予定 | macOS 26 および macOS 27 Golden Gate |
| CPU | Apple Silicon（arm64） |
| アプリ形式 | Dock アイコンを表示しない、非サンドボックスのメニューバー LSUIElement アプリ |
| 対応フォルダ | 内蔵固定ディスク上のローカルフォルダのみ |
| 配布形式 | Apple Development 署名済み、未公証の DMG を GitHub Releases で配布 |

## インストールとリリース

### Homebrew

公開されている個人 Tap から現在のベータ版をインストールします。

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask alcove@beta
```

### 手動インストール

各 GitHub Release には `Alcove.<バージョン>.dmg` が 1 つ含まれます。DMG を開き、`Alcove.app` を `Applications` にドラッグしてください。現在のリリースは無償の Apple Development 証明書で署名されていますが、Apple の公証は受けていません。初回起動前に、Release Notes の案内に従ってダウンロード隔離属性を削除してください。

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

バージョン形式は `x.y.z`、`x.y.z-alpha.n`、`x.y.z-beta.n` に対応しています。変更内容は [CHANGELOG.md](../CHANGELOG.md) を参照してください。

## 主な設計方針

- WidgetKit ではなく、ネイティブの AppKit を使用しています。
- パネル背景は安定した静的半透明表示で、5 段階の透明度とパネルごとの色を設定できます。
- 選択、クイックルック、ドラッグ＆ドロップ、コンテキストメニューは Finder の操作感に合わせています。
- 全体の外観と言語は `UserDefaults`、パネル配置はバージョン付き JSON ファイルに保存します。
- テレメトリや解析はありません。ユーザー状態は Mac 内に保存され、ネットワーク通信は署名済みソフトウェア更新の取得にのみ使用されます。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [Current Handoff](HANDOFF.md) | 現在の要件、実装状況、既知のリスク、引き継ぎ情報 |
| [Product Requirements](PRODUCT_REQUIREMENTS.md) | 製品目標、操作仕様、受け入れ条件 |
| [Architecture](ARCHITECTURE.md) | モジュール境界、データモデル、永続化、並行処理 |
| [Research](RESEARCH.md) | API 調査、技術検証、参照プロジェクト |
| [Delivery Plan](DELIVERY_PLAN.md) | 開発段階、テスト項目、リリース条件 |

## ライセンス

Copyright © 2025–2026 SlippinDylan Studio. Alcove は [Apache License 2.0](../LICENSE) で公開されています。
