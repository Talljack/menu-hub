# Menu Hub for macOS

[English](README.md) · [简体中文](README.zh-CN.md) · 繁體中文 · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md)

[下載最新版本](https://github.com/Talljack/menu-hub/releases/latest) · 需要 macOS 14 或以上版本 · 支援 Apple 晶片與 Intel

Menu Hub 是原生 macOS 選單列管理工具。按一下四瓣圖示，即可搜尋、辨識、整理並啟動目前執行中 App 的選單列項目。

<p align="center">
  <img src="docs/images/menu-hub-panel.png" alt="Menu Hub 在精簡的 macOS 面板中顯示可搜尋的選單列 App" width="520">
</p>

Menu Hub 使用 Swift 6、SwiftUI 與 AppKit 開發，只採用 macOS 公開 API。不使用 Electron、程式碼注入、螢幕錄製權限、分析 SDK、雲端服務或帳號。

## 安裝

1. 開啟 [GitHub 最新版本頁面](https://github.com/Talljack/menu-hub/releases/latest)。
2. 依 Mac 晶片下載對應的 DMG：Apple M1 或更新機型選擇 `arm64`；Intel Mac 選擇 `x86_64`。
3. 開啟 DMG，將 **Menu Hub** 拖到「應用程式」。
4. 推出 DMG，再從「應用程式」或 Spotlight 開啟 Menu Hub。
5. 在選單列尋找四瓣圖示。Menu Hub 不會顯示 Dock 圖示或一般主視窗。

同一個 Release 頁面也提供 ZIP 與 SHA-256 校驗檔。正式版本均以 Developer ID 簽署、經 Apple 公證，並可通過 Gatekeeper 檢查。

## 授予輔助使用權限

輔助使用權限可讓 Menu Hub 發現支援的選單列項目並執行其一般點按動作；未授權時仍可使用功能受限的 App 啟動器模式，不需要螢幕錄製權限。

1. 開啟 **設定 > 權限與隱私權**，按下 **開啟系統設定**。
2. 在 **隱私權與安全性 > 輔助使用** 中啟用 **Menu Hub**。
3. 若清單中沒有 Menu Hub，按 `+` 並選擇 `/Applications/Menu Hub.app`。
4. 返回 Menu Hub；App 會重新檢查權限並掃描。

如果開關已啟用但仍無權限，請在 **設定 > 權限與隱私權** 選擇 **修復權限**，確認後到系統設定重新啟用 Menu Hub，再按 **重新掃描**。此操作只會重設 Menu Hub 自己的 `com.local.MenuHub` 權限記錄。

## 使用方式

開啟輔助使用權限後，Menu Hub 會在選單列圖示旁顯示單色未讀總數。只有 macOS 公開的準確數字會計入；只有圓點而沒有數字時按 0 處理。可在 **設定 > 項目與群組** 中將每個項目設為「自動／一律計入／永不計入」。

- 按一下四瓣圖示開啟或關閉面板；按住 Option 再按圖示可收起或展開受管理的選單列區域。
- 在任何 App 中按 `⌥M` 切換面板；可在 **設定 > 快速鍵** 修改。
- 輸入 App 或項目名稱搜尋，按一下項目即可執行原本的選單列動作。
- `↑` / `↓` 移動選取，`Return` 執行，`⌘Return` 開啟宿主 App，`⌘K` 顯示動作，`Esc` 清除搜尋或關閉面板。
- 收藏、最近使用、常用、自訂群組、別名、排序與忽略項目可在 **設定 > 項目與群組** 管理。

## 語言、隱私與限制

Menu Hub 支援 10 種語言。可在 **設定 > 一般 > 語言** 跟隨 macOS 或自行選擇；不支援的系統語言會回退至英文。

所有目錄、偏好與使用記錄只保存在 `~/Library/Application Support/Menu Hub/`，不會上傳分析資料或使用者資料。

macOS 沒有能保證管理所有第三方選單列項目的公開 API。時鐘與控制中心等系統項目不在隱藏保證範圍；缺少穩定輔助使用資訊或 `AXPress` 支援的項目可能只能開啟宿主 App。相容性也會受到 macOS、螢幕配置與第三方 App 版本影響。

完整的建置、CI 與工程文件請參閱 [English README](README.md)。
