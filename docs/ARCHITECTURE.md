# Alcove 架构

本文描述当前生产实现的组件、所有权、持久化边界和仍需人工验证的系统风险。产品范围和交互契约见 `PRODUCT_REQUIREMENTS.md`，开发、测试和发布流程见 `development.md`，外部平台证据见 `RESEARCH.md`。

## 1. 系统结构

Alcove 是单进程、非沙盒的 macOS 菜单栏应用。仓库包含一个 Xcode 应用 target、一个 XCTest target，以及一个独立 Swift Package：

```text
Alcove.app
├── Application             生命周期、菜单栏、全局设置、更新和 Portal 编排
├── PortalWindowing         桌面层 NSWindow、拖动、缩放和窗口生命周期
├── PortalPresentation      Tab、面板内容、路径栏和 Portal 设置
├── FileGrid                NSCollectionView、选择、导航和文件操作
├── FolderAccess            目录校验、枚举、加载协调和 FSEvents
├── QuickLookIntegration    QLPreviewPanel responder-chain 所有权
├── DisplayPlacement        NSScreen 快照、主显示器投影和布局恢复
└── Persistence             Portal schema、迁移和布局备份

AlcoveCore                  UI-free Swift Package：领域模型和纯布局几何
```

这些 App 目录是源码职责分组，不是独立编译模块。依赖方向由类型所有权和组合方式维护：

- `AlcoveCore` 不导入 AppKit 或 SwiftUI，不执行文件 IO，也不了解窗口生命周期。
- `App/` 负责 AppKit、系统 API、文件系统、持久化和组合。
- `PortalCoordinator` 是 Portal 生命周期、持久化事务和显示器变化的应用级编排器。
- 视图和窗口控制器只呈现状态、接收交互并调用既有协调边界，不复制领域或文件操作规则。

## 2. 应用与窗口生命周期

`AppDelegate` 创建长期存活的应用级依赖、菜单栏入口、应用设置和 `PortalCoordinator`。Alcove 使用 `NSStatusItem`，`LSUIElement=true`，不显示 Dock 图标。

每个 Portal 由一组对象共同拥有：

- `PortalWindow`：桌面层窗口、可成为 key window 的交互策略，以及显式用户拖动事务。
- `PortalWindowController`：窗口与内容控制器生命周期、live resize 和 Quick Look 清理。
- `PortalViewController`：Tab 内容、文件网格、路径栏、空态和设置动作。
- `PortalCoordinator`：领域状态、持久化、窗口集合和跨 Portal 布局事务。

窗口使用 `desktopIconWindow + 1`，并采用当前代码中的 collection behavior 以保持桌面层和跨 Space 可见性。WindowServer、Spaces、Stage Manager、全屏和睡眠唤醒属于系统行为边界，自动测试只能验证配置和应用侧状态机，不能替代真实系统验证。

## 3. Portal 领域不变量

`AlcoveCore.Portal` 维护可持久化的业务状态：

- 空 Portal 是合法状态：`tabs` 为空时 `selectedTabID` 必须为 `nil`。
- 非空 Portal 必须选中一个实际存在于 `tabs` 中的 ID。
- 每个 Portal 最多四个 Tab；`Portal.tabs` 是显示顺序和持久化顺序的唯一来源。
- 每个 Tab 持久化映射根目录；当前浏览目录、返回历史、选择和滚动位置只属于运行时状态。
- `GridCapacity(columns, rows)` 是 Portal 的持久尺寸意图，最小为 `3×1`。
- `GridCapacity.columns` 是网格换行的唯一列数来源，不从存在边框或 clip view 误差的像素宽度反推。
- pinned 状态只禁止用户拖动和缩放，不阻止内容交互、显示器恢复或菜单栏 Show。

全局内容大小、透明度、间距、圆角、阴影和语言保存在 `UserDefaults`；Portal envelope 只保存单面板状态，例如容量、Tab、placement、排序、tint 和 pinned。

## 4. 主显示器与布局

Alcove 把实时 `NSScreen.screens[0]` 视为菜单栏主显示器，不使用代表键盘焦点屏幕的 `NSScreen.main`。所有 Portal 和新建 overlay 始终位于主显示器的 `visibleFrame`。

布局有两类来源：

- 用户来源：应用显式跟踪 top-row 拖动直到 mouse-up，并在 live resize 结束时提交一次 placement。
- 系统来源：显示器切换、断开、分辨率、缩放、Spaces 或 WindowServer 引起的 frame 变化。

只有明确完成的用户拖动或 live resize 可以写入用户 placement。普通 `windowDidMove`、`windowDidResize` 或系统投影不是用户意图，不得覆盖持久状态。

显示器拓扑变化时，Coordinator 对完整布局做一次预演：

1. 从旧主屏 `visibleFrame` 的左、上 point offset 投影到新主屏。
2. 按稳定顺序保留仍完整可见且不冲突的 frame。
3. 把溢出项向右开列并从上到下排列。
4. 空间不足时使用有限的顶部露出槽位；极端情况下允许重叠，但菜单栏 Show 仍可前置指定 Portal。
5. 完整计划可行后统一应用；系统投影不覆盖其他显示器的记忆布局。

内容大小或间距变化同样先对全部 Portal 预演。任何 Portal 无法合法放置时整次拒绝，不产生半套 runtime 或 durable 状态。

## 5. 文件夹加载与观察

文件夹选择和重新定位先经过 `FolderLocationValidator`。只有位于本机内置、固定、本地、不可移除且不可弹出的卷上的目录才能进入 Portal 状态；网络卷、外置卷和不合格路径在持久化前拒绝。

加载流程由真实实现中的 `FolderLoadingCoordinator` 管理：

```text
用户切换 Tab / 路径
  → 生成新的 request generation，并取消旧任务
  → 在专用后台执行边界枚举目录
  → 回到 MainActor
  → 仅当 generation 仍为当前值时应用结果
```

同步文件系统调用不会因为 Swift actor 自动变成后台工作，因此枚举和持久化必须继续使用既有显式执行边界。底层调用无法中途取消时，取消保证的是旧结果不进入 UI，而不是虚构底层 IO 已停止。

`FolderObserver` 使用 FSEvents 的 `FileEvents`、`WatchRoot` 和 `UseCFTypes`。只观察当前 Tab 的活动目录，事件作为快照失效信号触发重新枚举，不尝试逐事件修改网格。root change、dropped 或 wrapped 等恢复事件会停止旧 stream，重新校验路径和文件身份，再建立新 stream。显式 reload 与 FSEvents 最终收敛共同保证文件操作后的 UI 更新。

## 6. 文件网格与文件操作

`FileGridViewController` 使用 `NSCollectionView` 和共享 `GridLayout` 呈现连续 row-major 网格。Finder 风格交互契约由 `PRODUCT_REQUIREMENTS.md` 定义，包括单击选择、Command/Shift 扩展、双击打开、Return 重命名、拖放和上下文菜单。

所有变更型文件操作遵守同一边界：

1. 冻结有序选择和目标快照。
2. 在任何 mutation 前验证全部来源、目标、卷身份、冲突和自包含关系。
3. 拒绝覆盖、重复目标名、同目录传输和目录进入自身或后代。
4. 在专用 IO 边界串行执行；需要协调时使用 `NSFileCoordinator`。
5. 明确报告部分完成数量，不吞掉中途失败。
6. 成功后显式 reload，并由 FSEvents 最终收敛。

文件操作不经过 shell。压缩只以参数数组调用固定系统工具；Finder Get Info 使用编译固定的 AppleScript handler 和 descriptor 参数，不把路径拼接进脚本文本。

## 7. Quick Look 所有权

Quick Look 通过 responder chain 集成共享 `QLPreviewPanel`：

```text
FileCollectionView
  → PortalWindow
  → QuickLookIntegration
  → 原有 nextResponder / NSApplication
```

`QuickLookIntegration` 持有当前有序 URL 快照，只在选择非空时接受控制。它先请求共享面板显示，再让系统通过 responder chain 刷新 controller；不会直接调用 `beginPreviewPanelControl`，也不会抢占其他 responder 已拥有的可见面板。

Tab 切换、选择失效或窗口关闭时，只清理仍由当前 integration 拥有的 data source、delegate 和 responder 链接。真实预览渲染、焦点切换和多项目导航仍需在支持的 macOS 版本上人工验证。

## 8. Portal 表面

Portal 根视图使用普通 layer-backed 静态 alpha 合成表面。文件网格、顶部控制区、底部路径栏和分割线是同级内容；Portal 整体不使用动态 backdrop。

这个边界源于真实 Space 切换证据：desktop-level 窗口配合 `.canJoinAllSpaces` 时，整块 `NSGlassEffectView` 或 behind-window `NSVisualEffectView` 会暂时变灰。移除跨 Space 行为会破坏产品契约，切换后再移动窗口会产生明显延迟，因此生产实现选择静态表面。Reduce Transparency 使用不透明可访问表面，不修改已保存偏好。

## 9. 持久化与兼容性

内部 Portal 状态位于：

```text
~/Library/Application Support/Alcove/portals.json
```

`PortalStore` 使用版本化 Codable DTO 和同目录临时文件加原子 replace/move。当前 schema 为 v12；v1–v11 通过各自 DTO 解码、验证和迁移，不能把旧 JSON 直接宽泛解码为当前模型。迁移前保留单份原版本备份；发现已有不同备份时失败并保留证据，不覆盖。

布局导入导出是独立的 `com.alcove.layout-backup` v1 公共格式，不暴露内部 v12 envelope。它包含语义化全局外观和可移植 Portal 状态，不包含 launch-at-login：

- 导入严格验证完整文档，只支持替换，不执行 merge。
- 先基于当前主显示器、容量和间距预演完整布局。
- `PortalStore.save` 单次成功后才关闭旧窗口并替换 runtime。
- 解码、预演或保存失败不改变当前布局。

修改内部 schema、迁移策略或公开备份格式前，必须说明旧数据和未来版本行为并等待确认，同时增加兼容性测试。

## 10. 权限、网络与更新

Alcove 是非沙盒应用，不使用安全作用域书签、App Group 或特权 Helper。`NSOpenPanel` 是目录选择 UI，不是持久访问令牌；普通 POSIX 权限和 TCC 仍然适用。

- 核心 Portal 交互不需要 Accessibility 或 Full Disk Access。
- Desktop、Documents、Downloads 等位置可能触发 TCC；拒绝或 IO 失败必须显示可理解的错误。
- 应用不包含遥测或分析。
- Sparkle 会访问签名 appcast 检查更新，因此“完全无网络访问”不是当前事实。
- Finder Get Info 由用户动作触发 Apple Events，首次使用可能出现 Automation 权限请求。

## 11. 测试边界

自动测试分为两层：

- `Packages/AlcoveCore/Tests/`：领域不变量、选择状态、容量和纯布局几何。
- `Tests/AlcoveTests/`：AppKit 控制器、持久化迁移、文件操作、观察、Quick Look 协调、窗口配置和应用编排。

CI 还通过静态模式检查拒绝不安全 Swift 构造，并限制 UI 目录直接调用文件 mutation API。具体命令和按改动选择验证的规则见 `development.md`。

以下风险不能由 XCTest 单独关闭：

- WindowServer 层级、Show Desktop、Spaces、Stage Manager、全屏、锁屏和睡眠唤醒。
- 显示器 UUID 跨真实断开/重连的稳定性，以及不同硬件和缩放组合下的布局。
- `QLPreviewPanel` 的真实渲染、焦点和多项目交互。
- FSEvents、TCC、VoiceOver、Reduce Transparency 和 Increase Contrast 的系统行为。
- Apple Development 签名、Gatekeeper、quarantine、DMG 安装、Sparkle 更新和证书到期。

人工验证失败时必须修改实现或明确调整产品范围；不得把未测试的 fallback 描述成已支持。

## 12. 关键技术决策

| 决策 | 原因 |
|---|---|
| AppKit 生命周期和 `NSCollectionView` | 需要直接控制 `NSWindow` 层级、responder chain 和 Finder 风格多选网格 |
| 静态 Portal 表面 | 动态 backdrop 在跨 Space 的 desktop-level 窗口中不稳定 |
| FSEvents 快照失效 | 能表达 root change 和 dropped/wrapped 恢复；不需要双观察器或逐事件 patch |
| 非沙盒、无 Helper | 用户选择本地目录后的普通文件访问不需要提权或跨进程边界 |
| 版本化 JSON | Portal 数据规模小且写入频率低；原子文件和显式迁移比数据库更直接 |
| 独立公开备份格式 | 避免把机器相关内部 schema 暴露为长期公共契约 |

决策的外部依据、参考实现和已知证据等级见 `RESEARCH.md`。
