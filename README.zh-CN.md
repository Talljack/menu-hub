# Menu Hub for macOS

[English](README.md) | 简体中文

Menu Hub 是一个原生 macOS 菜单栏管理工具。它通过始终可见的四瓣 Hub 图标打开紧凑面板，让你搜索、收藏、分组并触发支持的菜单栏项目。

工程使用 Swift 6、SwiftUI + AppKit，最低支持 macOS 14；不使用私有 API、Electron、代码注入、录屏权限、联网服务、分析 SDK 或云存储。

> Menu Hub 当前为 MVP，尚不是经过 Apple 公证的公开发行版。准确验证状态和已知限制见 [MVP 对照验收](outputs/MVP-Comparison-Audit.md)。

## 使用方式

- 点击菜单栏中的四瓣 Hub 图标，打开或关闭主面板。
- 按 `⌥M` 可从任意 App 切换面板；可在“设置 > 快捷键”中修改。
- 输入文字搜索；`↑` / `↓` 选择，`Return` 执行默认动作，`⌘Return` 打开宿主 App，`⌘K` 打开动作菜单。
- `⌘1` 到 `⌘9` 触发收藏，`⌘F` 聚焦搜索，`Esc` 清空搜索或关闭面板。
- 按住 Option 点击 Hub 图标可收起或展开管理区域；右键可重新扫描、打开设置、恢复菜单栏或退出。
- 面板支持收藏、最近使用、常用、自定义分组和全部项目。每一项都优先显示宿主 App 名称，避免仅凭相同图标难以区分。

可触发项目优先执行 `AXPress`；不支持时可降级为打开已知宿主 App，无法处理的项目会禁用并显示原因。

## Accessibility 授权

首次运行会先解释用途，再显示 macOS 权限提示。你也可以跳过授权，继续使用“仅打开 App”的降级模式。

授权步骤：

1. 打开首次设置，或进入“设置 > 权限与隐私”。
2. 点击“打开系统设置”。
3. 在“隐私与安全性 > 辅助功能”中开启 Menu Hub。
4. 回到 Menu Hub；应用重新激活时会自动复查权限。

如果系统设置已开启但应用仍报告无权限，可选择“修复授权”。确认后，Menu Hub 只重置自身 `com.local.MenuHub` 的 Accessibility 记录并重新打开系统设置，不会重置其他 App。

## 管理与设置

项目管理支持搜索、别名、收藏、多分组、排序、忽略/恢复、能力重测、最近发现时间和本地错误信息；删除分组支持撤销。

设置包含通用、外观、项目与分组、快捷键、权限与隐私、诊断六个区域，支持登录时启动、恢复上次收起状态、面板行为、跟随系统/浅色/深色、列表/网格、语言、快捷键录制、本地数据控制、脱敏诊断导出和菜单栏恢复。

界面支持“系统默认、English、简体中文”。切换语言后请重新打开窗口；如仍有旧文字，可重启 Menu Hub。

## 本地构建与测试

安装 XcodeGen 和 Swift 6 工具链后运行：

```sh
xcodegen generate
swift test
xcodebuild test -project MenuHub.xcodeproj -scheme MenuHub -destination 'platform=macOS'
xcodebuild -project MenuHub.xcodeproj -scheme MenuHub -configuration Release \
  -derivedDataPath work/DerivedData clean build
open work/DerivedData/Build/Products/Release/MenuHub.app
```

Menu Hub 是 `LSUIElement` 菜单栏 App，不显示 Dock 图标或普通主窗口。启动后请在菜单栏寻找 Hub 图标，或按 `⌥M`。

## 版本与 CI 发布

根目录 `VERSION` 是版本号唯一来源，必须与 `project.yml` 中的 `MARKETING_VERSION` 一致。本地生成经过测试的 Universal（`arm64 + x86_64`）构建：

```sh
./scripts/build-release.sh
```

每次推送或合并到 `main` 都会运行 [.github/workflows/release.yml](.github/workflows/release.yml)，执行测试、Universal 构建、打包并上传 CI 构件。

推送 `v*` 标签后，只有 Developer ID 签名、Apple 公证和 stapling 全部成功，才会创建正式 GitHub Release。标签发布需要以下仓库 Secrets：

- `APPLE_CERTIFICATE_P12_BASE64`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Secrets 不完整时会安全失败，不会发布未签名或未公证的正式版本。

Phase 0 探针仍可用于验证公开 API 的真实兼容性：

```sh
swift run FeasibilityProbe --output FeasibilityReport.md
swift run FeasibilityProbe --press-index 0 --output FeasibilityReport.md
```

## 隐私与本地数据

目录、收藏、别名、分组、偏好和使用记录仅保存在本机：

```text
~/Library/Application Support/Menu Hub/
```

Catalog 使用带 schema 版本的 Codable JSON、原子替换和本地备份恢复。诊断只在用户选择保存位置后导出，并删除或哈希主目录、用户名、搜索文字和稳定项目标识。

## 公开 API 限制

macOS 没有公开 API 可以保证枚举、移动、隐藏并代理所有第三方菜单栏项目。Menu Hub 使用透明可变宽度 `NSStatusItem` 管理布局空间，并通过 Accessibility API 发现和触发支持的项目。

- 时钟、控制中心等系统管理项目不属于隐藏承诺。
- 缺少稳定 Accessibility 元数据或 `AXPress` 的项目可能只能打开宿主 App，或保持不可用。
- 前台 App 菜单过长、刘海屏和多显示器变化仍可能导致 macOS 裁切项目；布局不确定时 Menu Hub 会恢复到安全展开状态。
- 最终兼容性必须在目标 macOS、显示器布局和第三方 App 版本上实机验证。

## 项目文档

- [本地验证报告](outputs/LocalValidationReport.md)
- [MVP 对照验收](outputs/MVP-Comparison-Audit.md)
- [发布清单](docs/ReleaseChecklist.md)
- [Phase 0 手工检查表](docs/Phase0ManualTestChecklist.md)
- [Phase 0 可行性报告](FeasibilityReport.md)
