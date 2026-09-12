# Alcove 当前状态与开发交接

> 快照日期：2026-09-12（Asia/Tokyo）
>
> 适用基线：功能提交 `e73385b`；本交接文档的提交位于其后
>
> 用途：让新的开发对话在不依赖历史聊天记录的情况下接管项目

## 1. 新对话如何开始

新的开发对话应按以下顺序建立上下文：

1. 读取仓库根目录的 `README.md`。
2. 搜索并遵守当前环境、仓库和任务目录中的全部 `AGENTS.md`；不要假设本快照之后没有新增规则。
3. 读取本文，再按任务范围进入 `PRODUCT_REQUIREMENTS.md`、`ARCHITECTURE.md`、`DELIVERY_PLAN.md` 或对应 Spike 文档。
4. 执行 `git status --short`、`git log -10 --oneline` 和 `git rev-list --left-right --count origin/main...HEAD`，重新确认本文记录的 Git 状态是否仍然成立。
5. 保留所有已有未提交改动。尤其不要暂存、格式化、回退或覆盖 `Alcove.xcodeproj/project.pbxproj`。

本文是当前状态索引，不取代业务和架构文档。冲突时采用以下优先级：当前用户指令和 `AGENTS.md` → 当前代码与测试 → `PRODUCT_REQUIREMENTS.md` / `ARCHITECTURE.md` → 本文的历史说明 → 较早的 Delivery/Spike 计划。

## 2. 一句话说明项目

Alcove 是一个原生 macOS 菜单栏工具。它在桌面图标之上、普通应用窗口之下展示可移动、可缩放的文件夹 Portal；每个 Portal 可以包含多个文件夹 Tab，并提供 Finder 风格的图标网格、选择、打开、Quick Look、自动刷新和多显示器恢复。

它不是 Finder 替代品。MVP 是只读视图，不提供重命名、删除文件、新建文件夹、复制、移动或拖入写操作。

## 3. 已确认的产品范围

### 3.1 平台与发布

- 原生 AppKit 应用，最低 macOS 15，主要视觉目标 macOS 26。
- `LSUIElement` 菜单栏应用，不显示 Dock 图标。
- 通用架构：`arm64 + x86_64`。
- macOS 26 使用适用的 Liquid Glass；macOS 15–25 使用原生 `NSVisualEffectView` 回退。
- 正式签名、证书和最终 DMG 发布不是当前 UI 功能工作的阻塞项；用户已明确要求暂时不要处理正式签名。
- GitHub CI 和无签名通用验证制品已经存在，但最近的用户工作约定是：每轮完成后可以本地 commit，**不要自动 push，也不要监控 CI**，除非用户重新明确要求。

### 3.2 文件夹来源

- 只接受 Mac 内置、固定、本地存储上的目录。
- 必须拒绝 removable、ejectable、外置盘和网络卷。
- 目录选择和重新定位都必须先校验，再修改 Portal；失败或取消不产生半完成 Tab。
- 不使用安全作用域书签、App Group 或沙盒持久化方案；当前应用是非沙盒结构。

### 3.3 Portal 和 Tab

- 支持多个 Portal、多个显示器和每个 Portal 多个 Tab。
- Tab 按创建顺序持久化；当前选中 Tab 持久化。
- Tab 是顶部大胶囊内的小文件夹名称胶囊，整体水平居中，无分割线。
- 单个 Tab 只显示一个小胶囊；Tab 上不放加号或关闭叉号。
- Tab 编辑集中在右上角设置入口。
- 关闭最后一个已有 Tab 时，仍需确认是否移除整个 Portal。
- 空 Portal 是合法、可持久化状态：`tabs == []` 时 `selectedTabID == nil`；非空时必须存在一个属于 `tabs` 的选中 ID。

### 3.4 新建流程

- 菜单栏 New Portal 打开当前指针屏幕上的透明绘制层。
- 鼠标按下后立即显示虚线 Portal 骨架，包括外框、标题区和对象位置。
- 默认/最小容量是 3 列 × 1 行。
- 拖动按半个对象单元作为阈值切换整数列数和行数：例如 3.2 仍是 3 列并显示候选反馈，3.5 切为 4 列。
- 鼠标松开后立即创建并保存空 Portal，**不再立刻弹文件夹选择器**。
- 空 Portal 内容区提供 Choose Folder…，用户从 Portal 内部选择第一个文件夹。
- 取消选择或选到不支持的位置时，空 Portal 保留。

### 3.5 容量、缩放和对象回流

- `GridCapacity(columns, rows)` 是 Portal 的持久尺寸意图，不是根据当前像素宽度临时猜出来的结果。
- 最小容量固定为 3×1。
- 窗口实时缩放使用与创建相同的半格阈值，并在结束时一次性提交最终 frame 和 capacity。
- 零位移拖动或零变化缩放不写入 placement。
- `GridCapacity.columns` 是文件网格换行的唯一列数来源。窗口边框或 clip view 的 1–2pt 差值不得把 4 列重新推导成 3 列。
- 对象采用连续 row-major 顺序：

```text
2 行 × 4 列，7 个对象：
1 2 3 4
5 6 7

2 行 × 3 列，7 个对象：
1 2 3
4 5 6
7          ← 超出两行，需要纵向滚动

2 行 × 5 列，7 个对象：
1 2 3 4 5
6 7
```

- 加宽时下一行对象按顺序补到上一行末尾；缩窄时上一行末尾对象按顺序流入下一行。
- `NSScrollView` 必须把 viewport 宽度显式同步给 document collection view，并在容量改变时使布局失效。
- 纵向滚动条使用 AppKit 原生 `.mini + .overlay + autohidesScrollers`，不占内容宽度；不滚动/不需要时由系统自动隐藏。

### 3.6 Finder 风格的文件对象

- 每个对象空间包含带 padding 的图标区和最多两行的标题区。
- 当前布局基于 Finder 桌面尺寸语义，不能把 64pt 图标、12pt 文字写死为唯一配置。
- 单击选择；Command-click 切换；Shift-click 范围选择；方向键移动；Command-A 全选。
- 双击、Command-Down 或 Command-O 打开；文件夹通过 `NSWorkspace` 在 Finder 中打开。
- Space 使用 `QLPreviewPanel` 打开或关闭 Quick Look。
- 选中标题文字为白色；图标和标题有各自的 Finder 风格选中区域。
- 默认排序为目录优先，再按 localized standard name。

### 3.7 Finder 桌面尺寸同步

- 每个 Portal 独立选择并记住 Follow Desktop 或 Alcove 的 Small / Medium / Large。
- 只有用户明确选择 Follow Desktop 时，才允许弹 Finder Automation 权限请求。
- 被动刷新必须使用 `promptIfNeeded: false`，不得自己触发权限弹窗。
- 至少一个 Portal 处于 Follow Desktop 时才监听 Finder 激活状态。
- Finder 在前台时每秒读取一次；Finder 离开前台时执行最后一次刷新并停止 timer。
- Finder 尺寸改变时保持 `GridCapacity` 不变，按新图标/文字 metrics 重算 Portal 像素 frame。
- 用户正在移动或缩放时，Finder 被动更新必须让路；交互结束后重试。
- 拒绝、撤销权限或读取失败时保留最后一个有效快照。
- 成功取得 Finder 快照后，新建 Portal 的骨架和最终 Portal 使用同一 icon layout；不能出现预览和创建结果尺寸不一致。

### 3.8 窗口、显示器与系统行为

- Portal 无普通标题栏和红黄绿交通灯。
- Portal 材质和控件在其他应用激活时仍保持 active 视觉对比。
- 应用自己跟踪顶部非控件区域的拖动，直到 mouse-up 才提交一次用户 placement。
- `windowDidMove`、`windowDidResize`、`windowDidChangeScreen` 等普通通知不能单独证明用户意图，也不能直接持久化。
- live resize 仅在 `windowDidEndLiveResize` 提交。
- 系统显示器恢复、Spaces 或 Stage Manager 导致的 frame 变化不修改用户记住的 home placement。
- placement 保存 display UUID、绝对 frame、保存时 visible frame、preferred size 和 normalized anchor。
- 显示器断开时可以临时迁移到主屏，但原 home placement 必须保留；显示器回来后恢复。

### 3.9 当前设置窗口

- Portal 右上角使用 SF Symbol `slider.horizontal.3`，不再使用 `•••`。
- 点击后打开独立设置窗口，**不是 `NSPopover` 气泡**。
- 窗口外框固定为约 `400×572pt`，每次打开在当前 Portal 所在屏幕的 visible frame 水平、垂直居中。
- 使用原生 titled/closable `NSWindow`；显示红色关闭按钮，隐藏最小化和缩放按钮。
- 顶部使用 AppKit 原生 `NSTabViewController.tabStyle = .toolbar`，不要再手写一套分类导航。
- 顶部分类固定为 Folders、Style、Other；下方只显示当前分类内容。
- 内容使用接近系统设置的“章节标题 + 圆角分组卡片”结构。
- Folders：Add Folder…、Remove 当前文件夹。
- Style：Follow Desktop / Small / Medium / Large，以及背景透明度。
- Other：目前只有 Remove Portal。
- 同一 Portal 重复点击设置图标时复用并前置同一个设置窗口；Portal 关闭时设置窗口同步关闭。
- 提交 `9cd71a3` 曾错误实现为气泡 Popover，已被 `e73385b` 的独立窗口方案取代。后续不要恢复 Popover。

视觉目标不是简单的工具栏加裸按钮，而是接近用户给出的原生设置参考：选中分类的 icon/label 使用系统强调色，未选分类使用次要文字色，toolbar 下有细分隔线；内容区有 20–24pt 级别的外边距、章节标题和接近全宽的圆角深浅分组卡片。概念线框如下：

```text
┌──────────────────────────────┐  400pt
│ ●                            │
│   [icon]      [icon]  [icon] │
│   Folders      Style   Other │  原生 toolbar tabs
├──────────────────────────────┤
│                              │
│   Section title              │
│   ┌──────────────────────┐   │
│   │ native setting row   │   │
│   │ native setting row   │   │
│   └──────────────────────┘   │
│                              │
│   Section title              │
│   ┌──────────────────────┐   │
│   │ native setting row   │   │
│   └──────────────────────┘   │
│                              │
└──────────────────────────────┘  572pt
```

## 4. 当前实现和代码地图

| 范围 | 主要文件 | 当前职责 |
|---|---|---|
| 应用生命周期 | `Alcove/Application/AppDelegate.swift` | 菜单栏应用生命周期、Finder Automation 读取、Finder 前台 monitor |
| 全局协调 | `Alcove/Application/PortalCoordinator.swift` | Portal/Tab 事务、窗口回调、持久化、Finder metrics、显示器协调 |
| 新建 | `Alcove/PortalCreation/PortalFrameSelector.swift` | 当前屏幕 overlay、虚线骨架、整数容量选择 |
| 新建事务 | `Alcove/PortalCreation/PortalCreationCoordinator.swift` | 选择 frame 后创建空 Portal |
| Portal 窗口 | `Alcove/PortalWindowing/PortalWindow.swift` | 自定义拖动、用户交互边界、系统 placement 抑制 |
| 窗口控制 | `Alcove/PortalWindowing/PortalWindowController.swift` | live resize 量化、容量提交、Quick Look/设置窗口生命周期 |
| Portal 内容 | `Alcove/PortalPresentation/PortalViewController.swift` | Tab、网格、空态、加载/错误态、设置动作转发 |
| Tab 与设置 | `Alcove/PortalPresentation/TabBarView.swift` | 顶部 Tab 胶囊、设置图标、独立原生设置窗口 |
| 材质 | `Alcove/PortalPresentation/PortalChromeMaterialView.swift` | macOS 26 Glass / macOS 15 fallback、始终 active 的表面材质 |
| 文件网格 | `Alcove/FileGrid/FileGridViewController.swift` | collection view、row-major 布局接入、选择和键盘行为 |
| 文件单元 | `Alcove/FileGrid/FileItemCell.swift` | Finder 风格对象、两行标题、选中视觉和无障碍 |
| 文件读取 | `Alcove/FolderAccess/*` | 后台枚举、路径校验、FSEvents 和恢复 |
| Quick Look | `Alcove/QuickLookIntegration/QuickLookIntegration.swift` | responder chain 和 `QLPreviewPanel` 所有权 |
| placement | `Alcove/DisplayPlacement/DisplayPlacement.swift` | NSScreen 快照、拓扑通知、legacy frame 解析 |
| 持久化 | `Alcove/Persistence/*` | v6 DTO、迁移、同目录临时文件和原子替换 |
| 纯领域/几何 | `Packages/AlcoveCore/Sources/AlcoveCore/*` | Portal、GridCapacity、GridLayout、placement state machine、selection |

## 5. 持久化现状

- 当前 envelope 版本是 v6。
- v6 允许 `selected_tab_id` 缺失，从而表达可恢复的空 Portal。
- v1–v4 会根据旧 frame 和当时 icon/text metrics 推导容量；v5 已包含 columns/rows。
- v1–v5 都迁移为 v6。
- 迁移前先写一次 `portals.vN.json.bak`；已有不同备份时停止，不能覆盖证据。
- 当前存储路径：`~/Library/Application Support/Alcove/portals.json`。
- 保存使用同目录临时文件后 replace/move；不要改成非原子覆盖写。

## 6. 已踩过的坑及禁止回退的错误方案

### 6.1 Glass 中控件完全透明

在 desktop-level 窗口中，把可点击 Tab 控件放入小型 `NSGlassEffectView.contentView` 曾出现“可以点击但完全透明”。最终结构是材质、可见 backdrop 和控件作为有序 sibling，而不是把控件嵌套进 Glass。不要为了追求层级纯粹再次把控件塞回材质 content view。

### 6.2 Tab 一度不可见

Tab 从左侧改为水平居中后，布局时机和材质层级共同导致单个 Tab 消失。当前 `TabBarView` 的直接 sibling 层级和 layout 逻辑是经过多轮修正的；修改时必须覆盖单 Tab、多个 Tab、非 key window 和材质重建测试。

### 6.3 毛玻璃发黄

直接依赖某些 material 的底色会受桌面壁纸和 appearance 影响而发黄。当前表面采用接近原生通知的 `.popover` material，并保持模糊层强度，再使用浅色模式中性白/深色模式中性黑的透明 tint 调节三档透明度。不要通过降低整个 visual effect alpha 来调透明度，否则模糊强度也会丢失。

### 6.4 Finder 尺寸不能写死

Finder 桌面 icon/text 尺寸属于用户设置。项目不读取私有 preference key；只有显式 Follow Desktop 才通过 Finder scripting boundary 请求权限。手动预设是 Alcove 自己的稳定选择。

### 6.5 容量与 frame 不能混为一谈

只保存像素 frame 会在图标尺寸改变后失去“几列几行”的用户意图。当前保存 `GridCapacity`，像素 frame 是由 capacity 和 metrics 推导的结果。

### 6.6 4 列被错误降为 3 列

真实案例中保存数据为 `columns: 4, rows: 2`，窗口 frame 宽 452pt，但内容区因边框少约 2pt。用 `availableWidth` 向下推导列数会错误得到 3，8 个对象因此变成 3 行并出现滚动条。修复后 collection layout 直接使用持久的 `GridCapacity.columns`。不要重新引入“根据 clip width 决定列数”的路径。

### 6.7 新建时立刻选文件夹不是目标流程

旧流程在绘制结束后立即打开 `NSOpenPanel`。用户明确否定了该流程；正确流程是先持久化空 Portal，再在 Portal 内点 Choose Folder。

### 6.8 设置入口不是菜单或气泡

设置入口先后出现过 `NSMenu` 和自定义 `NSPopover`。用户明确要求参考原生设置界面的独立窗口。当前实现使用原生 toolbar tabs 的 `NSWindow`；不要回退为箭头气泡。

### 6.9 用户移动和系统移动不能共用持久化回调

AppKit 的通用 frame 通知无法区分用户、WindowServer、显示器变化、Spaces 和 Stage Manager。当前移动由应用跟踪 mouse-down/drag/mouse-up，resize 使用 live-resize 生命周期；只有明确的用户结束边界才提交。

### 6.10 Finder monitor 的竞态

已经处理过以下竞态，后续改动必须保留 generation 测试：

- stop 前排队的 Finder activation Task 不得重新启动 timer。
- 被取消的旧 refresh 不得清除新 refresh 的引用。
- 旧 Finder 结果不得倒灌覆盖新的 explicit Follow 或 creation grid。
- Finder read 期间或 store save 期间开始用户交互时，不得在交互中途发布新 frame/layout。

目前 save-await 竞态使用二次校验和补偿回写旧 snapshot。仍存在一个极窄的已知风险：如果首次被动刷新写入成功后、补偿回写完成前进程崩溃，磁盘可能暂时保留 Finder 更新后的 snapshot；它不会丢失 Portal/Tab 数据或容量，但下次启动的 frame 可能使用该快照。若未来要消除该窗口，需要设计带交互 revision 的条件提交，而不是继续叠布尔值。

### 6.11 截图权限

不要向系统申请屏幕录制或截图权限。视觉验收由用户运行 Xcode 后提供截图；除非用户明确改变这一约定。

## 7. 当前进度

### 7.1 已实现并有自动化覆盖

- 菜单栏应用外壳、无 Dock 图标。
- 桌面层 Portal 窗口和自定义拖动/缩放事务边界。
- 多 Portal、多 Tab、空 Portal、新建 overlay。
- Finder 风格图标网格、选择、键盘操作、打开和 Quick Look。
- 本地固定磁盘目录校验；外置、可移除、可弹出、网络卷拒绝。
- 后台文件枚举和 FSEvents 自动刷新。
- v6 原子持久化及 v1–v5 迁移。
- 多显示器 placement state machine 和系统通知接入。
- 三档 Portal 背景透明度、macOS 26 Glass 与旧系统 fallback。
- Follow Desktop、手动 icon presets、Finder 前台有限轮询和竞态处理。
- 3×1 最小容量、创建/缩放半格阈值、capacity 驱动的 row-major 回流。
- mini overlay 自动隐藏滚动条。
- 独立的分类设置窗口及设置动作到 Coordinator 的完整链路。

### 7.2 最近验证结果

在功能提交 `e73385b` 前执行并通过：

```bash
swift test --package-path Packages/AlcoveCore

xcodebuild test -quiet \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/AlcoveNativeSettingsFinal \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''

xcodebuild build -quiet \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/AlcoveNativeSettingsRelease \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''
```

Release 二进制经 `lipo -info` 确认为 `x86_64 arm64`。

### 7.3 仍需人工验证或尚未封闭

- 最新独立设置窗口的视觉结果尚未收到用户截图确认；这是下一次 UI 对话最可能的第一项工作。
- 设置窗口需人工核对：400×572 外框、当前屏幕居中、只显示红色关闭按钮、原生 toolbar 分类、圆角卡片比例、字体和间距是否足够接近参考图。
- Portal 的 desktop-level 窗口在 macOS 15/26、多个显示器、Spaces、Stage Manager、全屏应用、睡眠唤醒和缩放切换下仍需要真实系统矩阵。
- 显示器 UUID 跨断开/重连的稳定性不是 Apple 的通用保证，仍需真实硬件证据。
- Quick Look 的 desktop-level 单项/多项行为仍需人工验证。
- macOS 26 Liquid Glass、macOS 15 fallback、Reduce Transparency、Increase Contrast、VoiceOver 和键盘全流程仍需人工视觉/系统验证。
- 最终签名、证书、Gatekeeper、quarantine、DMG 安装和证书到期行为仍是独立 release gate。

`DELIVERY_PLAN.md` 和 Spike 文档中的未勾选项包含早期计划状态，其中一部分已有自动化实现但仍缺人工证据。下一段对话不能只看 checkbox 就断言功能不存在，也不能因为代码存在就宣称真机矩阵已通过。

## 8. Git 状态与提交边界

快照时：

```text
HEAD:        e73385b fix: present portal settings in a window
origin/main: 65368f0 fix: reflow portal items during resizing
ahead:       4 commits（本交接文档提交后会再增加 1）
worktree:    M Alcove.xcodeproj/project.pbxproj
```

尚未 push 的功能提交：

```text
15a501c fix: honor portal capacity when wrapping items
e641943 fix: use a mini overlay scroller
9cd71a3 feat: add categorized portal settings
e73385b fix: present portal settings in a window
```

其中 `9cd71a3` 是设置功能链路和分类内容的基础提交，但它的 Popover 展示方式已被 `e73385b` 替换。两者都属于当前本地历史，不要删除或重写，除非用户明确授权。

`Alcove.xcodeproj/project.pbxproj` 是用户已有的 Xcode 改动，包含 object version、组排序和 Development Team/签名设置等变化。此前所有任务都明确避开了它。新的对话必须继续做到：

- 不暂存它。
- 不回退它。
- 不自动格式化它。
- 不把它混入任何功能 commit。
- 如任务必须修改该文件，先精确说明重叠范围并获得用户确认。

## 9. 当前协作约定

- 使用中文、直接说结论，避免空泛汇报。
- 每个完成的逻辑轮次单独使用 Conventional Commit，commit message 用英文。
- 当前只允许本地 commit；不要自动 push，不要监控 CI，除非用户重新明确要求。
- UI 修改不主动启动截图或申请屏幕录制权限；由用户 `Cmd + R` 验收并提供截图。
- 不覆盖工作区既有改动，不做无关重构或顺手优化。
- 用户指出 UI 不符合参考图时，先确认交互形态和系统组件层级，不要仅凭文字近似实现。例如“设置窗口”已经明确意味着独立 `NSWindow`，不是菜单或 Popover。
- 正式签名暂不处理；开发期间可以使用 Xcode 的 Apple ID/Personal Team，但不要把用户的签名配置混入无关提交。

## 10. 下一段对话建议的第一步

如果用户继续调整设置界面：

1. 让用户用当前本地 HEAD 在 Xcode `Cmd + R` 打开设置窗口并提供截图。
2. 以截图逐项核对窗口大小、居中、toolbar 高度、分类 icon/label、内容卡片宽度/圆角/间距和 dark/light appearance。
3. 只修明确偏差；不要再次替换交互形态。
4. 跑 `TabBarViewTests`、`PortalViewControllerTests`、`PortalWindowConfigurationTests`、`PortalCoordinatorTests`，再按风险决定是否跑全套。
5. 只本地 commit，保留 `project.pbxproj`，不 push。

如果用户开始别的功能，则从本文第 3 节找到业务规则，再进入对应代码和文档；不要把“设置窗口仍待视觉验收”误当作整个 MVP 唯一剩余工作。
