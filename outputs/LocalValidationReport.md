# Menu Hub 本地验证报告

更新时间：2026-09-08
目标：Swift 6、macOS 14+、Bundle ID `com.local.MenuHub`

## 当前结论

本地 Release 验收版已经完成 `arm64` / `x86_64` 独立构建、DMG/ZIP 打包与架构验证；本机 `arm64` 副本经 Developer ID 签名后替换安装并启动，位置为 `/Applications/Menu Hub.app`。当前 SwiftPM 门禁为 238 项 XCTest、0 失败；中英文资源完整性另有 2 项 Swift Testing 测试通过。

用户报告的问题已有对应实测证据：面板使用固定头尾和独立单滚动区，并为系统滚动条保留右侧空间；飞书动态标题会随扫描更新，最终行标题由“宿主 App — 状态项”组成。当前 Mac 的主语言为 English，因此显示系统本地化名称 `Feishu`；所有项目都保留宿主名称，不再只显示数字。面板现只显示当前正在运行的用户 App，并在无权限降级时按宿主 App 去重；Control Center、Battery、Bluetooth、Clock、Focus、Passwords、Spotlight、SystemUIServer 与输入法代理均被排除。

仍未宣称可公开发布：独立 Xcode UI runner 在建立连接前超时，刘海/多显示器与耐久矩阵仍需专用测试机完成；当前安装版已通过实际辅助功能树与界面截图检查。

## 已有证据

| 项目 | 状态 | 证据或边界 |
|---|---|---|
| Swift / 部署目标 | 已配置 | `SWIFT_VERSION=6.0`，`MACOSX_DEPLOYMENT_TARGET=14.0` |
| 原生菜单栏结构 | 已实现 | AppKit `NSStatusItem` + `NSPopover`，`LSUIElement=true` |
| 状态图标 | 已安装并运行 | 四瓣 Hub 模板图标；Release 进程 PID 85675，快捷键回归后仍存活 |
| 默认快捷键 | 已实现、单元覆盖 | `⌥M`；可录制修改，冲突时保留旧值 |
| 主面板 | 已实现、Task 8 审查通过 | 固定搜索区、单一滚动区、固定底栏，滚动内容预留行尾操作与滚动条间距 |
| App 名称与动态数字 | 已实现、单元与本机数据验证 | 行项目保留 AX 目标身份，同时解析外层宿主 App 名称；数字变化按安全规则合并，飞书计数随实时扫描变化 |
| 用户 App 筛选 | PASS | 只显示当前运行的用户 App；第三方 Helper 归属外层 App；系统状态组件持久记录实测为 0；降级模式每个 App 一行 |
| 搜索与智能组 | 已实现、单元覆盖 | 模糊搜索、稳定排序、收藏、最近、30 天常用与手动分组 |
| AXPress 与降级 | 已实现、单元/集成覆盖 | 触发前重解析；失效/无动作时按能力打开宿主 App 或显示不可用 |
| 权限流程 | 已实现、单元覆盖 | 可跳过进入 launcher 模式；返回前台重新检测；repair 仅在用户确认后重置本 Bundle ID |
| 持久化 | 已实现、单元覆盖 | Codable JSON、schema v1、原子发布、备份、故障恢复和进程间锁 |
| 管理与设置 | 已实现并进入最终构建 | 管理项目与六区设置、登录时启动、快捷键、语言、外观、权限、诊断 |
| 双语 | 自动化通过 | English / 简体中文键集合一致并已打入安装包；实际窗口视觉切换仍待解锁后验收 |
| 本地隐私 | 源码确认 | 数据位于 `~/Library/Application Support/Menu Hub/`；无网络、分析、截图或 Screen Recording 代码 |
| 诊断 | 实现与脱敏测试存在 | 只在用户确认保存后导出；主目录/用户名/查询被删除，项目标识哈希化 |

## 最终门禁结果

| 门禁 | 最终结果 | 证据或边界 |
|---|---|---|
| `swift test` | PASS | 2026-09-08，238 项、0 失败；另有 2 项本地化 Swift Testing 测试通过 |
| Xcode UI tests | BLOCKED | 测试 target 和场景已建立；runner 在建立连接前超时，未伪报通过 |
| Release search performance | PASS | 100 项搜索回归测试已通过，早前 Release 实测约 0.675 ms/次，目标 < 16 ms |
| Clean Release build | PASS | `arm64` 与 `x86_64` 独立 Release 构建均成功，最低部署目标 macOS 14 |
| Bundle identity/signature | PASS | `com.local.MenuHub`；Developer ID `636LV693YD`；严格深度签名校验通过；Hardened Runtime |
| Linked frameworks/privacy scan | PASS | 仅系统 Framework/Swift 运行库；无 Electron、第三方 SDK、网络或分析框架 |
| Install/launch | PASS | 本机 `arm64` 版安装于 `/Applications/Menu Hub.app`，唯一进程 PID 92120 |
| Release 崩溃回归 | PASS | 修复 Release-only SwiftUI actor 隔离崩溃后，再次用 `⌥M` 打开未产生新崩溃报告，进程持续运行 |
| Panel/scroll/Lark display | PASS | 已通过本机辅助功能树与截图检查：系统组件消失、每个运行 App 一行、飞书使用宿主名加动态数字；滚动条位于预留槽内 |
| WeChat badge disappearance | PASS | 实际复现旧记录 `WeChat — 1` 到无角标；修复后点击会关闭 Hub 成功态并唤起微信，再打开无 stale warning |
| DMG/ZIP architecture packages | PASS | 两套 DMG 均可挂载且含 Applications 快捷方式；两套 ZIP 均可解压；Mach-O 分别严格为 `arm64` / `x86_64`，校验和通过 |
| Settings/management/localization | PARTIAL | 代码、自动化与打包资源通过；最终窗口视觉切换待解锁 |
| Restore and crash safety | PARTIAL | 状态机与异常启动测试通过；长循环及 SystemUIServer/硬件场景未完成 |

## 仍未验证，不得推断为通过

- 独立 UI Test target 及其完整场景。
- 15 个代表性项目的隐藏后触发兼容性矩阵。
- 非刘海屏、外接屏、显示器切换、缩放分辨率和全屏行为。
- macOS 14 真实硬件和最新公开测试版。
- 1000 次收起/展开、500 次搜索/触发、20 次睡眠/唤醒、20 次显示器插拔。
- 冷启动 < 500 ms、面板 P95 < 100 ms、空闲 CPU < 0.2%、稳态内存 < 45 MB。
- 正式公证、stapling、Gatekeeper 和无开发证书干净 Mac 安装。

## 公开 API 限制

Menu Hub 不能保证控制所有第三方或系统菜单栏项目。目标 App 若未暴露稳定 Accessibility 语义，结果可能是仅打开宿主 App 或不可用。菜单过长、刘海与多显示器布局由 macOS 管理，透明 SpacerItem 只能影响空间，不能私自重排其他 App 的图标。
