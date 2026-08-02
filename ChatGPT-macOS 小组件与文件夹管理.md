# macOS 小组件与文件夹管理

**User:** Anonymous  
**Created:** 8/2/2026 12:22:20  
**Updated:** 8/2/2026 13:11:19  
**Exported:** 8/2/2026 13:12:24  
**Link:** [https://chatgpt.com/c/6a6ec5f9-daf0-83ee-aa45-1fdbfcb99fd2](https://chatgpt.com/c/6a6ec5f9-daf0-83ee-aa45-1fdbfcb99fd2)  

## Prompt:
2026/8/2 12:22:17

你知道iCollections 这个软件吧，我用这个软件唯一的功能就是在桌面上新建一个iCollections 的文件夹入口，然后映射到我本地项目中的文件夹，然后直接进去，这个功能你知道吧

但是这个app 有点垃圾，就是我在macbook 的屏幕上设置了这个入口之后，如果连接显示器之后，在大屏上就会显示起来有问题，就是位置不对

我觉得完全可以用那种就是苹果自带的桌面的那种小组件来实现这个东西，但是我不知道现在是否有的

我想让你帮我查询两个东西
1.在 macOS26 上，苹果的小组件支持就是操作小组件的内容吗而不是点击之后直接打开 app（小组件是否支持交互）
2.macOS 上这类工具，有没有跟我说的类似的呢，无论是 GitHub 还是说其他的，有没有能实现这个东西的
3.如果要自己做的话，小组件是不是必须要买苹果的开发者证书呢？

## Response:
2026/8/2 12:22:27

> **Recherche d’options macOS**
>
> 我正在核对 macOS 26 对交互式小组件、App Intents、文件夹展示和深层链接的支持，再比较现成应用与自行开发的取舍，重点关注维护成本与实际可行性。
>
> **Recherché des options macOS**
>
> 
>
> **正在搜索网页**
>
> [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
> [ADDとは？症状や診断基準、ADHDとの違いを解説します](https://junior.litalico.jp/column/article/012/)
> [App Store - Apple（日本）](https://www.apple.com/jp/app-store/)
> [‎Widgetkitアプリ - App Store - Apple](https://apps.apple.com/jp/app/widgetkit/id1532637790)
> [【iOS】WidgetKit 入門](https://zenn.dev/naoya_maeda/articles/e5c5af8ec567c9)
> [Swift初心者向け：WidgetKitで簡単メモウィジェットを作る方法](https://qiita.com/yuuka_____gf/items/604c29a71584206f23d3)
>
> **已搜索 6 个网站**
>
> 
>
> **正在搜索网页**
>
> [Set up and run shortcuts from a widget on your Mac](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-a-widget-apd029b36d05/mac)
> [Automator | Apple Developer Forums](https://developer.apple.com/forums/tags/automator)
>
> **比较实现路径**
>
> 我正在把方案分成三类：系统小组件、现成第三方工具和自建应用。核心判断是文件夹打开很容易，但稳定的多显示器桌面定位才是主要难点。
>
> **已搜索 2 个网站**
>
> 
>
> **获取并检查苹果开发者能力页面**
>
>
> **检查了苹果开发者能力页面**
>
> 
>
> 思考了 2m 0s

我会先核对 Apple 对 macOS 26 小组件交互能力的官方定义，再查现成工具和 GitHub 项目，最后判断自研时证书、沙盒与文件夹权限的实际要求。

已经找到一个很接近你需求的原生方案：macOS 自带“快捷指令”小组件可以直接在桌面运行指定快捷指令。下一步重点确认它能否稳定打开任意本地项目文件夹，以及两个近期的开源桌面文件夹组件。

## 结论

你的需求在 macOS 26 上已经可以直接用 **苹果自带的“快捷指令小组件”**实现：桌面放一个原生小组件，点击后直接在 Finder 打开指定项目文件夹。这个方案由 macOS 管理小组件位置，最适合解决 iCollections 在内屏、外接显示器之间坐标错乱的问题。

## 1. macOS 26 小组件支持交互

macOS 小组件支持以下两种交互：

- `Button`：执行一个 App Intent 操作。
- `Toggle`：直接切换某个状态。

这些操作可以在小组件里执行，无需显示主 App 窗口。苹果官方的提醒事项小组件可以直接勾选任务，快捷指令小组件可以直接运行快捷指令。([Apple Developer](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities?utm_source=chatgpt.com))

同时，小组件有明确的能力边界：

- 适合点击按钮、切换状态、运行快捷操作。
- 整体点击或 `widgetURL` 通常用于跳转到 App 的指定页面。
- 小组件内容本质上是系统保存的 SwiftUI 视图快照，无法直接嵌入一个完整 Finder 窗口。
- 原生 WidgetKit 不适合文件拖放、框选、双击重命名、自由滚动文件列表等复杂操作。([Apple Developer](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity?utm_source=chatgpt.com))

所以，你只需要“点击桌面入口，打开某个项目文件夹”，原生小组件完全够用。

## 2. 现有方案

| 方案 | 能否打开指定文件夹 | 是否原生小组件 | 外接显示器适应性 | 推荐度 |
|---|---:|---:|---:|---:|
| macOS 快捷指令小组件 | 可以 | 是 | 系统管理位置 | **最高** |
| TileTop | 可以，还能显示文件内容 | 否，AppKit 桌面窗口 | 需要实际测试 | 较高 |
| Pocket Finder | 可以，接近迷你 Finder | 否，桌面窗口 | 固定桌面层窗口 | 一般 |
| Folder Peek | 可以 | 否，菜单栏入口 | 不受桌面坐标影响 | 较高 |
| Desktop Organizer | 可以组织文件区 | 否，自定义桌面区域 | 仍依赖窗口布局 | 较低 |

### 最适合你的：快捷指令小组件

设置方式：

1. 打开 macOS 的“快捷指令”。
2. 新建快捷指令，例如命名为“打开 Repo”。
3. 添加“运行 Shell 脚本”操作：

```bash
/usr/bin/open "/Users/dylanwang/Repo"
```

也可以使用快捷指令里的“打开文件”操作，直接选择目标文件夹。

4. 右键桌面，选择“编辑小组件”。
5. 找到“快捷指令”。
6. 添加小尺寸小组件。
7. 右键小组件，选择“编辑快捷指令”，指定刚才创建的“打开 Repo”。

苹果官方确认，小尺寸快捷指令小组件可以绑定一个指定快捷指令，点击后直接运行。([苹果支持](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-a-widget-apd029b36d05/mac?utm_source=chatgpt.com))

这个入口可以改名称、图标和颜色。你可以分别创建：

- Repo
- Products
- Apps
- Scripts
- Config

然后放进一个中尺寸快捷指令小组件中。

### TileTop：功能最接近 iCollections

TileTop 是一个近期出现的开源 macOS 项目，可以把任意文件夹固定到桌面，显示成毛玻璃文件夹组件。它支持：

- 展示文件夹内容。
- 双击打开文件或文件夹。
- 拖入、拖出文件。
- 重命名、新建文件夹、移动到废纸篓。
- 文件夹移动或改名后继续跟踪。
- 保存组件尺寸和位置。

它使用原生 AppKit，整个项目只有几百行 Swift，无 Electron，也没有 WidgetKit 的沙盒限制。([GitHub](https://github.com/NeutrinoLiu/TileTop))

它目前只有 8 次提交和 1 个 Star，属于非常新的项目；发布版本使用 ad-hoc 签名，没有经过 Apple 公证。它依然属于“桌面层窗口”，多显示器切换时的位置恢复逻辑需要重点测试。([GitHub](https://github.com/NeutrinoLiu/TileTop))

### Pocket Finder：桌面迷你文件管理器

Pocket Finder 可以在桌面显示完整文件列表，支持：

- 浏览文件夹。
- 文件搜索和排序。
- 双击打开。
- 在 Finder 中显示。
- 重命名、移动、创建文件夹。
- 拖拽文件。
- 多选操作。

它同样采用桌面层窗口，默认放在屏幕左下角，也使用 ad-hoc 签名，项目目前为 0 Star。([GitHub](https://github.com/leaton79/pocket-finder))

你的需求只有一个文件夹入口，Pocket Finder 的功能明显偏重。

### Folder Peek：稳定的菜单栏方案

Folder Peek 可以把项目文件夹固定到菜单栏，点击后直接查看文件、子文件夹，也支持拖放、快捷键和 Finder alias。它无法放到桌面，但完全绕开了多显示器桌面坐标问题。([App Store](https://apps.apple.com/us/app/folder-peek/id1615988943?mt=12))

## 3. 自己开发是否需要苹果开发者证书

| 使用方式 | 付费开发者账号 |
|---|---:|
| 使用快捷指令小组件 | 不需要 |
| 自己在本机开发和运行 | 不需要 |
| 开源后让用户自己编译 | 不需要 |
| 提供未公证的 App，用户右键打开 | 不需要 |
| 提供正常双击安装、无安全警告的 DMG | 需要 |
| 上架 Mac App Store | 需要 |

Apple 明确允许使用 Xcode 把 App 安装到自己的设备，无需加入付费 Apple Developer Program。([Apple Developer](https://developer.apple.com/help/account/membership/program-enrollment/?utm_source=chatgpt.com))

公开发布时，需要 Developer ID 证书并提交 Apple 公证；Developer ID 证书要求加入 Apple Developer Program。([Apple Developer](https://developer.apple.com/support/developer-id/?utm_source=chatgpt.com))

开发真正的 WidgetKit 小组件时，通常还会涉及：

- 主 App 和 Widget Extension 两个 Target。
- App Groups，共享配置和文件夹书签。
- Security-scoped bookmark，长期保存用户选择的文件夹权限。
- App Intent，处理小组件点击。
- 必要时由一个无窗口的后台 App 调用 `NSWorkspace` 打开 Finder。

Apple 对 App Groups 要求注册群组，并为相关 App ID 启用该能力。([Apple Developer](https://developer.apple.com/help/account/identifiers/register-an-app-group/?utm_source=chatgpt.com))

你的最佳执行顺序是：

1. 先用“快捷指令小组件”替代 iCollections，基本已经满足需求。
2. 需要直接在桌面查看和拖放项目文件时，再测试 TileTop。
3. 决定自己开发时，做成“WidgetKit 文件夹启动器”，本机自用阶段无需购买证书；准备公开提供安装包时再购买开发者账号。

---

**Sources:**

- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities?utm_source=chatgpt.com)
- [Set up and run shortcuts from a widget on your Mac](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-a-widget-apd029b36d05/mac?utm_source=chatgpt.com)
- [GitHub - NeutrinoLiu/TileTop: Pin any website or folder to your macOS desktop as a glassy widget. Native AppKit, no Electron, builds with swiftc. · GitHub](https://github.com/NeutrinoLiu/TileTop)
- [‎Folder Peek App - App Store](https://apps.apple.com/us/app/folder-peek/id1615988943?mt=12)

## Prompt:
2026/8/2 12:38:48

我记得在 windows 上有这样的一个工具，f 开头的我忘了叫啥了，steam 上架了

## Response:
2026/8/2 12:38:51

> **正在搜索 Steam app Windows desktop icons organizer starts with F**
>
> [Save 15% on Fences 6 on Steam](https://store.steampowered.com/app/3165690/Fences_6/)
> [Desktop Computers & All-in-One PCs](https://www.bestbuy.com/site/computers-pcs/desktop-computers/abcat0501000.c?id=abcat0501000)
> [Blank "Steam Desktop Icons" - Issue and Potential Resolution](https://steamcommunity.com/discussions/forum/1/597412189643706588/?l=dutch)
> [Stardock Fences 6: Automatically organize your desktop ...](https://www.stardock.com/products/fences/)
> [All steam shortcut games missing icons in windows 11](https://www.reddit.com/r/Steam/comments/11y7ngl/all_steam_shortcut_games_missing_icons_in_windows/)
> [Desktop icon organization tips needed](https://www.facebook.com/groups/cozygamer/posts/1287626419154003/)
> [Hands-on: Fences 6 makes your desktop even more efficient](https://www.xda-developers.com/hands-on-fences-6-levels-up-your-desktop-even-more/)
> [How to Organize Your Desktop Using Stardock Fences](https://www.youtube.com/watch?v=_kwrXBRzKcw)
> [OFFICIAL | 意味, Cambridge 英語辞書での定義](https://dictionary.cambridge.org/ja/dictionary/english/official)
> [STEAM: A Training-Free Congestion-Aware Enhancement Framework for Decentralized Multi-Agent Path Finding](https://arxiv.org/abs/2605.20929)
>
> **已搜索 10 个网站**
>
> 
>
> 思考了 15s

你记得的是 **Stardock Fences**。

它里面的 **Folder Portals** 功能，和你在 iCollections 里使用的功能几乎一致：

- 把任意本地文件夹映射到 Windows 桌面。
- 桌面区域直接显示该文件夹内的文件和子目录。
- 双击文件夹继续进入下一级。
- 文件变化会同步显示。
- 无需把真实文件复制到桌面。([Stardock](https://www.stardock.com/products/fences/?utm_source=chatgpt.com))

目前 Steam 上架的是 **Fences 6**，2025 年 10 月登陆 Steam。新版还加入了标签页，可以在同一块桌面区域中切换多个文件夹。([Steam商店](https://store.steampowered.com/app/3165690/Fences_6/?utm_source=chatgpt.com))

所以你的实际目标可以描述为：

> 在 macOS 上实现一个类似 Fences Folder Portals 的桌面文件夹入口，映射任意本地目录，并由系统正确处理多显示器位置。

这个参照比“做一个小组件打开文件夹”更准确。小组件方案只能提供快捷入口；完整复刻 Fences Folder Portals，需要显示目录内容、进入子目录和操作文件，应该采用桌面层原生窗口方案，而非 WidgetKit。

---

**Sources:**

- [Stardock Fences 6: Automatically organize your desktop ...](https://www.stardock.com/products/fences/?utm_source=chatgpt.com)
- [Save 15% on Fences 6 on Steam](https://store.steampowered.com/app/3165690/Fences_6/?utm_source=chatgpt.com)

## Prompt:
2026/8/2 12:52:42

我给你说一下我的想法，原先在用iCollections的时候，我是做的文件夹映射，比如新建一个iCollections的文件夹视图之后，然后比如说映射到“/Users/dylanwang/Repo”这个路径，那么这个视图就会展示这个文件夹的所有子文件夹
然后如果是还想要查看其他文件夹的映射的话，那么就得再新建一个文件夹视图才行

我想要的是顶部有个 tab，然后可以在一个视图里面通过多个 tab 的方式承载多个文件夹视图，点击即可切换不同的文件夹，然后 tab 的名称就是当前映射的文件夹的名称，然后下方展示的内容就是映射路径下面的所有文件夹和文件，可以滚动，文件夹或者文件的图标大小跟桌面上当前显示的大小一样，视图还可以根据当前屏幕的分辨率自动调整，用户可以选择视图进行移动位置显示，想显示在哪就显示在哪，然后切换显示器之后，这个还是要存在的，但是位置可能要根据显示器而切换一下了，点击某个文件夹之后，直接在访达中打开显示，点击某个文件之后，直接根据当前 mac 设置的默认的打开方式打开，空格键就是正常的预览

我觉得通过 mac 的原生小组件是实现不了这个东西的，iCollections现在在多个显示器的时候 bug 太多了，我觉得用不了了，然后我想知道我想做的这个东西，有办法实现把，我想最低支持 macOS15，你帮我查一下呢

我觉得肯定得有一个后台运行的的东西，显示图标到菜单栏，这玩意无非就是新建和设置，然后新建的时候就在桌面新建一个虚线的框即可，用户鼠标移动到哪就在哪里建，但是不能超过屏幕的区域，然后点击之后，就新建完成了，然后要选择文件夹路径，然后可以新增文件夹路径，要有辅助功能应该得授权和全局磁盘访问，可能还要其他的权限，然后可以调整大小，但是这个大小就是固定的，一行显示 3 个 4 个这样，然后可以设置新增一个文件夹路径，就变成以 tab 的形式展示了，然后可以整个视图移除，圆角跟随 mac 原生的圆角大小，背景我想的是玻璃磨砂的这种，也是根据 mac 的原生的，看是什么样就自动是什么样即可，以上是我大概的想法，你帮我分析一下呢，重点正儿八经去网上查一下资料了来，不要自己随便想，一定要去查官方的资料和别人的案例

## Response:
2026/8/2 12:52:53

> **正在梳理方案**
>
> 我会先核对 macOS 15 的窗口、文件监控、预览与权限能力，再比较成熟应用和开源项目，最后整理成可落地的架构、MVP 以及后续迭代路线。
>
> **梳理方案**
>
> 
>
> **正在搜索网页**
>
> [moveToActiveSpace | Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace?changes=_5%2C_5)
> [NSWindowクラス - macOS/iOS API解説 - はてなブログ](https://cocoaapi.hatenablog.com/entry/Appkit/NSWindow_class)
> [Choosing a Window Level in Red Stripe and Sim Daltonism](https://michelf.ca/blog/2016/choosing-window-level/)
> [NSWindowをSwiftUIのインターフェースで呼び出す](https://zenn.dev/kyome/articles/2bb254567daef7)
> [lukakerr/NSWindowStyles: A showcase of the many ...](https://github.com/lukakerr/NSWindowStyles)
>
> **正在搜索网页**
>
>
> **已搜索 5 个网站**
>
> 
>
> **正在搜索 GitHub macOS desktop folder widget NSWindow desktop level folder view tabs**
>
> [Github Desktop not reading folder contents Mac OS #15370](https://github.com/desktop/desktop/issues/15370)
> [Looking for widget to pin folders to desktop : r/MacOS](https://www.reddit.com/r/MacOS/comments/179h6b2/looking_for_widget_to_pin_folders_to_desktop/)
> [7. GitHub Desktop for Macintosh](https://www.youtube.com/watch?v=OfrKx4c8YoY)
> [12/24 Mac超初心者のミス Move Github Desktop to the ...](https://qiita.com/wa-chan222/items/223ca7ea514688a26eed)
> [Folders File Manager - App Store - Apple](https://apps.apple.com/us/app/folders-file-manager/id1593644229?mt=12)
> [git/GitHub Desktop not recognizing files in subfolders](https://stackoverflow.com/questions/68088256/git-github-desktop-not-recognizing-files-in-subfolders)
> [Folders File Manager | Folders Pro](https://foldersapp.dev/)
> [File Widgets for macOS](https://www.i-novation.de/file-widgets/)
> [Switching to open folders on a Mac](https://superuser.com/questions/129692/switching-to-open-folders-on-a-mac)
> [Mac Widgets: Custom Desktop Widgets Built With AI | Kepo Blog](https://kepo.ai/blog/mac-widgets)
> [Managing multiple desktops - AppleScript | Mac OS X](https://www.macscripter.net/t/managing-multiple-desktops/22192)
> [🛠️ Configure GitHub Desktop's External Editor for Multiple ...](https://medium.com/%40brysenpoi6615/%EF%B8%8F-configure-github-desktops-external-editor-for-multiple-ides-on-macos-492c31d2701a)
> [Unauthorized Cross-App Resource Access on MAC OS X and iOS](https://arxiv.org/abs/1505.06836)
> [What is the macOS Finder on your new MacBook Neo? Here's your complete beginner's guide on the Mac's file organizer](https://www.techradar.com/computing/mac-os/what-is-the-macos-finder-on-your-new-macbook-neo-heres-your-complete-beginners-guide-on-the-macs-file-organizer)
> [The 30 Best Mac Apps That Will Make Your Life Easier](https://www.wired.com/story/best-mac-apps)
>
> **设计多屏布局**
>
> 我会按显示器 UUID 保存窗口位置与尺寸，并以可见区域的归一化坐标恢复；显示器断开时临时迁移并限制在主屏，重连后再恢复原布局。
>
> **正在搜索网页**
>
>
> **已搜索 15 个网站**
>
> 
>
> 思考了 2m 41s

我会把这个方案拆成四块核实：桌面层窗口、多显示器与空间管理、文件系统交互与权限、现有开源案例。重点确认哪些能力 macOS 15 的公开 API 已经支持，哪些地方最容易踩坑。

从官方 API 看，你的核心能力都能在 macOS 15 上实现。权限上有一个关键修正：用户主动选择文件夹并保存安全书签即可，辅助功能和“完全磁盘访问”通常都不需要，这会显著降低安装门槛。

## 结论

这个产品完全可以实现，最低支持 **macOS 15** 没有技术障碍。最合适的形态是：

> **常驻菜单栏 App + AppKit 桌面层窗口 + 多文件夹 Tab + 原生文件图标网格**

WidgetKit 适合按钮、开关和 App Intent 等聚焦交互，系统负责归档和渲染小组件；它无法承载持续运行的可滚动文件浏览器，也不适合 Finder 式选择、空格预览、拖放和自由调整窗口尺寸。([Apple Developer](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities?utm_source=chatgpt.com))

## 已经有一个很接近的现成 App

**Desktop Organizer - File Zones** 最近几个版本已经加入：

- 3.3：多 Tab 文件区域。
- 3.1：空格键文件预览、图标拖动排序。
- 3.0：优化多显示器显示逻辑。
- 2.10：修复多显示器位置错乱。

它现在已经相当接近你描述的“macOS 版 Fences Folder Portal”。App Store 评价里也有人称它是目前最接近 Windows Fences 的 Mac 软件，同时也有用户反馈重命名、拖放和 iCloud 文件方面仍存在问题。([App Store](https://apps.apple.com/us/app/desktop-organizer-file-zones/id6504022609?mt=12))

另一个重要参考是开源项目 **TileTop**。它使用 AppKit 创建桌面文件夹窗口，支持菜单栏管理、文件图标网格、滚动、打开文件、拖放、重命名、回收站、文件夹移动追踪和多显示器位置保存，最低支持 macOS 13，采用 Apache 2.0 许可证。它目前缺少多 Tab 和空格预览，但非常适合作为你的项目底座。([GitHub](https://github.com/NeutrinoLiu/TileTop))

## 推荐技术方案

| 需求 | 实现方式 |
|---|---|
| 桌面显示区域 | 无标题、透明、可调整尺寸的 `NSWindow` |
| 位于桌面层 | `CGWindowLevelForKey(.desktopIconWindow) + 1` |
| 常驻所有桌面空间 | `.canJoinAllSpaces`、`.stationary`、`.ignoresCycle` |
| 菜单栏管理 | `NSStatusItem` 或 SwiftUI `MenuBarExtra` |
| 多文件夹 Tab | 每个窗口维护多个 `FolderTab` |
| 文件图标网格 | `NSCollectionView` + `NSScrollView` |
| 系统文件图标 | `NSWorkspace.shared.icon(forFile:)` |
| 默认程序打开文件 | `NSWorkspace.shared.open(url)` |
| Finder 打开文件夹 | `NSWorkspace.shared.open(folderURL)` |
| 空格预览 | `QLPreviewPanel` |
| 文件变化同步 | `DispatchSourceFileSystemObject` 或 FSEvents |
| 文件夹长期权限 | `NSOpenPanel` + security-scoped bookmark |
| 磨砂背景 | macOS 15 使用 `NSVisualEffectView`，macOS 26 使用 `NSGlassEffectView` |

Core Graphics 公开提供桌面图标窗口层级；TileTop 实际采用了 `desktopIconWindow + 1`，并配置窗口加入所有 Spaces。([Apple Developer](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey/desktopiconwindow?utm_source=chatgpt.com))

文件图标、默认应用打开和 Finder 式打开都由 `NSWorkspace` 提供；空格预览可以直接接入系统 `QLPreviewPanel`。([Apple Developer](https://developer.apple.com/documentation/AppKit/NSWorkspace?utm_source=chatgpt.com))

### 窗口数据结构

建议保存成类似下面的模型：

```swift
struct Portal {
    let id: UUID
    var displayUUID: String
    var frameByDisplay: [String: CGRect]
    var selectedTabID: UUID
    var tabs: [FolderTab]
    var iconSize: CGFloat
    var columnCount: Int
}

struct FolderTab {
    let id: UUID
    var bookmarkData: Data
    var displayName: String
    var sortMode: SortMode
    var showHiddenFiles: Bool
}
```

Tab 名称默认取解析后文件夹 URL 的 `lastPathComponent`。文件夹更名后重新解析路径并更新 Tab 名称。

## 多显示器处理是这个项目的核心

iCollections 这类问题通常发生在窗口只保存一组绝对坐标，没有把坐标和具体显示器绑定。你的项目应该同时保存：

1. 显示器 UUID。
2. 该显示器上的窗口位置。
3. 相对于 `visibleFrame` 的归一化坐标。
4. 窗口宽高和图标列数。

`NSScreen.visibleFrame` 会排除菜单栏、Dock 和刘海不可用区域；显示器可以通过 `CGDisplayCreateUUIDFromDisplayID` 建立稳定标识。([Apple Developer](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe?utm_source=chatgpt.com))

推荐规则：

- 用户在某台显示器移动窗口时，记录该显示器 UUID 和对应 frame。
- 显示器断开时，把窗口临时放到主屏可见区域，同时保留原显示器位置。
- 原显示器重新连接时，恢复原位置。
- 分辨率或缩放比例变化时，按归一化坐标重新计算，再限制在 `visibleFrame` 内。
- 窗口过大时缩小到屏幕可容纳范围。
- 用户选择“一行 3 个”或“一行 4 个”时，调整尺寸采用网格吸附。

TileTop 已经实现了“每个显示器分别保存 frame、显示器返回后恢复原位置、断开显示器时不覆盖原始位置”的逻辑，可以直接参考。([GitHub](https://github.com/NeutrinoLiu/TileTop/blob/main/Sources/WidgetCore.swift))

建议提供两个位置模式：

- **绑定显示器**：默认模式，窗口跟随指定显示器。
- **跟随主屏幕**：主屏切换后，窗口移动到新主屏相同相对位置。

绑定显示器更符合你的使用场景。

## 新建虚线框的交互

这套交互无需辅助功能权限：

1. 菜单栏点击“新建文件夹视图”。
2. 在鼠标所在显示器上创建一个全屏透明覆盖窗口。
3. 鼠标按下并拖动，显示虚线矩形。
4. 实时把矩形限制在该屏幕 `visibleFrame` 内。
5. 松开鼠标后完成创建。
6. 打开 `NSOpenPanel`，选择第一个映射文件夹。
7. 后续通过 Tab 右侧的 `+` 添加其他文件夹。

建议同时提供“直接创建 3 列”“直接创建 4 列”，比完全自由绘制更容易形成整齐布局。

## 文件交互建议

建议采用 Finder 的基本交互：

- 单击：选中文件或文件夹。
- 双击文件夹：在 Finder 中打开。
- 双击文件：使用系统默认程序打开。
- 空格：Quick Look。
- Return：重命名。
- Command + Delete：移到废纸篓。
- 右键：打开、在 Finder 中显示、复制路径、重命名、移除。
- Command 多选、Shift 连续选择。

单击直接打开会影响多选、空格预览和键盘操作，因此双击打开更稳定，可以额外提供“单击打开”设置。

`NSCollectionView` 更适合这套交互。TileTop 已经使用它实现文件选择、图标网格、滚动、拖放和重命名。([GitHub](https://github.com/NeutrinoLiu/TileTop/blob/main/Sources/FolderWidget.swift))

## 图标大小跟随桌面

文件图标本身可以通过 `NSWorkspace.icon(forFile:)` 获取，包括 App、自定义文件夹图标和不同文件类型图标。Apple 没有提供公开 API 读取 Finder 当前桌面的图标尺寸设置。([Apple Developer](https://developer.apple.com/documentation/AppKit/NSWorkspace?utm_source=chatgpt.com))

建议应用提供：

- 小：48 pt
- 中：64 pt
- 大：80 pt
- 自定义滑块

默认使用 64 pt，视觉上接近常见桌面图标。直接读取 Finder 的内部偏好属于非公开实现，系统升级后容易失效。

## 磨砂和 macOS 26 外观

最低 macOS 15 时使用：

```swift
NSVisualEffectView
```

配置系统 material、动态系统颜色和连续圆角，窗口会自动适配深色模式、浅色模式和壁纸背景。`behindWindow` 模式会对窗口后方的桌面内容产生模糊效果。([Apple Developer](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow?utm_source=chatgpt.com))

macOS 26 再通过可用性判断切换到：

```swift
if #available(macOS 26.0, *) {
    // NSGlassEffectView
} else {
    // NSVisualEffectView
}
```

`NSGlassEffectView` 是 macOS 26 的原生 Liquid Glass API，适合 Tab、按钮和窗口容器。([Apple Developer](https://developer.apple.com/documentation/AppKit/NSGlassEffectView?utm_source=chatgpt.com))

## 权限结论

### 辅助功能权限

**不需要。**

鼠标拖动、窗口移动、键盘选择、空格预览都发生在应用自己的窗口中，没有操控 Finder 或其他应用界面。

### 完全磁盘访问

**不需要。**

用户通过 `NSOpenPanel` 主动选择 `/Users/dylanwang/Repo` 后，沙盒 App 可以获得该文件夹及其子目录的访问权限。把 URL 保存为 security-scoped bookmark 后，应用重启仍可恢复访问。([Apple Developer](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?utm_source=chatgpt.com))

权限建议：

- 只浏览和打开文件：`User Selected File: Read Only`
- 支持重命名、拖入、删除、新建文件夹：`User Selected File: Read/Write`

你的第一版使用 Read Only 就能完成核心需求，权限最干净。

### 后台 Helper

**不需要。**

它是一个正常运行的菜单栏 App，窗口和文件监听都在主进程中完成。SwiftUI 的 `MenuBarExtra` 和 AppKit 的 `NSStatusItem` 都适合这种持续运行的工具。([Apple Developer](https://developer.apple.com/documentation/swiftui/menubarextra?utm_source=chatgpt.com))

## 开发者证书

- 本机开发、自用、自己编译：免费 Apple 开发者账户即可。
- GitHub 开源，让用户自己编译：无需付费证书。
- 发布可直接双击安装的 DMG：需要 Developer ID 签名和 Apple 公证。
- Mac App Store 上架：需要付费开发者账户，并启用 App Sandbox。([Apple Developer](https://developer.apple.com/get-started/?utm_source=chatgpt.com))

## 推荐实施顺序

1. **先试 Desktop Organizer - File Zones 当前版本**，验证它的多 Tab 和多显示器逻辑是否已经满足你的需求。
2. 自研时以 **TileTop** 为基础，保留它的桌面窗口层级、菜单栏、文件网格和显示器位置恢复。
3. 第一版只做多 Tab、打开文件、Quick Look、滚动、窗口移动缩放和多显示器恢复。
4. 第二版增加拖放、重命名、新建文件夹和废纸篓。
5. 全程使用 AppKit 负责窗口与文件网格，SwiftUI 负责设置页和简单表单。

这个项目的系统实现难度属于中等，真正需要反复测试的是 **外接显示器断开重连、分辨率变化、独立 Spaces、Stage Manager 和全屏应用切换**。推荐采用 **AppKit + TileTop 架构 + security-scoped bookmark + 每显示器独立位置记录**。

---

**Sources:**

- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities?utm_source=chatgpt.com)
- [‎Desktop Organizer - File Zones App - App Store](https://apps.apple.com/us/app/desktop-organizer-file-zones/id6504022609?mt=12)
- [GitHub - NeutrinoLiu/TileTop: Pin any website or folder to your macOS desktop as a glassy widget. Native AppKit, no Electron, builds with swiftc. · GitHub](https://github.com/NeutrinoLiu/TileTop)

## Prompt:
2026/8/2 13:09:08

你觉得我这个应该叫个什么名字好呢？

## Response:
2026/8/2 13:09:17

> **筛选应用名称**
>
> 我会优先考虑简短、易记、能同时表达“文件夹门户”和“标签页”的名字。我的首选是 **FolderDeck**；备选包括 **DeskPortal**、**FilePort**、**TabShelf** 和 **PortalStack**。
>
> **筛选应用名称**
>
> 
>
> 思考了 8s

我最推荐 **FolderDeck**。

它很贴合你的产品结构：一个桌面视图像一副卡片，通过顶部 Tab 切换多个文件夹；名字简短，听起来也像原生 macOS 工具。

其他备选：

| 名称 | 感觉 |
|---|---|
| **FolderDeck** | 最完整，适合正式产品名 |
| **DeskPortal** | 强调桌面文件夹入口 |
| **FileDeck** | 更宽泛，文件和文件夹都覆盖 |
| **TabShelf** | 强调 Tab 和桌面置物架 |
| **FolderShelf** | 直观，偏工具感 |
| **DeskTabs** | 最容易理解，品牌感稍弱 |
| **PortalPane** | 强调窗口式文件入口 |
| **FilePortal** | 功能表达直接 |
| **DeskDeck** | 简短，有桌面卡片集合的感觉 |
| **FolderPane** | 原生 macOS 工具风格明显 |

对应仓库名建议：

```text
folder-deck
```

菜单栏显示 `FolderDeck`，窗口可以叫 `Folder Portal`，单个桌面视图的数据模型叫 `Portal`。

最终推荐：**FolderDeck**。

## Prompt:
2026/8/2 13:09:58

真垃圾啊起的名字，非得两个单词组合在一起是吧

## Response:
2026/8/2 13:10:10

对，刚才那批就是功能词硬拼，确实没品牌感。你这个更适合一个独立单词。

我重新筛一批：

| 名称 | 含义和感觉 |
|---|---|
| **Alcove** | 壁龛、嵌入式小空间，最贴合“桌面上的文件区域” |
| **Nook** | 小角落，简短、自然，很像 macOS 工具名 |
| **Folio** | 文件册、作品集，适合多文件夹 Tab |
| **Locus** | 位置、场所，强调每个视图绑定桌面位置 |
| **Cove** | 隐蔽的小空间，柔和、有原生 Mac 气质 |
| **Pane** | 窗格，直指你的桌面文件视图 |
| **Hatch** | 舱口、入口，点击进入不同文件夹 |
| **Cubby** | 小储物格，功能很贴切，风格偏可爱 |
| **Grove** | 一片聚集区域，适合多个项目文件夹 |
| **Mosaic** | 网格化排列，强调图标视图 |
| **Nest** | 容纳多个目录的桌面容器 |
| **Portal** | 含义最直接，但品牌辨识度稍弱 |

我最推荐三个：

1. **Alcove**：最有产品感，也最贴合功能。
2. **Nook**：最好记，图标和品牌都容易做。
3. **Folio**：更像一款成熟的 macOS 文件工具。

最终推荐 **Alcove**，仓库名直接用：

```text
alcove
```

中文可以叫“桌面壁龛”或直接保留英文名。

## Prompt:
2026/8/2 13:11:02

仓库简介，中英文都要

## Response:
2026/8/2 13:11:07

可以直接用这版：

**standard: **

**中文：**  
Alcove 是一款 macOS 桌面文件夹视图工具，支持在同一个悬浮区域中通过多个标签页访问不同目录，并提供原生文件图标、Quick Look、多显示器位置适配和 Finder 打开能力。

**English:**  
Alcove is a macOS desktop folder viewer that lets you access multiple directories through tabs in a single desktop panel, with native file icons, Quick Look, multi-display positioning, and Finder integration.

GitHub 仓库的短描述建议用英文这一句：

**standard: **

A native macOS desktop folder viewer with tabbed directories, Quick Look, and multi-display support.



---
Powered by [ChatGPT Exporter](https://www.chatgptexporter.com)