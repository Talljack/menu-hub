# Menu Hub for macOS

Menu Hub 是一个原生 macOS 菜单栏管理工具。它用一个始终可见的四瓣 Hub 图标打开紧凑面板，让你搜索、收藏、分组并触发可访问的菜单栏项目。

当前工程使用 Swift 6、SwiftUI + AppKit，最低支持 macOS 14。它不使用私有 API、Electron、代码注入、Screen Recording、联网服务或分析 SDK。

> 当前代码已进入 MVP 收尾阶段，但还不是可公开分发的成品。自动化 UI 测试、完整硬件兼容性矩阵、公证和最终安装验收仍需完成。准确状态见 [MVP 对照验收](outputs/MVP-Comparison-Audit.md)。

## 使用方式

- 点击菜单栏中的四瓣方形 Hub 图标，打开或关闭主面板。
- 按 `⌥M` 可从任意 App 打开或关闭面板。可在“设置 > 快捷键”中修改；若冲突，原快捷键会保留并显示错误。
- 输入文字搜索项目；`↑` / `↓` 选择，`Return` 执行默认动作，`⌘Return` 打开宿主 App，`⌘K` 打开动作菜单。
- `⌘1` 到 `⌘9` 触发对应收藏；`⌘F` 聚焦搜索；按两次 `Esc` 先清空搜索、再关闭面板。
- `Option` 单击 Hub 图标收起或展开隐藏区。右键图标可重新扫描、打开设置、恢复菜单栏或退出。
- 面板默认显示收藏、最近使用、常用、用户分组和全部项目；每一行始终显示宿主 App 名称。可触发项目优先执行 `AXPress`，不支持时降级为打开宿主 App，无法处理时显示原因。

## Accessibility 授权

首次运行会说明能力边界。你可以跳过权限并使用“仅打开 App”的降级模式。

授权路径：

1. 打开 Menu Hub 的首次设置，或进入“设置 > 权限与隐私”。
2. 点击“打开系统设置”。
3. 在“隐私与安全性 > 辅助功能”中开启 Menu Hub。
4. 回到 Menu Hub。应用激活时会重新检测权限，不会循环弹窗。

如果系统设置显示已开启，但 Menu Hub 仍报告未授权，可在权限页选择“修复授权”。该操作会先解释风险并要求确认，只重置 `com.local.MenuHub` 的 Accessibility 记录，然后重新打开系统设置。它不会重置其他 App，也不会自动执行。

## 管理与设置

“管理项目”窗口用于搜索全部项目、编辑别名、收藏、加入多个分组、调整内部顺序、忽略项目、重新测试能力，并查看最近发现时间和错误。删除分组支持撤销。

设置窗口包含六个区域：通用、外观、项目与分组、快捷键、权限与隐私、诊断。这里可设置登录时启动、上次收起状态、面板行为、浅色/深色/跟随系统、列表/网格、语言、快捷键、本地数据导出/清除、诊断导出与恢复菜单栏。

界面提供“系统默认、简体中文、English”三种语言选项。部分窗口或菜单文字切换后可能需要重新打开，应用会显示相应提示。

## 本地构建与测试

要求安装 XcodeGen 和 Swift 6 工具链：

```sh
xcodegen generate
swift test
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS'
xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Release \
  -derivedDataPath work/DerivedData clean build
open work/DerivedData/Build/Products/Release/MenuHub.app
```

Menu Hub 是 `LSUIElement` 菜单栏 App，启动后不会显示 Dock 图标或普通主窗口。请在菜单栏寻找四瓣 Hub 图标，或按 `⌥M`。

## 版本与 CI 发布

版本号由根目录的 `VERSION` 统一管理，并必须与 `project.yml` 的 `MARKETING_VERSION` 一致。生成经过测试的 Universal (`arm64 + x86_64`) 发布包：

```sh
./scripts/build-release.sh
```

本地创建发布标签：

```sh
git tag -a v0.1.0 -m "Menu Hub 0.1.0"
git push origin v0.1.0
```

推送 `v*` 标签会触发 `.github/workflows/release.yml`，运行测试、构建 Universal App、生成 ZIP 与 SHA-256，并在 Developer ID 签名、Apple 公证与 stapling 全部成功后创建 GitHub Release。正式标签要求仓库配置以下 Secrets：

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

未配置完整 Secrets 时，标签构建会 fail closed，不会创建未签名或未公证的正式 Release；仍可用手动触发进行内部构建验证。

Phase 0 探针仍保留用于验证公开 API 的真实兼容性：

```sh
swift run FeasibilityProbe --output FeasibilityReport.md
swift run FeasibilityProbe --press-index 0 --output FeasibilityReport.md
```

## 隐私与本地数据

目录、收藏、别名、分组、偏好和使用记录仅保存在：

```text
~/Library/Application Support/Menu Hub/
```

Catalog 使用带 schema 版本的 Codable JSON、原子替换和本地备份恢复。设置页可显式导出或清除数据。诊断只在用户选择保存位置后导出，并对主目录、用户名、搜索文字和稳定项目标识做删除或哈希处理。

## 公开 API 限制

macOS 没有公开 API 可以保证枚举、移动、隐藏并代理所有第三方菜单栏项目。Menu Hub 使用透明可变宽度 `NSStatusItem` 改变布局空间，并通过 Accessibility API 尝试发现和触发项目。因此：

- 系统强制保留的时钟、控制中心等项目不属于隐藏承诺。
- 未提供稳定 Accessibility 名称或 `AXPress` 的项目只能打开宿主 App，或显示不可用。
- 前台 App 菜单过长、刘海屏或多显示器布局变化时，macOS 仍可能裁掉项目；Menu Hub 会优先恢复为安全展开状态。
- 不承诺“支持所有图标”。最终兼容性必须以对应 macOS、显示器和目标 App 的实机矩阵为准。

## 项目文档

- [本地验证报告](outputs/LocalValidationReport.md)
- [MVP 对照验收](outputs/MVP-Comparison-Audit.md)
- [发布清单](docs/ReleaseChecklist.md)
- [Phase 0 手工检查表](docs/Phase0ManualTestChecklist.md)
- [Phase 0 可行性报告](FeasibilityReport.md)
