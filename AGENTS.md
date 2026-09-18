# Alcove Agent 指南

本文件是仓库导航和工作契约，不是完整手册。只读取与当前任务相关的链接；详细知识维护在对应权威文档中，不在这里重复。

## 项目概述

Alcove 是面向 macOS 26 及以上版本、仅支持 Apple Silicon 的原生菜单栏应用。它使用 Swift 6、AppKit、少量 SwiftUI 和独立的 `AlcoveCore` Swift Package，在桌面图标之上、普通应用窗口之下展示可移动、可缩放的本地文件夹面板。

用户可见行为以 [README.md](README.md) 和 [产品需求](docs/PRODUCT_REQUIREMENTS.md) 为准，当前实现边界见 [架构文档](docs/ARCHITECTURE.md)，开发、验证和发布流程见 [开发指南](docs/development.md)。

## 开始工作

1. 检查 Git 状态，保留已有未提交改动，不清理或回退无关内容。
2. 阅读本文件以及任务涉及的权威文档，不把历史交接或早期计划当作当前状态。
3. 搜索现有类型、服务和测试，确认职责、数据流及系统边界后再修改。
4. 沿用现有设计和命名，将改动限制在需求范围；公共契约或业务语义存在实质歧义时先确认。

## 仓库地图

- `App/Application/`：应用生命周期、菜单栏、全局设置、Portal 编排和更新入口。
- `App/PortalWindowing/`、`App/PortalPresentation/`：桌面层窗口、面板内容、Tab、设置窗口和视觉边界。
- `App/FileGrid/`：`NSCollectionView` 文件网格、选择、打开、重命名、传输和文件操作。
- `App/FolderAccess/`：目录资格校验、后台枚举、加载协调和 FSEvents 观察。
- `App/QuickLookIntegration/`：`QLPreviewPanel` responder-chain 所有权。
- `App/DisplayPlacement/`：主显示器识别、布局投影和显示器变化处理。
- `App/Persistence/`：版本化 Portal JSON、旧版本迁移和公开布局备份格式。
- `Packages/AlcoveCore/`：不依赖 UI 的领域模型、选择和布局几何。
- `Tests/AlcoveTests/`、`Packages/AlcoveCore/Tests/`：宿主应用与纯领域测试。
- `.github/`、`Config/Release/`、`Scripts/`：CI、发布清单、分发元数据和 DMG 打包。

## 产品与架构硬边界

- Alcove 不是 Finder 替代品；文件浏览限制在用户映射的根目录及当前 Tab 的运行时历史。
- 新建和重新映射的文件夹必须由用户明确选择；恢复和布局导入也必须在写入状态前重新校验目录位于 Mac 内置、固定、本地存储，并拒绝可移除、可弹出和网络卷。
- `GridCapacity` 是 Portal 的持久尺寸意图；文件换行列数不得从存在像素误差的可见宽度重新推导。
- 所有 Portal 始终位于实时菜单栏主显示器。系统驱动的迁移不得覆盖用户保存的 placement。
- `Portal.tabs` 是 Tab 顺序的唯一状态源；每个 Portal 最多四个 Tab，空 Portal 是合法状态。
- Finder 风格交互保持单击选择、双击打开、Space 快速查看；视图层不得复制领域或文件操作规则。
- 文件变更必须先完整校验、绝不覆盖，并通过专用 IO 边界执行；不要在 UI 层新增任意 shell 或直接文件变更路径。
- Quick Look 由 responder chain 和共享 `QLPreviewPanel` 管理；不得抢占其他 responder 已拥有的面板。
- Portal 使用静态半透明表面。不要重新引入整面板 `NSGlassEffectView`、`NSVisualEffectView` 或 WindowServer backdrop。
- 内部 Portal 持久化 schema、公开布局备份格式和迁移策略属于兼容性边界；修改前说明影响并等待确认。

## 实现约定

- 在用户输入、文件系统、持久化、系统 API 和外部工具输出等边界校验；内部代码相信已由类型和契约建立的不变量。
- UI 与窗口控制器保持 `@MainActor`；阻塞文件 IO 使用现有后台执行边界，异步结果必须拒绝过期 generation。
- 不使用 `as!`、`try!`、`@unchecked Sendable`、`nonisolated(unsafe)`、空 `catch` 或 silent fallback 绕过问题。
- 错误在能恢复或向用户说明的层级显式处理；持久化失败、权限失败和部分文件操作失败不得伪装成成功。
- 代码注释使用英文，只解释原因、约束和非显而易见的系统行为。

## 常用命令

优先使用可用的 Xcode 项目工具执行 macOS 构建和测试；不可用时使用下列命令。完整参数和适用范围见 [开发指南](docs/development.md)。

```bash
bash -n Scripts/create-dmg.sh
Scripts/create-dmg.sh --help >/dev/null
node .github/scripts/release-manifest.mjs validate
node --test .github/scripts/*.test.mjs
swift test --package-path Packages/AlcoveCore
xcodebuild test \
  -project Alcove.xcodeproj -scheme Alcove \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData-Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
xcodebuild build \
  -project Alcove.xcodeproj -scheme Alcove -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData-Release \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

不要为常规验证启动应用、截图、浏览器、模拟器或 watch 进程。UI 和系统级行为由用户验收；只有用户明确要求或提供截图时才做视觉验证。

## 验证与完成标准

- 先运行覆盖改动的最小检查，再根据失败或风险扩大范围。
- `AlcoveCore` 领域变更运行 package tests；AppKit、持久化、窗口或集成变更运行相关 hosted tests 和一次应用构建。
- 自动化或发布变更运行 Shell 语法、发布清单校验和全部 Node 测试。
- Portal、Quick Look、Spaces、Stage Manager、多显示器、辅助功能、签名和 Gatekeeper 行为不能仅由 XCTest 证明；未人工执行时明确报告剩余风险。
- 完成前运行 `git diff --check`，检查改动文件和残留引用，确认没有密钥、调试输出、生成物或无关修改。
- 无法执行的必要验证说明原因，不以历史测试数量或旧交接记录代替本轮结果。

## 文档规则

- README 记录用户可见能力、安装、系统要求和下载入口；对应事实变化时同步维护所有语言版本。
- `PRODUCT_REQUIREMENTS.md` 记录产品范围和交互契约；`ARCHITECTURE.md` 记录当前组件、稳定不变量及风险；`RESEARCH.md` 记录外部证据；`development.md` 记录开发和发布流程。
- `HANDOFF.md` 与 `DELIVERY_PLAN.md` 只保留历史导航，不是当前状态或需求来源。
- 新增和维护的内部文档使用中文。源码可以清晰表达的成员列表、调用细节和测试数量不复制进文档。
- 同一事实只维护一个权威来源；重复出现的错误优先用类型、测试或 CI 固化，再补充必要说明。

## 发布与清理边界

- `Config/Release/manifest.json` 是发布请求入口。未经明确要求，不修改版本、启用发布、提交、推送、创建 Release 或更新 appcast/Homebrew Cask。
- 不在日志、测试夹具、文档或提交中写入证书、Token、Sparkle 私钥或其他真实凭据。
- 只有用户明确要求清理时，才删除可安全再生的构建产物；删除前确认目标路径和归属。
- 不删除源码、Git 数据、工程配置、签名材料、用户布局、日志或用途不明的文件；仓库外临时目录和 DerivedData 需要单独授权。

## 信息冲突

当前用户指令优先于仓库文档。`AGENTS.md` 规定工作方式，产品需求和架构文档规定稳定契约，源码、测试和 CI 说明当前实现。三者冲突且会影响行为或公共契约时，列出证据、影响和建议方案，等待确认，不自行选择方便的一方。
