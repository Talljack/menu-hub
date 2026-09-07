# Menu Hub 发布清单

状态日期：2026-09-07

本清单不把“代码已实现”等同于“已在真实机器验收”。只有带具体构建、测试、签名或实机证据的项目才能勾选。

## 工程与产品范围

- [x] Swift 6、SwiftUI + AppKit、最低 macOS 14。
- [x] 原生菜单栏 App，`LSUIElement=true`，无 Dock 图标。
- [x] App Sandbox 关闭，以支持用户授权后的 Accessibility 控制。
- [x] Hardened Runtime 构建设置已启用。
- [x] 仅使用系统框架；无第三方运行时、联网、分析、账号、Screen Recording、私有 API 或注入实现。
- [x] 可见四瓣 Hub 状态图标和透明 SpacerItem 均有实现。
- [x] `⌥M` 默认快捷键、冲突处理和设置录制器均有实现。
- [x] 面板、搜索、收藏、最近、常用、手动分组、别名、排序、忽略与宿主启动降级均有实现。
- [x] 首次设置、渐进授权、显式单 App repair、管理窗口和六区设置页均有实现。
- [x] English 与简体中文资源键集合一致（当前各 224 个本地化键）。
- [x] 本地原子 Catalog、备份恢复、显式导出/清除和脱敏诊断均有实现。

## 已记录的自动验证里程碑

- [x] Task 8 里程碑：185 项测试，0 失败。
- [x] Task 8 里程碑：Debug 与 Release 构建成功。
- [ ] 最终代码冻结后重新运行 `swift test`，记录总数与日志。
- [ ] 最终代码冻结后运行完整 Xcode 单元/集成测试。
- [ ] 建立并通过独立 UI Test target，包括双语、外观、权限 fixture、键盘和持久化场景。
- [ ] Release 模式 100 项搜索测试低于 16 ms，并记录实测数字。

## 安装前门禁

- [ ] 执行干净 Release 构建，确认 `MACOSX_DEPLOYMENT_TARGET=14.0`。
- [ ] 使用 Developer ID Application 签名，带安全时间戳。
- [ ] `codesign --verify --deep --strict --verbose=2` 通过。
- [ ] 确认 Hardened Runtime 存在，发布 entitlements 不含 `get-task-allow`。
- [ ] 用 `otool -L` 确认无禁止的第三方联网或分析框架。
- [ ] 旧 `/Applications/Menu Hub.app` 已移动到 `work/` 下的时间戳备份。
- [ ] 只运行一个 `com.local.MenuHub` 进程，启动路径来自 `/Applications/Menu Hub.app`。
- [ ] Accessibility 授权在保持相同 Bundle ID 与签名身份后仍有效；除非用户确认 repair，否则不重置 TCC。

## 当前 Mac 交互验收

- [ ] 菜单栏只有一个可见 Hub 图标，SpacerItem 无可见内容。
- [ ] 点击图标和 `⌥M` 均能稳定开关面板，搜索立即聚焦。
- [ ] 轨迹板、鼠标滚轮和拖动滚动条均可用，滚动条不覆盖行尾动作。
- [ ] 每行始终显示宿主 App 名称；飞书/Lark 等动态数字在刷新后与菜单栏同步。
- [ ] 鼠标、方向键、Return、`⌘Return`、`⌘K`、`⌘F`、`⌘1…9` 和两段 Escape 正常。
- [ ] AXPress 项目可触发；launch-only 项目可打开宿主；失败时有准确原因。
- [ ] 收藏、别名、分组、顺序、最近、常用和偏好在重启后保持。
- [ ] 授权、撤销、跳过和用户确认的 repair 流程均正常，无重复催促。
- [ ] Settings、管理窗口、诊断导出、登录时启动状态与“恢复菜单栏”正常。
- [ ] 简体中文与 English 切换正确；浅色、深色、减少透明度、减少动态效果和增大对比度可读。
- [ ] 崩溃或强制退出后重新启动处于安全展开状态。

## Phase 0 与发布级质量

- [ ] 至少 15 个代表性状态项完成发现、命名、Press、隐藏后 Press、弹出位置和恢复矩阵。
- [ ] 1000 次收起/展开与 500 次搜索/触发通过。
- [ ] 20 次睡眠/唤醒与 20 次显示器插拔通过。
- [ ] 刘海屏、非刘海屏、外接屏、缩放分辨率、全屏和 SystemUIServer 重启通过。
- [ ] macOS 14 与最新稳定 macOS 的真实硬件矩阵通过。
- [ ] 冷启动、面板 P95、空闲 30 分钟 CPU/唤醒、内存和包体均有记录并达到目标。
- [ ] 未安装开发证书的干净 Mac 完成安装、首次授权、更新和卸载验证。

## 分发

- [ ] `spctl --assess --type execute --verbose=4` 通过。
- [ ] `notarytool` 返回 Accepted，并完成 stapling 与二次验证。
- [ ] 生成签名并公证的 ZIP 或 DMG，发布 SHA-256。
- [ ] 发布说明包含权限用途、公开 API 限制、恢复步骤、本地数据路径和卸载方式。

在上述 Phase 0、最终自动化、实机与公证门禁完成前，不标记为“可公开发布”。
