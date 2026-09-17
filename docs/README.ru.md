<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Значок приложения Alcove">
  <h1>Alcove</h1>
</div>

<div align="center">
  <p>Держите часто используемые локальные папки на рабочем столе Mac в перемещаемых панелях с изменяемым размером.</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <strong>Русский</strong>
  </p>
</div>

Alcove — нативное приложение macOS для строки меню, которое показывает выбранные локальные папки на рабочем столе. Панели располагаются под обычными окнами приложений, но над значками рабочего стола. Это не замена Finder, а удобный вход в папки, к которым вы возвращаетесь в течение дня.

## Возможности

<table>
  <tr>
    <td width="32%"><strong>Панели папок на рабочем столе</strong><br><br>Нарисуйте панель на рабочем столе, выберите папку, затем перемещайте, меняйте размер, закрепляйте или удаляйте её. В одной панели может быть до четырёх вкладок с папками.</td>
    <td width="68%"><img src="images/readme/portal-overview.png" alt="Панель папки Alcove с двумя вкладками и сеткой значков"></td>
  </tr>
  <tr>
    <td><strong>Работа с файлами в панели</strong><br><br>Просматривайте папки, используйте выделение в стиле Finder, Quick Look и перетаскивание. Контекстное меню позволяет открыть, переименовать, дублировать, сжать, переместить в Корзину, показать в Finder, отправить через AirDrop и скопировать путь.</td>
    <td><img src="images/readme/file-actions.png" alt="Контекстное меню файлов Alcove"></td>
  </tr>
  <tr>
    <td><strong>Создание в нужном месте</strong><br><br>Перетащите указатель по рабочему столу, чтобы задать размер новой панели, посмотрите предварительный вид сетки и подключите папку.</td>
    <td><img src="images/readme/portal-creation.png" alt="Создание панели Alcove с предварительным просмотром сетки"></td>
  </tr>
  <tr>
    <td><strong>Вкладки папок</strong><br><br>Добавляйте в панель до четырёх папок, переключайте их, меняйте порядок или удаляйте. Каждая вкладка хранит своё место просмотра и выделение.</td>
    <td align="center"><img src="images/readme/folder-tabs.png" width="420" alt="Настройки панели Alcove с вкладками папок"></td>
  </tr>
  <tr>
    <td><strong>Управление панелью</strong><br><br>Закрепляйте панель, меняйте порядок сортировки, открывайте настройки или удаляйте панель с рабочего стола.</td>
    <td><img src="images/readme/panel-controls.png" alt="Меню управления панелью Alcove"></td>
  </tr>
  <tr>
    <td><strong>Внешний вид</strong><br><br>Настраивайте размер содержимого, прозрачность, радиус скругления, расстояние между панелями и тень окна.</td>
    <td align="center"><img src="images/readme/appearance-settings.png" width="420" alt="Настройки внешнего вида Alcove"></td>
  </tr>
  <tr>
    <td><strong>Запуск и язык</strong><br><br>Alcove можно запускать при входе в систему. Интерфейс может следовать языку macOS или использовать английский, упрощённый китайский либо традиционный китайский.</td>
    <td align="center"><img src="images/readme/language-settings.png" width="420" alt="Общие настройки Alcove для запуска при входе и языка"></td>
  </tr>
</table>

## Загрузка и установка

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask alcove@beta
```

### DMG

Текущие публичные сборки имеют статус бета-версии. Скачайте последний DMG из [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases), откройте его и перетащите `Alcove.app` в `Applications`.

Эта бета-версия подписана сертификатом Apple Development, но не нотариально заверена. macOS помечает загруженные приложения атрибутом карантина, поэтому Gatekeeper может заблокировать первый запуск. Если вы доверяете источнику загрузки, сначала щёлкните приложение с удерживаемой клавишей Control и выберите «Открыть». Если карантин всё ещё мешает запуску, выполните:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Alcove.app
```

Доступные версии перечислены в [GitHub Releases](https://github.com/SlippinDylan/Alcove/releases). Список изменений находится в [CHANGELOG.md](../CHANGELOG.md).

## Требования и ограничения

| Пункт | Значение |
|---|---|
| macOS | macOS 26 или новее |
| Mac | Apple Silicon (`arm64`) |
| Тип приложения | Приложение для строки меню без значка в Dock |
| Папки | Только локальные папки на внутреннем несъёмном диске |
| Дисплей | Панели остаются на основном дисплее |

Внешние, съёмные, извлекаемые и сетевые тома не поддерживаются. Для защищённых мест, например «Рабочий стол», «Документы» и «Загрузки», macOS может запросить у Alcove разрешение на доступ.

## Сборка из исходного кода

Установите Xcode с SDK macOS 26, затем клонируйте репозиторий и соберите общую схему:

```bash
git clone https://github.com/SlippinDylan/Alcove.git
cd Alcove
xcodebuild -project Alcove.xcodeproj -scheme Alcove -configuration Debug build
```

## Документация

| Документ | Описание |
|---|---|
| [Требования к продукту](PRODUCT_REQUIREMENTS.md) | Границы продукта и правила взаимодействия |
| [Архитектура](ARCHITECTURE.md) | Компоненты, хранение данных и модель размещения |
| [Исследование](RESEARCH.md) | Исследование платформы и источники |
| [Журнал изменений](../CHANGELOG.md) | История выпусков |

## Лицензия

Copyright © 2025–2026 SlippinDylan Studio. Alcove распространяется по лицензии [Apache License 2.0](../LICENSE).
