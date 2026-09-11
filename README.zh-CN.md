# Menu Hub for macOS

[English](README.md) · 简体中文 · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md)

[下载最新版本](https://github.com/Talljack/menu-hub/releases/latest) · 需要 macOS 14 或更高版本 · 支持 Apple 芯片与 Intel

Menu Hub 是一个原生 macOS 菜单栏管理工具。点击四瓣图标，即可搜索、识别、整理和触发当前运行 App 的菜单栏项目。

<p align="center">
  <img src="docs/images/menu-hub-panel.png" alt="Menu Hub 在紧凑的 macOS 面板中显示可搜索的菜单栏 App" width="520">
</p>

Menu Hub 使用 Swift 6、SwiftUI 和 AppKit 开发，只使用 macOS 公开 API。不使用 Electron、代码注入、录屏权限、分析 SDK、云服务或账号系统。

## 安装

1. 打开 [GitHub 最新版本页面](https://github.com/Talljack/menu-hub/releases/latest)。
2. 根据 Mac 芯片下载对应 DMG：

   | Mac | 下载文件 |
   | --- | --- |
   | Apple M1、M2、M3、M4 或更新芯片 | `Menu-Hub-*-macos-arm64.dmg` |
   | Intel 处理器 | `Menu-Hub-*-macos-x86_64.dmg` |

   不确定芯片类型时，打开“苹果菜单 > 关于本机”，查看“芯片”或“处理器”。
3. 打开 DMG，将 **Menu Hub** 拖入“应用程序”。
4. 推出 DMG，然后从“应用程序”或 Spotlight 启动 Menu Hub。
5. 在菜单栏中寻找四瓣 Menu Hub 图标。Menu Hub 是菜单栏 App，因此不会显示 Dock 图标，也不会自动打开普通主窗口。

同一个 Release 页面还提供 ZIP 和 SHA-256 校验文件。正式版本均使用 Developer ID 签名、经过 Apple 公证，并可通过 Gatekeeper 检查。

升级时先退出正在运行的 Menu Hub，再将新版本拖入“应用程序”并替换旧版本。

## 授予辅助功能权限

辅助功能权限用于发现支持的菜单栏项目，并执行这些项目原本的点击动作。不授权时，Menu Hub 仍可使用，但会降级为功能有限的 App 启动器模式。Menu Hub 不需要录屏权限。

1. 启动 Menu Hub 并按照首次运行说明操作，或打开 **设置 > 权限与隐私**。
2. 点击 **打开系统设置**。
3. 进入 **隐私与安全性 > 辅助功能**，开启 **Menu Hub**。
4. 如果列表中没有 Menu Hub，点击 `+`，选择 `/Applications/Menu Hub.app`。
5. 返回 Menu Hub。App 再次激活时会自动复查权限并重新扫描。

如果系统开关已经打开，但 Menu Hub 仍提示没有权限：

1. 打开 **Menu Hub > 设置 > 权限与隐私**。
2. 选择 **修复授权** 并确认。
3. 在系统设置中重新开启 Menu Hub，然后重新打开面板或点击 **重新扫描**。

“修复授权”只会重置 Menu Hub 自己的 `com.local.MenuHub` 辅助功能记录，不会修改其他 App 的权限。

## 使用 Menu Hub

- 点击菜单栏中的四瓣图标，打开或关闭面板。
- 在任意 App 中按 `⌥M` 切换面板。如果快捷键冲突，可在 **设置 > 快捷键** 中修改。
- 输入 App 名称或项目名称进行搜索。每个结果都会优先显示宿主 App 名称，避免仅凭相似图标难以区分。
- 点击项目可执行原有菜单栏动作。如果无法直接触发，Menu Hub 可以改为打开已识别的宿主 App。
- 按住 Option 点击 Menu Hub 图标，可收起或展开受管理的菜单栏区域。
- 右键点击图标，可重新扫描、打开设置、恢复菜单栏或退出。
- 收藏、最近使用、常用、自定义分组、别名、排序和忽略项目，可在 **设置 > 项目与分组** 中管理。

### 未读消息提醒

开启辅助功能权限和自动扫描后，Menu Hub 会在菜单栏图标旁显示单色未读总数胶囊。面板打开时每秒刷新已知数字，面板关闭时每 5 秒刷新一次。

自动模式默认支持飞书/Lark、微信、企业微信、QQ、钉钉、Slack、Microsoft Teams、Telegram、WhatsApp、Discord、Signal、LINE、KakaoTalk、Viber、Zoom Workplace、Mattermost、Zulip 和 Element。只有 macOS 公开辅助功能标题中的准确纯数字才会计入；只有红点、没有数字时按 0 处理。可在 **设置 > 项目与分组** 中选择项目，然后把 **未读提醒** 改为“自动 / 始终计入 / 从不计入”。

该功能只读取菜单栏项目公开的辅助功能标题，不读取消息内容、通知正文、账号或网络流量。

### 键盘操作

| 快捷键 | 功能 |
| --- | --- |
| `⌥M` | 全局打开或关闭 Menu Hub |
| `↑` / `↓` | 移动选择 |
| `Return` | 执行所选项目的默认动作 |
| `⌘Return` | 打开所选项目的宿主 App |
| `⌘K` | 打开所选项目的动作菜单 |
| `⌘1` 到 `⌘9` | 触发收藏项目 |
| `⌘F` | 聚焦搜索框 |
| `Esc` | 先清空搜索，再关闭面板 |

## 语言

Menu Hub 支持 10 种语言：English、简体中文、繁體中文、日本語、한국어、Español、Français、Deutsch、Português (Brasil) 和 Русский。在 **设置 > 通用 > 语言** 中可跟随 macOS 或明确选择语言。“跟随系统”会匹配已支持的地区变体（例如 `zh-TW` 使用繁體中文）；系统语言尚未支持时会回退到 English。切换后请重新打开窗口；如果已有窗口仍显示旧文字，请重启 Menu Hub。

## 隐私与本地数据

目录、收藏、别名、分组、偏好和使用记录仅保存在本机：

```text
~/Library/Application Support/Menu Hub/
```

Menu Hub 不会上传分析数据或用户数据。诊断信息只会在你主动选择保存位置后导出，并会删除或哈希主目录、用户名、搜索文字和稳定项目标识。

## 公开 API 限制

macOS 没有公开 API 可以保证发现、移动、隐藏和代理触发所有第三方菜单栏项目。Menu Hub 使用透明可变宽度 `NSStatusItem` 管理布局空间，并通过辅助功能 API 发现和触发项目。

- 时钟、控制中心等系统管理项目不属于隐藏保证范围。
- 缺少稳定辅助功能元数据或 `AXPress` 支持的项目，可能只能打开宿主 App，或保持不可用。
- 前台 App 菜单过长、刘海屏和显示器变化仍可能让 macOS 裁切项目。布局状态不确定时，Menu Hub 会恢复到安全展开状态。
- 兼容性可能受到 macOS 版本、显示器排列和第三方 App 版本影响。
- macOS 没有允许 App 把自身菜单项强制固定到绝对最左坐标的公开 API。Menu Hub 会优先创建主图标并让系统保存位置；如需调整，可按住 Command 自行拖动。

## 本地构建与测试

安装 XcodeGen 和 Swift 6 工具链后运行：

```sh
xcodegen generate
swift test
xcodebuild test \
  -project MenuHub.xcodeproj \
  -scheme MenuHub \
  -destination 'platform=macOS' \
  -skip-testing:MenuHubUITests \
  CODE_SIGNING_ALLOWED=NO
```

生成 Apple Silicon 与 Intel 原生发布构件：

```sh
./scripts/build-release.sh
```

根目录 `VERSION` 是版本号唯一来源，必须与 `project.yml` 中的 `MARKETING_VERSION` 一致。

## CI 发布

每次推送或合并到 `main` 都会运行 [.github/workflows/release.yml](.github/workflows/release.yml)，执行测试、构建两种芯片架构，并上传对应的 DMG 和 ZIP 构件。

`v*` 标签会生成 GitHub Release。受保护的 `release` 环境配置完成后，CI 会导入 Developer ID 证书、签名两个 App、提交 Apple 公证、装订公证票据、验证全部 8 个发布文件，并在批准后公开发布。

## 项目文档

- [本地验证报告](outputs/LocalValidationReport.md)
- [MVP 对照验收](outputs/MVP-Comparison-Audit.md)
- [发布清单](docs/ReleaseChecklist.md)
- [Phase 0 手工检查表](docs/Phase0ManualTestChecklist.md)
- [Phase 0 可行性报告](FeasibilityReport.md)
