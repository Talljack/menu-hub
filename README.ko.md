# Menu Hub for macOS

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · 한국어 · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md)

[최신 릴리스 다운로드](https://github.com/Talljack/menu-hub/releases/latest) · macOS 14 이상 · Apple Silicon 및 Intel 지원

Menu Hub는 macOS 네이티브 메뉴 막대 관리자입니다. 네잎 모양 아이콘을 클릭하여 실행 중인 앱의 메뉴 막대 항목을 검색하고, 식별하고, 정리하고, 실행할 수 있습니다.

<p align="center">
  <img src="docs/images/menu-hub-panel.png" alt="검색 가능한 메뉴 막대 앱을 간결한 macOS 패널에 표시하는 Menu Hub" width="520">
</p>

Swift 6, SwiftUI, AppKit으로 제작했으며 공개 macOS API만 사용합니다. Electron, 코드 주입, 화면 기록 권한, 분석 SDK, 클라우드 서비스 또는 계정을 사용하지 않습니다.

## 설치

1. [GitHub 최신 릴리스](https://github.com/Talljack/menu-hub/releases/latest)를 엽니다.
2. Mac에 맞는 DMG를 받습니다. Apple M1 이상은 `arm64`, Intel Mac은 `x86_64`를 선택합니다.
3. DMG를 열고 **Menu Hub**를 **응용 프로그램** 폴더로 드래그합니다.
4. DMG를 추출한 뒤 응용 프로그램 또는 Spotlight에서 Menu Hub를 실행합니다.
5. 메뉴 막대에서 네잎 모양 아이콘을 찾습니다. Menu Hub는 Dock 아이콘이나 일반 기본 창을 표시하지 않습니다.

같은 릴리스 페이지에서 ZIP과 SHA-256 체크섬도 제공합니다. 정식 릴리스는 Developer ID로 서명되고 Apple 공증 및 Gatekeeper 검사를 거칩니다.

## 손쉬운 사용 권한 부여

손쉬운 사용 권한은 지원되는 메뉴 막대 항목을 찾고 일반 클릭 동작을 실행하는 데 필요합니다. 권한이 없어도 제한된 앱 실행기 모드로 사용할 수 있으며 화면 기록 권한은 필요하지 않습니다.

1. **설정 > 권한 및 개인정보 보호**에서 **시스템 설정 열기**를 클릭합니다.
2. **개인정보 보호 및 보안 > 손쉬운 사용**에서 **Menu Hub**를 활성화합니다.
3. 목록에 없으면 `+`를 클릭하고 `/Applications/Menu Hub.app`을 선택합니다.
4. Menu Hub로 돌아오면 권한을 다시 확인하고 스캔합니다.

스위치가 켜져 있는데도 접근할 수 없다면 같은 설정 화면에서 **권한 복구**를 실행하고 시스템 설정에서 Menu Hub를 다시 활성화한 뒤 **다시 스캔**을 클릭하세요. 이 작업은 Menu Hub의 `com.local.MenuHub` 권한 항목만 재설정합니다.

## 사용 방법

손쉬운 사용 권한이 켜져 있으면 Menu Hub는 고정 너비의 메뉴 막대 아이콘 안에 읽지 않은 메시지 합계를 단색으로 겹쳐 표시합니다. macOS가 공개하는 정확한 숫자만 합산하며 숫자 없는 점은 0으로 처리합니다. **설정 > 항목 및 그룹**에서 각 항목을 자동, 항상 포함 또는 포함 안 함으로 지정할 수 있습니다.

- 네잎 아이콘을 클릭하여 패널을 열거나 닫습니다. Option-클릭으로 관리되는 메뉴 막대 영역을 숨기거나 표시합니다.
- 어느 앱에서든 `⌥M`으로 패널을 전환합니다. **설정 > 단축키**에서 변경할 수 있습니다.
- 앱 또는 항목 이름을 입력해 검색하고 항목을 클릭하여 원래 메뉴 막대 동작을 실행합니다.
- `↑` / `↓` 선택, `Return` 실행, `⌘Return` 호스트 앱 열기, `⌘K` 동작 메뉴, `Esc` 검색 지우기 또는 패널 닫기를 지원합니다.
- 즐겨찾기, 최근 사용, 자주 사용, 사용자 그룹, 별칭, 순서 및 무시 항목은 **설정 > 항목 및 그룹**에서 관리합니다.

## 언어, 개인정보 보호 및 제한

Menu Hub는 10개 언어를 지원합니다. **설정 > 일반 > 언어**에서 macOS를 따르거나 언어를 직접 선택할 수 있습니다. 지원하지 않는 시스템 언어는 영어로 표시됩니다.

카탈로그, 환경설정 및 사용 기록은 `~/Library/Application Support/Menu Hub/`에만 저장되며 분석 정보나 사용자 데이터를 전송하지 않습니다.

macOS 공개 API는 모든 타사 메뉴 막대 항목의 관리를 보장하지 않습니다. 시계와 제어 센터 같은 시스템 항목은 숨김 보장 대상이 아닙니다. 안정적인 손쉬운 사용 정보나 `AXPress`가 없는 항목은 호스트 앱만 열 수 있습니다. 호환성은 macOS, 디스플레이 구성 및 타사 앱 버전에 따라 달라질 수 있습니다.

빌드, CI 및 기술 문서는 [English README](README.md)를 참고하세요.
