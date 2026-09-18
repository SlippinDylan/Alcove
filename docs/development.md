# Alcove 开发指南

本文是 Alcove 本地开发、验证、CI、发布和安全清理流程的权威入口。产品行为见 `PRODUCT_REQUIREMENTS.md`，组件和系统边界见 `ARCHITECTURE.md`。

## 1. 环境与工程

- 支持平台：macOS 26 及以上，仅支持 Apple Silicon (`arm64`)。
- 语言与 UI：Swift 6、AppKit 和少量 SwiftUI。
- 工程入口：`Alcove.xcodeproj` 的共享 `Alcove` scheme，包含应用和 `AlcoveTests`。
- 纯领域模块：`Packages/AlcoveCore`，可独立运行 Swift Package tests。
- 更新框架：Sparkle 2；版本由 Xcode 工程锁定，具体解析版本见 `Package.resolved`。
- CI 使用 `macos-26` runner 并选择 Xcode 26.6。本机其他 Xcode 版本通过不代表 CI 环境已通过。
- `.github/scripts/` 仅使用 Node.js 内置模块，不需要 npm 或 pnpm 安装依赖。

本地运行时在 Xcode 中打开工程并构建 `Alcove` scheme。常规自动验证不要主动启动应用；桌面层窗口和视觉结果由用户运行后验收。

## 2. 最小验证命令

### 2.1 自动化脚本

```bash
bash -n Scripts/create-dmg.sh
Scripts/create-dmg.sh --help >/dev/null
node .github/scripts/release-manifest.mjs validate
node --test .github/scripts/*.test.mjs
```

这些命令覆盖 DMG 脚本基本契约、发布清单解析、发布顺序、通知和分发元数据。它们不编译 Swift，也不能证明应用行为。

### 2.2 AlcoveCore

```bash
swift test --package-path Packages/AlcoveCore
```

领域模型、选择状态、布局几何和主显示器投影等纯逻辑变更先运行此命令。

### 2.3 宿主应用测试

```bash
xcodebuild test \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData-Tests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

该命令覆盖 AppKit 控制器、持久化、文件操作、Quick Look 协调和 Portal 集成测试。它会写入 `build/DerivedData-Tests/`。

### 2.4 无签名 Release 构建

```bash
xcodebuild build \
  -project Alcove.xcodeproj \
  -scheme Alcove \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData-Release \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

这是与 CI 一致的编译路径。产物位于 `build/DerivedData-Release/Build/Products/Release/Alcove.app`；无签名构建不能代替发布签名或 Gatekeeper 验证。

## 3. 按改动选择验证

| 改动范围 | 最小验证 |
|---|---|
| 仅文档或 `AGENTS.md` | 链接和引用搜索、`git diff --check`、检查改动列表 |
| `.github/scripts/`、发布清单或通知 | 发布清单校验、全部 Node tests |
| `Scripts/create-dmg.sh` | `bash -n`、`--help`，需要真实制品时再执行 DMG 创建和挂载检查 |
| `Packages/AlcoveCore` | 相关 package tests；公共领域行为变化时运行全部 package tests |
| AppKit、SwiftUI、持久化、文件系统或工程配置 | 相关 hosted tests 和一次应用构建；跨模块或高风险变更运行完整 hosted tests |
| Portal 窗口、Quick Look、多显示器、Spaces、Stage Manager、辅助功能 | 自动测试加人工系统验证；未执行的矩阵必须列为剩余风险 |
| 签名、Sparkle、DMG、发布或 Homebrew | 自动化测试、Release 构建、制品契约检查及真实安装/更新验证 |

UI 修改不主动启动应用或截图。用户明确要求视觉验证或提供截图后，再检查实际窗口和外观。

## 4. CI 契约

`.github/workflows/ci.yml` 是持续集成行为的唯一事实来源。

每次目标为 `main` 的 pull request、`main` push 和手动触发都会先运行 Ubuntu 轻量检查：

- 校验 `Scripts/create-dmg.sh` 语法和帮助入口。
- 校验 `Config/Release/manifest.json`。
- 运行全部 Node tests。

当变更不只涉及 `README.md`、`LICENSE`、根 `AGENTS.md` 或 `docs/`，或发布清单启用发布时，CI 还会运行 macOS job：

- 拒绝 `as!`、`try!`、`@unchecked Sendable` 和 `nonisolated(unsafe)`。
- 限制文件变更 API 只能出现在专用 IO 边界。
- 运行 AlcoveCore tests 和 hosted app tests。
- 构建无签名 arm64 Release 应用。
- 验证最低系统版本、菜单栏应用属性、Sparkle 配置、框架嵌入和动态库边界。

CI 当前只自动覆盖 macOS 26。macOS 27、真实多显示器、WindowServer 行为、辅助功能和最终用户安装路径没有自动覆盖时，必须明确标记为未验证风险。

## 5. 发布流程

### 5.1 发布请求

`Config/Release/manifest.json` 是发布请求入口，必须只包含 `version` 和 `release`：

```json
{
  "version": "x.y.z[-alpha.n|-beta.n]",
  "release": false
}
```

发布前必须满足：

1. `CHANGELOG.md` 存在唯一且非空的 `## [完整版本] - YYYY-MM-DD` 段落。
2. 请求版本高于已有的合法 GitHub Release 版本。
3. 仓库为 public。
4. 计划发布的提交已进入 `main`，并通过该提交触发的 CI。
5. 用户明确要求发布后，才将 `release` 改为 `true`；不要把本地构建成功当作发布授权。

发布工作流读取 manifest 的完整版本，使用其基础语义版本作为 `MARKETING_VERSION`，以 GitHub run number 作为 build number，并按 stable、alpha 或 beta 选择 Sparkle channel。

### 5.2 签名和制品

Release 使用仓库 Secrets 中的 Apple Development P12 和临时 keychain，按 Sparkle 要求由内到外重签嵌入组件，再验证应用和 DMG。失败时必须终止，不得回退到 ad-hoc 或未签名发布。

发布 DMG 必须：

- 仅包含 `Alcove.app` 和指向 `/Applications` 的符号链接。
- 包含单一 arm64 可执行文件，最低系统版本为 macOS 26.0。
- 保留经过验证的 Apple Development 签名和 Sparkle framework。
- 以 `Alcove.<完整版本>.dmg` 命名，并作为该 draft/release 的唯一资源。

这是未公证的 Apple Development 分发。quarantine、右键打开、`xattr`、证书或个人 Team profile 到期、macOS 26/27 安装与更新行为仍属于人工发布验证范围；未执行时不得描述为已验证兼容。

### 5.3 分发元数据

Release 发布后，独立且可重跑的 metadata workflow 会验证已发布制品，生成签名 appcast，并更新 `SlippinDylan/homebrew-tap`：

- stable → `alcove.rb`
- alpha → `alcove@alpha.rb`
- beta → `alcove@beta.rb`

该流程需要 Sparkle 私钥和 Homebrew tap token。不得读取、输出或复制 Secret 值；只记录缺失的 Secret 名称或配置位置。

## 6. 人工验证边界

以下行为由 macOS、WindowServer、硬件拓扑、辅助功能或签名环境共同决定，普通单元测试无法证明：

- desktop-level 窗口在 Show Desktop、Spaces、Stage Manager、全屏、锁屏和睡眠唤醒中的层级与恢复。
- 菜单栏主显示器切换、断开重连、分辨率/缩放变化及极端布局溢出。
- `QLPreviewPanel` 的真实内容渲染、焦点接管和多项目导航。
- Reduce Transparency、Increase Contrast、VoiceOver 和不同外观下的可读性。
- TCC 保护目录、FSEvents 系统事件、外部卷拒绝和真实文件传输。
- Apple Development 签名、Gatekeeper、quarantine、DMG 安装、Sparkle 更新和证书到期。

人工检查失败时，修改实现或明确收缩产品范围；不要把未经验证的 fallback 写成已支持行为。

## 7. 开发产物与安全清理

- `swift test` 生成 `Packages/AlcoveCore/.build/`。
- CI 风格的测试和构建生成 `build/DerivedData-Tests/`、`build/DerivedData-Release/`。
- 常见可再生产物还包括 `.build/`、`.swiftpm/`、`DerivedData/`、`*.app`、`*.dmg` 和 `*.xcarchive`；这些路径已由 `.gitignore` 排除。
- `Scripts/create-dmg.sh` 使用临时 staging 目录并自动清理，但会以 `hdiutil -ov` 覆盖调用者给出的 DMG 路径。只使用已经确认可覆盖的专用输出文件。
- 只有用户明确要求清理时才删除可再生产物；删除前解析准确路径并确认归属。
- 不删除源码、Git 数据、工程配置、签名材料、用户布局、日志或用途不明的文件。
- 清理仓库外的 `/tmp`、`/private/tmp`、`/private/var/folders` 或 Xcode DerivedData 需要用户明确授权，并且目标必须可靠归属于 Alcove 或本次开发流程。

## 8. 文档维护

- 用户可见能力、安装步骤、系统要求或数据位置变化时，同步更新 README 及所有语言版本。
- 产品范围和交互变化更新 `PRODUCT_REQUIREMENTS.md`；架构、持久化或系统边界变化更新 `ARCHITECTURE.md`；外部证据变化更新 `RESEARCH.md`。
- 开发命令、CI、发布或清理流程变化更新本文。
- `HANDOFF.md` 和 `DELIVERY_PLAN.md` 是历史导航，不记录当前状态。
- 不在文档中记录测试总数、某次本地 HEAD、未提交文件、临时下一步或单次构建结果。
