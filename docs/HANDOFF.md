# Alcove 当前状态与开发交接

> 快照日期：2026-09-15（Asia/Tokyo）
>
> 适用基线：`HEAD 00d2bc4`；主显示器跟随与位置修复改动尚未提交
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

Alcove 是一个原生 macOS 菜单栏工具。它在桌面图标之上、普通应用窗口之下展示可移动、可缩放的文件夹 Portal；每个 Portal 可以包含多个文件夹 Tab，并提供 Finder 风格的图标网格、选择、打开、Quick Look、自动刷新和主显示器跟随恢复。

它不是 Finder 替代品。每个 Tab 可在映射根目录内进行运行时导航，但映射根路径不随浏览改变；支持进废纸篓及 Finder 文件 URL 的拖入/拖出，仍不提供重命名、新建文件夹、覆盖冲突项或文件操作撤销。

## 3. 已确认的产品范围

### 3.1 平台与发布

- 原生 AppKit 应用，最低 macOS 15，主要视觉目标 macOS 26。
- `LSUIElement` 菜单栏应用，不显示 Dock 图标。
- 通用架构：`arm64 + x86_64`。
- macOS 26 使用适用的 Liquid Glass；macOS 15 使用原生 `NSVisualEffectView` 回退。Apple 在 macOS 15 后直接采用年份版本号 26，不存在 macOS 16～25 产品版本。
- 正式签名、证书和最终 DMG 发布不是当前 UI 功能工作的阻塞项；用户已明确要求暂时不要处理正式签名。
- GitHub CI 和无签名通用验证制品已经存在，但最近的用户工作约定是：每轮完成后可以本地 commit，**不要自动 push，也不要监控 CI**，除非用户重新明确要求。

### 3.2 文件夹来源

- 只接受 Mac 内置、固定、本地存储上的目录。
- 必须拒绝 removable、ejectable、外置盘和网络卷。
- 目录选择和重新定位都必须先校验，再修改 Portal；失败或取消不产生半完成 Tab。
- 不使用安全作用域书签、App Group 或沙盒持久化方案；当前应用是非沙盒结构。

### 3.3 Portal 和 Tab

- 支持多个 Portal 和每个 Portal 多个 Tab；多个已连接显示器只作为拓扑输入，所有 Portal 始终位于菜单栏主显示器。
- Tab 按创建顺序持久化；当前选中 Tab 持久化。
- 每个 Portal 最多包含四个文件夹 Tab。顶部使用一个水平居中的无阴影分段胶囊，内部 Segment 等宽、相连且只有当前文件夹显示中性选中胶囊，不使用蓝色强调。Small/Medium/Large 的目标 Segment 宽度为 `56/64/72pt`、高度为 `26/28/30pt`；空间不足时全部等比压缩，不提供横向滚动。长名称尾部省略，但 Tooltip 和无障碍名称保持完整。左右始终按返回按钮的完整宽度做对称逻辑预留，即使返回暂时隐藏，右侧齿轮也占相同布局宽度，因此 Tab 组不随目录层级偏移。返回按钮用 `imageHugsTitle` 将箭头和文字作为一个整体居中。Portal 接收任意左键点击时先激活 Alcove 并成为 key window。
- 单个 Tab 只显示一个小胶囊；Tab 上不放加号或关闭叉号。
- Tab 编辑集中在右上角设置入口。
- 右上角齿轮打开原生菜单：钉住/取消钉住、排序方式子菜单、面板设置、确认后删除面板。顶部不再单独显示图钉；钉住状态仍按 Portal 持久化，并且不阻断显示器恢复或内容交互。
- 删除确认使用独立的 app-modal `NSAlert`，按当前 Portal 所在屏幕的实时 `visibleFrame` 水平、垂直居中，不作为 Sheet 挂在 Portal 上。
- 齿轮菜单的钉住、排序、面板设置和删除项都使用对应 SF Symbol。单面板 General 将三种排序方式直接显示为原生单选项；Folders 显示当前数量/4和上限说明，在四个时禁用添加；Style 将八种内置 tint 直接显示为圆形颜色单选，不再使用下拉菜单。
- 每个 Portal 持久化名称/修改时间/创建时间排序，以及默认、红、橙、黄、绿、蓝、靛、紫八种内置磨玻璃 tint；透明强度仍由全局 Style 统一控制。
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
- 从网格空白处双向拖拽可框选与 tile 相交的对象；Command-框选以 mouse-down 时冻结的选择为基准切换。框选进入滚动边缘时使用 AppKit autoscroll，文件区事件不能触发 Portal 顶栏拖动。
- 双击普通目录在当前 Tab 内进入；Package 和符号链接交给系统默认 App。每个 Tab 独立保留运行时 currentURL、返回历史、选择和滚动位置，重启回到映射根目录。
- 子目录中顶部左侧显示原生返回按钮；底部路径栏跟随 currentURL，路径可在 Finder 打开，并提供 Apple Terminal 与最右侧绝对路径复制按钮。
- Space 使用 `QLPreviewPanel` 打开或关闭 Quick Look。
- Command-Delete 冻结当前有序 URL、立即清空选择并使 Quick Look 失效，再通过 `NSWorkspace.recycle` 移入废纸篓；失败必须显示错误。
- 从 Alcove 向 Finder/桌面拖动使用 `NSCollectionView` 原生多项 drag session 和 `NSURL` pasteboard writer，源端不在 drop 结束后自行删除。
- Finder 拖入只接受当前浏览目录的网格空白背景。默认 Copy，按住 Command 才请求 Move；操作前全量拒绝同目录、同名目标、重复目标名和目录进入自身后代，绝不覆盖。实际 IO 在 actor 中通过 `NSFileCoordinator` 串行协调，完成后显式 reload，并由 FSEvents 最终收敛；中途失败集中报告已完成数量。
- 选中标题文字为白色；图标和标题有各自的 Finder 风格选中区域。
- 默认排序为目录优先，再按 localized standard name。
- 当前浏览路径显示在网格下方的固定行中，底部路径行与文件网格之间使用轻分割线，不使用胶囊、额外材质、填充或描边。用户目录缩写为 `~`；Finder、Terminal 和复制操作都使用真实 currentURL，复制写入绝对路径。空 Portal 隐藏路径内容但保留布局高度。

### 3.7 图标尺寸

- 所有 Portal 共享全局 Small、Medium 或 Large 内容尺寸，设置界面使用三档离散滑块。
- 不读取 Finder 设置，不发送 Apple Events，也不申请 Finder Automation 权限。
- 内容尺寸改变时保持每个 Portal 的 `GridCapacity`，以改变前的实际 frame 识别贴屏和面板相邻关系，再用新尺寸统一重排。同组面板在放大和缩小时都保持所选精确间距；自由面板保留左上角意图。每块屏幕完整预演后才统一动画，任一布局放不下则整次拒绝。
- 新建 Portal 的骨架和最终 Portal 都使用 Medium。

### 3.8 窗口、显示器与系统行为

- Portal 无普通标题栏和红黄绿交通灯。
- Portal 材质和控件在其他应用激活时仍保持 active 视觉对比。
- 应用自己跟踪顶部非控件区域的拖动，直到 mouse-up 才提交一次用户 placement。
- `windowDidMove`、`windowDidResize`、`windowDidChangeScreen` 等普通通知不能单独证明用户意图，也不能直接持久化。
- live resize 仅在 `windowDidEndLiveResize` 提交。
- 系统显示器恢复、Spaces 或 Stage Manager 导致的 frame 变化不修改用户记住的 home placement。
- 菜单栏主显示器严格取实时 `NSScreen.screens[0]`，不能使用表示键盘焦点屏幕的 `NSScreen.main`。新建、拖动和缩放都限制在该主屏的 `visibleFrame`，不再支持把 Portal 长期留在副屏。
- 用户拖动使用 swept-AABB 阻止快速穿透，live resize 在实际 frame 形成后回退到上一合法 frame；两者均使用窗口当前 runtime frame 作为障碍。
- 主显示器切换、拔插、缩放或分辨率变化时，完整布局按旧主屏 `visibleFrame` 左边和上边的 pt 偏移投影到新主屏。仍完整可见且不冲突的 Portal 按稳定顺序锁定；溢出项按原视觉顺序向右新开列并从上到下排列。若固定尺寸仍无法全部容纳，则优先使用不同的顶部露出槽位，有限槽位耗尽后允许完全重叠；菜单栏 Show 始终可把指定 Portal 提到最前。系统迁移不覆盖旧显示器持久布局，切回时只在所有 Portal 都有该屏记录时整组恢复，否则整组从当前布局投影。
- 全局间距变化会从保存位置派生完整 runtime 布局并平滑移动现有 Portal：处于最大 20pt 范围内的贴屏边或相邻关系使用当前档位作为精确间距，因此调大时推开、调小时也会拉回；距离较远的自由布局不会被吸到一起。重排预检失败时拒绝档位变化，不产生半套布局；自动移动不写入 durable placement。
- placement 保存 display UUID、绝对 frame、保存时 visible frame、preferred size 和 normalized anchor。
- Application Settings → Advanced 提供“修复面板位置”：按稳定顺序只修复不在主屏可见区域内或与先前正常 Portal 冲突的 Portal，正常 Portal 的 runtime frame 和持久化 placement 都不变；修复结果先单次保存，再动画应用。

### 3.9 当前设置窗口

- Portal 右上角使用 SF Symbol `gearshape`，不再使用 `slider.horizontal.3` 或 `•••`。
- 点击后打开独立设置窗口，**不是 `NSPopover` 气泡**。
- 窗口外框固定为约 `400×572pt`，每次打开在当前 Portal 所在屏幕的 visible frame 水平、垂直居中。
- 使用原生 titled/closable `NSWindow`；最顶部的独立标题栏显示红色关闭按钮，隐藏最小化和缩放按钮。
- 标题栏下使用原生 preference-style `NSToolbar` 承载 Folders、Style 分类导航和选中状态，并以显式系统分割线隔开下方内容。
- Folders 使用 `NSTableView` 列表卡片：Glass Add Folder 位于章节标题右侧，每行显示 `~` 缩写路径，右侧提供拖拽提示和无边框删除按钮；原生拖放显示 gap 反馈并执行一次原子排序。Remove Panel 位于同页最下方带主副标题的独立危险操作卡片。
- 单面板设置不再提供图标尺寸和背景强度；两者由全局 Settings → Style 统一控制。
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

- 顶层菜单依次为 New Panel、Portal 列表、应用 Settings、Quit；每个 Portal 名称的二级菜单提供带 SF Symbol 的 Show、Hide、Pin/Unpin、Panel Settings 和确认后 Remove。
- 顶层 Settings 指整个 Alcove 的应用设置，不是单个 Portal 的设置窗口；当前分类为 General / Style / Advanced / About。General 只提供系统登录时自动启动；Style 统一控制三档内容大小、五档背景透明度、五档面板间距、五档圆角和系统阴影；Advanced 通过独立的布局备份 v1 JSON 执行完整导入/导出；About 使用 Icon Composer 图标并显示名称、版本、构建号和版权。全局外观写入 `UserDefaults`，不复制 Portal v11 的单面板排序和颜色状态。
- 全局 Style 卡片的每个设置行之间使用系统分割线；Advanced 备份卡片继续以一条系统分割线区分说明和操作按钮。
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
| Tab 与设置 | `Alcove/PortalPresentation/TabBarView.swift` | 原生 Glass/旧系统回退 Tab、齿轮管理菜单、单面板 General/Folders/Style 设置 |
| 材质 | `Alcove/PortalPresentation/PortalChromeMaterialView.swift` | macOS 26 Glass / macOS 15 fallback、始终 active 的表面材质 |
| 文件网格 | `Alcove/FileGrid/FileGridViewController.swift` | collection view、row-major 布局接入、选择和键盘行为 |
| 文件单元 | `Alcove/FileGrid/FileItemCell.swift` | Finder 风格对象、两行标题、选中视觉和无障碍 |
| 文件读取 | `Alcove/FolderAccess/*` | 后台枚举、路径校验、FSEvents 和恢复 |
| Quick Look | `Alcove/QuickLookIntegration/QuickLookIntegration.swift` | responder chain 和 `QLPreviewPanel` 所有权 |
| placement | `Alcove/DisplayPlacement/DisplayPlacement.swift` | 菜单栏主屏识别、NSScreen 快照、拓扑通知、legacy frame 解析 |
| 持久化 | `Alcove/Persistence/*` | v11 DTO、v1–v10 迁移、同目录临时文件和原子替换 |
| 布局备份 | `Alcove/Application/ApplicationLayoutBackupController.swift`、`Alcove/Persistence/AlcoveLayoutBackupCodec.swift` | JSON 面板、后台原子 I/O、公开 v1 codec 和替换式导入 |
| 纯领域/几何 | `Packages/AlcoveCore/Sources/AlcoveCore/*` | Portal、GridCapacity、GridLayout、placement state machine、主屏投影/溢出恢复、selection |

## 5. 持久化现状

- 当前 envelope 版本是 v11；每个 Portal 持久化排序方式和内置颜色预设。
- v6 引入的可选 `selected_tab_id` 和 v7 引入的必需 `is_pinned` 继续保留；v8 对应网格上下边距从 16pt 收紧到 8pt，v9 对应对象横向间距从 12pt 收紧到与纵向一致的 4pt。
- v1–v4 会根据旧 frame 和当时 icon/text metrics 推导容量；v5 已包含 columns/rows。
- v1–v10 都迁移为 v11；v10 缺少排序和颜色时使用 `.name` / `.default`。旧 `follow_desktop` 按最后保存的图标尺寸映射到最近的 Small/Medium/Large。迁移按当前 capacity 和 metrics 统一重算 frame，保持原顶部、右侧位置（显示器空间允许时）、容量、图钉和 Tab 顺序，并重新计算 normalized anchor。
- 迁移前先写一次 `portals.vN.json.bak`；已有不同备份时停止，不能覆盖证据。
- 当前存储路径：`~/Library/Application Support/Alcove/portals.json`。
- 保存使用同目录临时文件后 replace/move；不要改成非原子覆盖写。
- 布局备份是独立的 `com.alcove.layout-backup` v1 公共格式，不直接导出内部 v11 JSON。导入只支持完整替换：严格解码并预演主显示器布局，单次持久化成功后才关闭旧窗口；失败不改变运行时状态。开机自启动不进入备份。

## 6. 已踩过的坑及禁止回退的错误方案

### 6.1 Glass 中控件完全透明

在 desktop-level 窗口中，把可点击 Tab 控件放入小型 `NSGlassEffectView.contentView` 曾出现“可以点击但完全透明”。当前 macOS 26 的整块 Portal 表面使用一个 `NSGlassEffectView`，Tab 自身只是普通无边框 Layer 胶囊，不再为顶部控件嵌套第二层 Glass。不要重新引入该不可见的嵌套控制组 Glass。

### 6.2 Tab 一度不可见

Tab 从左侧改为水平居中后，布局时机和材质层级共同导致单个 Tab 消失。当前 `TabBarView` 的直接 sibling 层级和 layout 逻辑是经过多轮修正的；修改时必须覆盖单 Tab、多个 Tab、非 key window 和材质重建测试。

### 6.3 毛玻璃发黄

macOS 26 的标准默认表面直接使用 `.regular` `NSGlassEffectView`，`tintColor == nil`，由系统根据壁纸决定原生 Glass 外观。最透明/较透明档使用 `.clear`，较不透明档使用 `.regular` 加轻量中性 tint；彩色预设通过 `NSGlassEffectView.tintColor` 着色，不再叠加普通颜色 View。macOS 15 使用 `.popover` `NSVisualEffectView` 与现有五档覆盖层回退。不要通过降低整个材质 View 的 alpha 调透明度，否则模糊强度也会丢失。

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
- 空白框选、Command-Delete 进废纸篓、原生文件 URL 拖出，以及以 currentURL 为目标的 Finder 拖入 Copy/Command-Move。
- 本地固定磁盘目录校验；外置、可移除、可弹出、网络卷拒绝。
- 后台文件枚举和 FSEvents 自动刷新。
- v11 原子持久化及 v1–v10 迁移。
- 多显示器 placement state machine 和系统通知接入。
- 所有 Portal 跟随菜单栏主显示器；保持左/上 pt 偏移、锁定仍可见面板、溢出向右开列、极端重叠露出顶栏，并提供 Advanced 一键位置修复。
- 五档 Portal 背景强度、macOS 26 Glass 与旧系统 fallback。
- Small/Medium/Large 三档手动 icon presets；没有 Finder Automation 或外部尺寸同步。
- 3×1 最小容量、创建/缩放半格阈值、capacity 驱动的 row-major 回流。
- mini overlay 自动隐藏滚动条。
- 原生 preference toolbar 设置窗口、原生表格文件夹排序、离散样式滑块及完整 Coordinator 动作链路。
- 可持久化图钉、排序与 tint，底部 Finder/Terminal/复制路径按钮，菜单栏 Show/Hide，以及包含 General/Style/Advanced/About 的全局 Settings 窗口。
- English、简体中文、繁体中文完整 bundle 本地化，其他系统语言回退 English。

### 7.2 最近验证结果

主显示器跟随与一键位置修复实现后执行并通过：

```bash
swift test --package-path Packages/AlcoveCore

xcodebuild test -quiet \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/AlcovePrimaryDisplayRiskFixFinal \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''

xcodebuild build -quiet \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/AlcovePrimaryDisplayRiskFixFinalRelease \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''
```

Core 共 159 项 XCTest 通过；hosted app 260 项测试通过；Release 为 `x86_64 + arm64`。覆盖菜单栏主屏识别、左上 pt
偏移投影、`1–8` 溢出新列、有限重叠槽位优先耗尽、部分历史记录不与当前布局混用、
冲突候选进入 overflow、旧主屏仍连接时全体跟随新主屏、手动修复只持久化离屏/冲突
Portal、无修复时零写入、保存失败时 runtime 零变化，以及窗口拒绝应用时不误报成功。

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
- 主屏在 27 英寸 4K、14 英寸内置屏和当前竖屏显示器之间切换时，左上偏移、溢出新列、返回旧布局和极端重叠仍需真机人工验证。
- 显示器 UUID 跨断开/重连的稳定性不是 Apple 的通用保证，仍需真实硬件证据。
- Quick Look 的 desktop-level 单项/多项行为仍需人工验证。
- macOS 26 Liquid Glass、macOS 15 fallback、Reduce Transparency、Increase Contrast、VoiceOver 和键盘全流程仍需人工视觉/系统验证。
- 最终签名、证书、Gatekeeper、quarantine、DMG 安装和证书到期行为仍是独立 release gate。

`DELIVERY_PLAN.md` 和 Spike 文档中的未勾选项包含早期计划状态，其中一部分已有自动化实现但仍缺人工证据。下一段对话不能只看 checkbox 就断言功能不存在，也不能因为代码存在就宣称真机矩阵已通过。

## 8. Git 状态与提交边界

主显示器跟随、一键位置修复、本地化、测试和相关文档改动尚未提交。
`Alcove.xcodeproj/project.pbxproj` 本轮未修改；新 Swift 文件通过现有同步文件组进入构建。

快照时：

```text
HEAD:        00d2bc4 feat: cap portal folder tabs
origin/main: 666b709 feat: reflow attached portals with content size
ahead:       3 commits
worktree:    本轮主显示器跟随与位置修复改动，未提交
```

尚未 push 的功能提交：

```text
0193501 feat: refine portal chrome appearance
5bd8b2e feat: adopt native portal glass styling
00d2bc4 feat: cap portal folder tabs
```

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
