# Alcove 当前状态与开发交接

> 快照日期：2026-09-13（Asia/Tokyo）
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
- Tab 位于顶部水平居中的可滚动条带中，当前文件夹使用小胶囊强调；顶部控制区与文件网格之间使用轻分割线。
- 单个 Tab 只显示一个小胶囊；Tab 上不放加号或关闭叉号。
- Tab 编辑集中在右上角设置入口。
- 左上角图钉按 Portal 持久化；钉住后禁止用户拖动和缩放，但不阻断显示器恢复或内容交互。
- 关闭最后一个已有 Tab 时，仍需确认是否移除整个 Portal。
- 空 Portal 是合法、可持久化状态：`tabs == []` 时 `selectedTabID == nil`；非空时必须存在一个属于 `tabs` 的选中 ID。

### 3.4 新建流程

- 菜单栏 New Portal 打开当前指针屏幕上的透明绘制层。
- 鼠标按下后立即显示虚线 Portal 骨架，包括圆角外框、上下通长分割线和完整对象格；不再显示旧标题/路径胶囊，也不拆成 icon 与名称两个框。
- 新建选区必须与 `visibleFrame` 边缘及其他 Portal 保持全局间距；冲突候选显示为红色并留在 overlay 中继续选择，Coordinator 保存前再次校验。
- 默认/最小容量是 3 列 × 1 行。
- 拖动按半个对象单元作为阈值切换整数列数和行数：例如 3.2 仍是 3 列并显示候选反馈，3.5 切为 4 列。
- 鼠标松开后立即创建并保存空 Portal，**不再立刻弹文件夹选择器**。
- 空 Portal 内容区提供 Choose Folder…，用户从 Portal 内部选择第一个文件夹。
- 取消选择或选到不支持的位置时，空 Portal 保留。
- 创建骨架和最终窗口都为底部路径行预留固定高度，不能从文件网格容量中偷取空间。

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
- 每个完整对象空间使用细边框显示实际 tile 边界；图标和标题的选中区域仍彼此独立。
- 当前布局基于 Finder 桌面尺寸语义，不能把 64pt 图标、12pt 文字写死为唯一配置。
- 单击选择；Command-click 切换；Shift-click 范围选择；方向键移动；Command-A 全选。
- 双击、Command-Down 或 Command-O 打开；文件夹通过 `NSWorkspace` 在 Finder 中打开。
- Space 使用 `QLPreviewPanel` 打开或关闭 Quick Look。
- 选中标题文字为白色；图标和标题有各自的 Finder 风格选中区域。
- 默认排序为目录优先，再按 localized standard name。
- 当前 Tab 的文件夹路径显示在网格下方的固定行中，底部路径行与文件网格之间使用轻分割线，不使用胶囊、额外材质、填充或描边。用户目录缩写为 `~`；复制按钮把显示路径写入剪贴板。空 Portal 隐藏路径内容但保留布局高度。

### 3.7 图标尺寸

- 每个 Portal 独立选择并持久化 Small、Medium 或 Large，设置界面使用三档离散滑块。
- 不读取 Finder 设置，不发送 Apple Events，也不申请 Finder Automation 权限。
- 图标尺寸改变时保持 `GridCapacity` 和 Portal 左上角不变，按所选 preset 向右、向下重算像素 frame；优先使用当前 home display 的 `visibleFrame`，无法取得当前 descriptor 时使用其记住的 reference frame。
- 新建 Portal 的骨架和最终 Portal 都使用 Medium。

### 3.8 窗口、显示器与系统行为

- Portal 无普通标题栏和红黄绿交通灯。
- Portal 材质和控件在其他应用激活时仍保持 active 视觉对比。
- 应用自己跟踪顶部非控件区域的拖动，直到 mouse-up 才提交一次用户 placement。
- `windowDidMove`、`windowDidResize`、`windowDidChangeScreen` 等普通通知不能单独证明用户意图，也不能直接持久化。
- live resize 仅在 `windowDidEndLiveResize` 提交。
- 系统显示器恢复、Spaces 或 Stage Manager 导致的 frame 变化不修改用户记住的 home placement。
- 用户拖动使用 swept-AABB 阻止快速穿透，live resize 在实际 frame 形成后回退到上一合法 frame；两者均使用窗口当前 runtime frame 作为障碍，并按指针位置保留跨显示器 handoff。
- 全局间距变化会按显示器从保存位置派生完整 runtime 布局并平滑移动现有 Portal：处于最大 20pt 范围内的贴屏边或相邻关系使用当前档位作为精确间距，因此调大时推开、调小时也会拉回；距离较远的自由布局不会被吸到一起。重排预检失败时拒绝档位变化，不产生半套布局；自动移动不写入 durable home placement。
- placement 保存 display UUID、绝对 frame、保存时 visible frame、preferred size 和 normalized anchor。
- 显示器断开时可以临时迁移到主屏，但原 home placement 必须保留；显示器回来后恢复。

### 3.9 当前设置窗口

- Portal 右上角使用 SF Symbol `gearshape`，不再使用 `slider.horizontal.3` 或 `•••`。
- 点击后打开独立设置窗口，**不是 `NSPopover` 气泡**。
- 窗口外框固定为约 `400×572pt`，每次打开在当前 Portal 所在屏幕的 visible frame 水平、垂直居中。
- 使用原生 titled/closable `NSWindow`；最顶部的独立标题栏显示红色关闭按钮，隐藏最小化和缩放按钮。
- 标题栏下使用原生 preference-style `NSToolbar` 承载 Folders、Style 分类导航和选中状态，并以显式系统分割线隔开下方内容。
- Folders 使用 `NSTableView` 列表卡片：Glass Add Folder 位于章节标题右侧，每行显示 `~` 缩写路径，右侧提供拖拽提示和无边框删除按钮；原生拖放显示 gap 反馈并执行一次原子排序。Remove Panel 位于同页最下方带主副标题的独立危险操作卡片。
- Style 使用三档图标尺寸滑块和五档背景强度滑块。
- 内容使用接近系统设置的“章节标题 + 圆角分组卡片”结构。
- 不再存在 Other 分类或 Follow Desktop 选项。
- 同一 Portal 重复点击设置图标时复用并前置同一个设置窗口；Portal 关闭时设置窗口同步关闭。
- 提交 `9cd71a3` 曾错误实现为气泡 Popover，已被 `e73385b` 的独立窗口方案取代。后续不要恢复 Popover。

视觉目标接近用户给出的原生设置参考：原生 preference toolbar 管理分类 icon/label、选中背景和分割层级；内容区使用统一文字基线、标准内容材质和接近全宽的圆角分组卡片。概念线框如下：

```text
┌──────────────────────────────┐  400pt
│ ●                            │  标准标题栏
├──────────────────────────────┤
│       [icon]      [icon]     │
│       Folders      Style     │  原生 preference toolbar
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

### 3.10 菜单栏与本地化

- 顶层菜单依次为 New Panel、Portal 列表、应用 Settings、Quit；Portal 名称的二级菜单只提供 Show 和 Hide。
- 顶层 Settings 指整个 Alcove 的应用设置，不是单个 Portal 的设置窗口；点击后打开可复用的独立设置窗口。General 提供系统登录时自动启动、全局五档面板间距（4/8/12/16/20pt）、五档圆角（0/8/14/20/24pt）和系统阴影开关；About 使用 Icon Composer 生成的应用图标并显示应用名称、版本、构建号和版权信息。全局外观写入 `UserDefaults`，不复制 Portal v11 的单面板排序和颜色状态。
- 所有用户可见文本、错误、菜单和无障碍说明提供 English、简体中文和繁体中文。
- English 是开发语言和兜底语言；系统语言不是上述三种时使用 English。

## 4. 当前实现和代码地图

| 范围 | 主要文件 | 当前职责 |
|---|---|---|
| 应用生命周期 | `Alcove/Application/AppDelegate.swift` | 菜单栏应用生命周期、持久状态恢复和终止协调 |
| 全局协调 | `Alcove/Application/PortalCoordinator.swift` | Portal/Tab 事务、窗口回调、持久化和显示器协调 |
| 新建 | `Alcove/PortalCreation/PortalFrameSelector.swift` | 当前屏幕 overlay、虚线骨架、整数容量选择 |
| 新建事务 | `Alcove/PortalCreation/PortalCreationCoordinator.swift` | 选择 frame 后创建空 Portal |
| Portal 窗口 | `Alcove/PortalWindowing/PortalWindow.swift` | 自定义拖动、用户交互边界、系统 placement 抑制 |
| 窗口控制 | `Alcove/PortalWindowing/PortalWindowController.swift` | live resize 量化、容量提交、Quick Look/设置窗口生命周期 |
| Portal 内容 | `Alcove/PortalPresentation/PortalViewController.swift` | Tab、分区线、网格、底部路径行、空态、加载/错误态、设置动作转发 |
| Tab 与设置 | `Alcove/PortalPresentation/TabBarView.swift` | 左侧图钉、顶部 Tab 胶囊、设置图标、双行窗口 chrome、文件夹管理和离散样式滑块 |
| 材质 | `Alcove/PortalPresentation/PortalChromeMaterialView.swift` | macOS 26 Glass / macOS 15 fallback、始终 active 的表面材质 |
| 文件网格 | `Alcove/FileGrid/FileGridViewController.swift` | collection view、row-major 布局接入、选择和键盘行为 |
| 文件单元 | `Alcove/FileGrid/FileItemCell.swift` | Finder 风格对象、两行标题、选中视觉和无障碍 |
| 文件读取 | `Alcove/FolderAccess/*` | 后台枚举、路径校验、FSEvents 和恢复 |
| Quick Look | `Alcove/QuickLookIntegration/QuickLookIntegration.swift` | responder chain 和 `QLPreviewPanel` 所有权 |
| placement | `Alcove/DisplayPlacement/DisplayPlacement.swift` | NSScreen 快照、拓扑通知、legacy frame 解析 |
| 持久化 | `Alcove/Persistence/*` | v11 DTO、v1–v10 迁移、同目录临时文件和原子替换 |
| 纯领域/几何 | `Packages/AlcoveCore/Sources/AlcoveCore/*` | Portal、GridCapacity、GridLayout、placement state machine、selection |

## 5. 持久化现状

- 当前 envelope 版本是 v11；每个 Portal 持久化排序方式和内置颜色预设。
- v6 引入的可选 `selected_tab_id` 和 v7 引入的必需 `is_pinned` 继续保留；v8 对应网格上下边距从 16pt 收紧到 8pt，v9 对应对象横向间距从 12pt 收紧到与纵向一致的 4pt。
- v1–v4 会根据旧 frame 和当时 icon/text metrics 推导容量；v5 已包含 columns/rows。
- v1–v10 都迁移为 v11；v10 缺少排序和颜色时使用 `.name` / `.default`。旧 `follow_desktop` 按最后保存的图标尺寸映射到最近的 Small/Medium/Large。迁移按当前 capacity 和 metrics 统一重算 frame，保持原顶部、右侧位置（显示器空间允许时）、容量、图钉和 Tab 顺序，并重新计算 normalized anchor。
- 迁移前先写一次 `portals.vN.json.bak`；已有不同备份时停止，不能覆盖证据。
- 当前存储路径：`~/Library/Application Support/Alcove/portals.json`。
- 保存使用同目录临时文件后 replace/move；不要改成非原子覆盖写。

## 6. 已踩过的坑及禁止回退的错误方案

### 6.1 Glass 中控件完全透明

在 desktop-level 窗口中，把可点击 Tab 控件放入小型 `NSGlassEffectView.contentView` 曾出现“可以点击但完全透明”。当前 Portal 已取消顶部 control-group Glass 和外层胶囊，改为普通可滚动 Tab 条带与上下轻分割线；不要重新引入该不可见的嵌套 Glass 结构。

### 6.2 Tab 一度不可见

Tab 从左侧改为水平居中后，布局时机和材质层级共同导致单个 Tab 消失。当前 `TabBarView` 的直接 sibling 层级和 layout 逻辑是经过多轮修正的；修改时必须覆盖单 Tab、多个 Tab、非 key window 和材质重建测试。

### 6.3 毛玻璃发黄

直接依赖某些 material 的底色会受桌面壁纸和 appearance 影响而发黄。当前表面采用接近原生通知的 `.popover` material，并保持模糊层强度，再使用浅色模式中性白/深色模式中性黑的透明 tint 调节五档背景强度。不要通过降低整个 visual effect alpha 来调透明度，否则模糊强度也会丢失。

### 6.4 图标尺寸只有三个稳定档位

当前只支持 Alcove 自己的 Small、Medium、Large，不读取系统或 Finder 设置。设置控件必须保持三档离散值，不能重新加入任意值或外部同步状态。

### 6.5 容量与 frame 不能混为一谈

只保存像素 frame 会在图标尺寸改变后失去“几列几行”的用户意图。当前保存 `GridCapacity`，像素 frame 是由 capacity 和 metrics 推导的结果。

### 6.6 4 列被错误降为 3 列

真实案例中保存数据为 `columns: 4, rows: 2`，窗口 frame 宽 452pt，但内容区因边框少约 2pt。用 `availableWidth` 向下推导列数会错误得到 3，8 个对象因此变成 3 行并出现滚动条。修复后 collection layout 直接使用持久的 `GridCapacity.columns`。不要重新引入“根据 clip width 决定列数”的路径。

### 6.7 新建时立刻选文件夹不是目标流程

旧流程在绘制结束后立即打开 `NSOpenPanel`。用户明确否定了该流程；正确流程是先持久化空 Portal，再在 Portal 内点 Choose Folder。

### 6.8 设置入口不是菜单或气泡

设置入口先后出现过 `NSMenu` 和自定义 `NSPopover`。用户明确要求参考原生设置界面的独立窗口。当前实现使用带 preference-style `NSToolbar` 的独立窗口；不要回退为箭头气泡或内容内自定义分类栏。

### 6.9 用户移动和系统移动不能共用持久化回调

AppKit 的通用 frame 通知无法区分用户、WindowServer、显示器变化、Spaces 和 Stage Manager。当前移动由应用跟踪 mouse-down/drag/mouse-up，resize 使用 live-resize 生命周期；只有明确的用户结束边界才提交。

### 6.10 文件夹顺序只有一份状态

`Portal.tabs` 数组是显示和持久化顺序的唯一来源。设置页的上移/下移必须通过 Coordinator 的 persistence-first 事务交换相邻元素，不能在 UI 中维护第二份排序；选中 Tab ID 在重排后保持不变。

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
- v11 原子持久化及 v1–v10 迁移。
- 多显示器 placement state machine 和系统通知接入。
- 五档 Portal 背景强度、macOS 26 Glass 与旧系统 fallback。
- Small/Medium/Large 三档手动 icon presets；没有 Finder Automation 或外部尺寸同步。
- 3×1 最小容量、创建/缩放半格阈值、capacity 驱动的 row-major 回流。
- mini overlay 自动隐藏滚动条。
- 原生 preference toolbar 设置窗口、原生表格文件夹排序、离散样式滑块及完整 Coordinator 动作链路。
- 可持久化图钉、底部路径与复制按钮、菜单栏 Show/Hide，以及包含 General/About 的全局 Settings 窗口。
- English、简体中文、繁体中文完整 bundle 本地化，其他系统语言回退 English。

### 7.2 最近验证结果

本轮图钉、路径栏、菜单、本地化与等距紧凑网格实现后执行并通过：

```bash
swift test --package-path Packages/AlcoveCore

xcodebuild test -quiet \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/AlcoveSettingsRedesignTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''

xcodebuild build -quiet \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/AlcoveSettingsRedesignRelease \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''
```

Core 125 项测试和完整 AppKit 测试通过；Release 二进制经 `lipo -info` 确认为
`x86_64 arm64`，应用 bundle 包含 `en`、`zh-Hans`、`zh-Hant` 的
`Localizable.strings`。Finder Automation 权限说明已从 Info.plist 和资源中移除。

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
- 设置窗口需人工核对：约 400×572 外框、当前屏幕居中、preference toolbar 的分类 icon/label 与选中背景、圆角卡片比例、Glass 按钮、滑块、字体和间距是否足够接近参考图。
- Portal 的 desktop-level 窗口在 macOS 15/26、多个显示器、Spaces、Stage Manager、全屏应用、睡眠唤醒和缩放切换下仍需要真实系统矩阵。
- 显示器 UUID 跨断开/重连的稳定性不是 Apple 的通用保证，仍需真实硬件证据。
- Quick Look 的 desktop-level 单项/多项行为仍需人工验证。
- macOS 26 Liquid Glass、macOS 15 fallback、Reduce Transparency、Increase Contrast、VoiceOver 和键盘全流程仍需人工视觉/系统验证。
- 最终签名、证书、Gatekeeper、quarantine、DMG 安装和证书到期行为仍是独立 release gate。

`DELIVERY_PLAN.md` 和 Spike 文档中的未勾选项包含早期计划状态，其中一部分已有自动化实现但仍缺人工证据。下一段对话不能只看 checkbox 就断言功能不存在，也不能因为代码存在就宣称真机矩阵已通过。

## 8. Git 状态与提交边界

本轮实现尚未提交。除下述既有 `project.pbxproj` 变更外，工作区还包含本轮图钉、
路径 footer、v10 迁移、菜单、本地化、测试和文档改动。用户已明确允许仅为本地化
资源修改 `project.pbxproj`；新增的 variant groups、known regions 和 Resources build
phase 条目属于本轮，原有 object version、组排序和 Development Team/签名设置仍属于
用户既有改动。后续若提交，必须按 hunk 区分，不能把整份工程文件直接混入功能提交。

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
2. 以截图逐项核对窗口大小、居中、preference toolbar、分类 icon/label、分割线、内容卡片宽度/圆角/间距和 dark/light appearance。
3. 只修明确偏差；不要再次替换交互形态。
4. 跑 `TabBarViewTests`、`PortalViewControllerTests`、`PortalWindowConfigurationTests`、`PortalCoordinatorTests`，再按风险决定是否跑全套。
5. 只本地 commit，保留 `project.pbxproj`，不 push。

如果用户开始别的功能，则从本文第 3 节找到业务规则，再进入对应代码和文档；不要把“设置窗口仍待视觉验收”误当作整个 MVP 唯一剩余工作。
