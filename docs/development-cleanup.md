# Alcove 开发产物清理规则

本文是 Alcove 开发产物清理的唯一规则来源，定义清理请求的语义、允许审计的位置、项目归属证据、删除边界和结果报告要求。

只有用户明确要求清理时才执行。目标是让仓库回到接近“尚未构建”的状态：保留项目输入、用户数据、机器长期状态和 Agent 对话记录，移除能够可靠归属于 Alcove、由开发和验证过程产生且可以重新生成的全部输出。

## 请求语义

### 清理仓库内开发产物

仅审计当前 Alcove Git 工作树内部、本文件明确列出的可再生产物，不扩展到仓库外目录。

### 清理当前项目所有开发产物

“清理当前项目所有开发产物”“全面清理当前项目”或含义等价的明确请求，表示：

- 审计当前工作树及本文列出的仓库外位置；
- 覆盖本次和历史 Agent 会话执行编译、构建、测试、预览、签名、打包及验证留下的 Alcove 产物；
- 删除能够可靠归属的本地 App、DMG、dSYM、`.xcarchive` 和其他可再生交付物，无论它们是否已经签名或通过验证；
- 授权删除审计范围内满足本文全部删除条件的内容，无需对同一范围再次请求许可。

授权审计不等于删除所有命中项。无法证明项目归属、安全再生性或数据性质的内容必须保留并报告。

如果当前目录不是 Alcove 的单一 Git 工作树，或者请求可能同时指向其他 clone 或 worktree，必须先明确目标，不能把多个工作树视为同一个项目。

### 清理当前项目所有开发和验证残留

该请求包含前述全部范围，并进一步检查为了本地验证而安装或注册的 Alcove App、登录项和其他机器状态。

普通文件清理不得退出正在运行的 App、删除已安装 App、修改登录项、撤销权限或调用提权操作。只有用户明确要求恢复开发验证环境，且能够通过当前实现确认精确、安全的卸载流程时才处理；否则只报告检测到的状态。

## 当前项目定义

| 项目属性 | Alcove 定义 |
|---|---|
| Git 仓库 | 当前工作树根目录 |
| Xcode project | `Alcove.xcodeproj` |
| Scheme | `Alcove` |
| Targets | `Alcove`、`AlcoveTests` |
| Swift Package | `Packages/AlcoveCore` |
| App bundle identifier | `com.dylanwang.Alcove` |
| Test bundle identifier | `com.dylanwang.AlcoveTests` |
| DMG 临时前缀 | `alcove-dmg.` |
| 用户数据 | `~/Library/Application Support/Alcove/`、Alcove 的 UserDefaults、用户导入或导出的布局及用户映射的文件夹 |
| 项目专属可再生缓存 | `~/Library/Caches/com.dylanwang.Alcove/` 及 macOS 为同一完整 bundle identifier 建立的纯缓存 |

这些标识来自工程配置、源码和受版本控制的脚本。名称相似但标识或工程路径不匹配的内容不属于 Alcove。

## 仓库内审计范围

已知可再生产物包括：

```text
build/
DerivedData/
.build/
Packages/AlcoveCore/.build/
.swiftpm/
*.xcresult
*.dSYM
*.dSYM.zip
*.app
*.dmg
*.xcarchive
```

还应审计由当前任务明确指定在仓库内的测试结果、覆盖率输出、构建日志、Archive、DMG 输出、临时导出目录和打包 staging。

候选项必须位于当前工作树内，并且能由工程设置、构建命令或项目脚本证明为生成物。`.gitignore` 只能作为线索，不能单独证明文件可以删除；不得使用 `git clean` 代替逐项判断，未跟踪文件也不能自动视为垃圾文件。

## 仓库外审计范围

只有用户明确要求清理当前项目所有开发产物时，才审计本节范围。

### Xcode DerivedData

审计 `~/Library/Developer/Xcode/DerivedData/` 中工程名称和构建元数据均能确认属于当前 Alcove 工作树的目录。不能只根据 `Alcove-` 目录名前缀判断。应优先核对 DerivedData 元数据记录的 project/workspace 绝对路径，并在规范化路径后与当前工作树比较。属于其他 Alcove clone、worktree 或无法解析来源的目录必须保留。

### Xcode Archives

审计 `~/Library/Developer/Xcode/Archives/` 中能够通过归档元数据、bundle identifier、scheme 和工程信息确认属于当前工作树的 `.xcarchive`。符合条件的本地归档属于可再生开发输出，即使已经签名或用于发布验证，也在全面清理范围内。

### 系统临时目录

审计：

- `/tmp`
- `/private/tmp`
- 当前用户的 `$TMPDIR`，即解析后的 `/private/var/folders/.../T/`

`/tmp` 通常解析为 `/private/tmp`。统计和删除前必须规范化并去重，不重复计算或删除同一目标，也不得遍历其他用户的 `/private/var/folders`。

Alcove 的强归属证据包括：

- `Scripts/create-dmg.sh` 创建的 `alcove-dmg.*` 临时目录；
- 当前工作树的规范化绝对路径；
- `Alcove`、`AlcoveTests` 或 `AlcoveCore` target/module 的精确构建元数据；
- 完整 bundle identifier；
- 当前任务已知的构建、签名、DMG 挂载或验证输出路径。

测试和文件压缩会在系统临时目录中创建 UUID 命名的内容。除非能够通过本次任务记录、路径内容或其他强证据确认其属于 Alcove 且不包含用户文件，否则不得仅因名称、修改时间或位置而删除。

项目名的模糊子串、最近修改时间、临时目录位置或“看起来像缓存”都不能单独证明归属。

### 项目专属缓存

可以审计完整 bundle identifier 对应、且不承载用户数据的纯缓存。不得把以下内容当作缓存：

- `~/Library/Application Support/Alcove/` 下的 Portal 布局、迁移备份和其他持久数据；
- Alcove UserDefaults，其中包含应用设置；
- 用户导入或导出的布局备份；
- 用户映射的文件夹及其中的文件；
- 任何用户选择、导入、导出或由 Alcove 操作的原始文件。

### 历史 Agent 开发残留

文件系统通常不能证明某个文件由哪次 Codex、ChatGPT 或其他 Agent 对话创建。“历史 Agent 开发残留”只表示不把候选项限制在本次会话时间范围内；删除仍必须依赖路径、工程元数据、项目标识或脚本前缀等客观证据。

不得按 `Codex`、`ChatGPT`、`Agent`、`Alcove` 或时间范围进行宽泛匹配删除。

## Agent 对话和工作状态

Agent 对话记录不是开发产物。清理不得扫描、删除或修改：

- Codex、ChatGPT 或其他 Agent 的 conversation、thread 和 session 数据；
- `~/.codex/`、`~/.agents/` 以及 ChatGPT/Codex 的 Application Support 数据；
- Agent 配置、Skill、认证状态和工具配置；
- 仓库内 `.engramory-memory/` 及其他项目决策记录。

这些记录即使包含 Alcove 路径、构建命令或历史操作，也只能作为调查线索，不能成为清理目标。

## 可删除内容

满足项目归属和安全条件后，全面清理应删除：

- 仓库内外属于当前工作树的 DerivedData 和 SwiftPM `.build`；
- 测试结果、覆盖率输出、构建日志和预览产物；
- 本地生成的 Alcove `.app`、`.dSYM`、`.xcarchive`、DMG 和其他打包输出；
- 签名、导出和发布验证产生的可再生副本、响应文件、staging、挂载和临时目录；
- `alcove-dmg.*` 等项目脚本遗留的临时目录；
- 本文明确列出的项目专属可再生缓存；
- 能够证明来自开发运行、且不承载用户数据的其他 Alcove 临时文件。

删除符号链接时只处理链接本身，不跟随链接递归删除其目标。候选目录包含未知挂载点、路径逃逸、权限异常或所有权异常时，停止处理该目标并报告。

## 禁止删除内容

无论是否与 Alcove 有关，默认不得删除：

- 源码、测试源码、文档、Git 数据和任务开始前的工作区变更；
- `Alcove.xcodeproj/`、`Config/`、`Package.resolved`、plist、entitlements 和发布自动化；
- 证书、私钥、真实钥匙串、provisioning profile、Sparkle 私钥、Token、签名配置和发布凭据；
- `xcuserdata`、断点、个人 scheme 和编辑器状态；
- Application Support、UserDefaults、Portal 布局、迁移备份、用户映射目录和用户文件；
- Agent 对话、session、配置、Skill、认证状态、Memory 和项目决策记录；
- 已安装 App、登录项、系统权限和其他机器长期状态，除非用户明确要求恢复开发验证环境且存在精确卸载流程；
- Xcode ModuleCache、SDK 缓存、SwiftPM 下载/仓库缓存及其他跨项目共享缓存；
- 其他仓库、clone 或 worktree 的产物；
- 用途、所有权、项目归属或可再生性无法确认的文件。

普通开发产物清理不得停止 Alcove、Xcode 或其他进程。相关进程仍在运行时，应说明产物可能立即重新生成。

## 输出集中规则

本地自动验证应继续把 DerivedData 放在仓库内 `build/`。新增测试、Archive 或打包流程时，优先使用以下布局：

```text
build/
├── DerivedData-Tests/
├── DerivedData-Debug/
├── DerivedData-Release/
├── TestResults/
├── Archives/
├── Products/
├── Packages/
└── Temp/
```

在命令支持的前提下显式设置 `-derivedDataPath`、`-resultBundlePath` 和 `-archivePath`。DMG 脚本的输出路径由调用者指定，调用前必须确认允许覆盖；临时目录继续使用项目专属 `alcove-dmg.` 前缀并由 `trap` 清理。

## 执行流程

1. 确认当前 Git 根目录、实际工作树和本文件中的项目定义。
2. 检查工作树状态。已有修改和未跟踪文件属于用户内容，除非与本文明确列出的生成物完全匹配，否则不得处理。
3. 根据请求语义确定仅审计仓库内、同时审计仓库外，还是进一步恢复开发安装和验证状态。
4. 收集候选项，解析绝对路径和符号链接，去除重复、嵌套和互相覆盖的目标。
5. 为每个候选项记录项目归属证据、安全分类以及保留或删除理由。
6. 使用一致口径统计删除前大小；父目录已计入时，不再把其子目录重复加入总计。
7. 只删除同时满足项目归属、可再生性和非用户数据要求的精确目标。
8. 使用同一口径重新统计，并计算每项实际释放空间。
9. 再次扫描相同范围，确认是否仍有符合条件的残留；保留项必须记录原因。
10. 检查 Git 状态，确认没有删除或修改受版本控制文件，也没有影响任务开始前的工作区变更。
11. 确认 Agent 对话、配置、Skill、认证状态和 Memory 未被扫描或修改。

不得为了扩大范围使用 `sudo`，不得修改权限或所有权，也不得把权限错误当作绕过安全判断的理由。

## 结果报告

清理完成后按以下字段报告：

| 项目 | 路径 | 归属证据 | 清理前 | 清理后 | 实际释放 | 结果 |
|---|---|---|---:|---:|---:|---|
| `<artifact>` | `<absolute-path>` | `<evidence>` | `<size>` | `<size>` | `<size>` | `<deleted/retained/failed>` |

随后汇总删除的主要目录、每项和总实际释放空间、保留项及原因、无法处理的范围和剩余风险，以及仍在运行并可能重新生成产物的相关进程。

总数只能对规范化、去重后的非重叠目标求和。APFS clone、稀疏文件或文件系统记账可能使目录逻辑大小与实际磁盘回收量不同，必须说明统计口径。

完成结论应表述为：所有能够可靠归属于当前 Alcove 工作树、可安全重新生成的开发产物均已清除；共享缓存、Agent 对话和状态、用户数据、机器长期状态以及无法可靠归属的系统记录未处理。不得声称系统中不存在任何 Alcove 痕迹。
