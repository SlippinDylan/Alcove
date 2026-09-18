<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Alcove のアプリアイコン">
  <h1>Alcove</h1>
</div>

<div align="center">
  <p>よく使うローカルフォルダを、移動・サイズ変更できるパネルとして Mac のデスクトップに置くアプリです。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <strong>日本語</strong> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

Alcove は、選んだローカルフォルダをデスクトップに表示する macOS ネイティブのメニューバーアプリです。パネルは通常のアプリウインドウより下、デスクトップアイコンより上に表示されます。Finder の代わりではなく、何度も戻るフォルダへの入口として使うアプリです。

## 機能

<table>
  <tr>
    <td width="32%"><strong>デスクトップのフォルダパネル</strong><br><br>デスクトップをドラッグしてパネルを作成します。フォルダを選んだ後は、移動、サイズ変更、固定、削除ができます。1 つのパネルには最大 4 個のフォルダタブを追加できます。</td>
    <td width="68%"><img src="images/readme/portal-overview.png" alt="2 つのタブとアイコングリッドを表示する Alcove のフォルダパネル"></td>
  </tr>
  <tr>
    <td><strong>パネル内でのファイル操作</strong><br><br>フォルダを閲覧し、Finder に近い選択、クイックルック、ドラッグ＆ドロップを使えます。コンテキストメニューでは、開く、名前変更、複製、圧縮、ゴミ箱へ移動、Finder で表示、AirDrop で送信、パスのコピーができます。</td>
    <td><img src="images/readme/file-actions.png" alt="Alcove のファイル用コンテキストメニュー"></td>
  </tr>
  <tr>
    <td><strong>必要な場所に作成</strong><br><br>デスクトップをドラッグして新しいパネルの大きさを決めます。グリッドをプレビューしてからフォルダに接続できます。</td>
    <td><img src="images/readme/portal-creation.png" alt="グリッドプレビュー付きの Alcove パネル作成画面"></td>
  </tr>
  <tr>
    <td><strong>フォルダタブ</strong><br><br>1 つのパネルに最大 4 個のフォルダを追加し、切り替え、並べ替え、削除できます。各タブは閲覧位置と選択状態を保持します。</td>
    <td align="center"><img src="images/readme/folder-tabs.png" width="420" alt="フォルダタブを表示する Alcove のパネル設定"></td>
  </tr>
  <tr>
    <td><strong>パネル操作</strong><br><br>パネルの固定、並び順の変更、設定画面の表示、デスクトップからの削除を行えます。</td>
    <td><img src="images/readme/panel-controls.png" alt="Alcove のパネル操作メニュー"></td>
  </tr>
  <tr>
    <td><strong>外観</strong><br><br>コンテンツサイズ、透明度、角丸、パネル間隔、ウインドウの影を調整できます。</td>
    <td align="center"><img src="images/readme/appearance-settings.png" width="420" alt="Alcove の外観設定"></td>
  </tr>
  <tr>
    <td><strong>起動と言語</strong><br><br>ログイン時に Alcove を起動できます。表示言語は macOS に従うほか、英語、簡体字中国語、繁体字中国語を選べます。</td>
    <td align="center"><img src="images/readme/language-settings.png" width="420" alt="自動起動と言語を設定する Alcove の一般設定"></td>
  </tr>
</table>

## ダウンロードとインストール

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask alcove@beta
```

### DMG

現在公開されているビルドはベータ版です。[GitHub Releases](https://github.com/SlippinDylan/Alcove/releases) から最新の DMG をダウンロードし、開いてから `Alcove.app` を `Applications` にドラッグしてください。

このベータ版は Apple Development 証明書で署名されていますが、公証されていません。macOS はダウンロードしたアプリに隔離属性を付けるため、Gatekeeper が初回起動を妨げることがあります。ダウンロード元を信頼できる場合は、まず Control キーを押しながらアプリをクリックし、「開く」を選んでください。それでも隔離属性によって起動できない場合は、次を実行します。

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

公開済みのリリースは [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases) に掲載しています。変更内容は [CHANGELOG.md](../CHANGELOG.md) を参照してください。

## 動作環境と制限

| 項目 | 内容 |
|---|---|
| macOS | macOS 26 以降 |
| Mac | Apple Silicon（`arm64`） |
| アプリ形式 | Dock アイコンを表示しないメニューバーアプリ |
| フォルダ | 内蔵の取り外し不可ディスク上にあるローカルフォルダのみ |
| ディスプレイ | パネルはプライマリディスプレイに表示されます |

外付け、リムーバブル、取り外し可能なボリューム、ネットワークボリュームは利用できません。デスクトップ、書類、ダウンロードなどの保護された場所では、macOS が Alcove へのアクセス許可を求めることがあります。

## ソースからビルド

macOS 26 SDK を含む Xcode をインストールしてから、リポジトリを複製し、共有スキームをビルドします。

```bash
git clone https://github.com/SlippinDylan/Alcove.git
cd Alcove
xcodebuild -project Alcove.xcodeproj -scheme Alcove -configuration Debug build
```

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [要件](PRODUCT_REQUIREMENTS.md) | 製品範囲と操作の取り決め |
| [アーキテクチャ](ARCHITECTURE.md) | コンポーネント、永続化、レイアウトモデル |
| [開発ガイド](development.md) | ビルド、テスト、CI、リリース、クリーンアップ手順 |
| [調査](RESEARCH.md) | プラットフォーム調査と参照元 |
| [変更履歴](../CHANGELOG.md) | リリース履歴 |

## ライセンス

Copyright © 2025–2026 SlippinDylan Studio. Alcove は [Apache License 2.0](../LICENSE) で公開されています。
