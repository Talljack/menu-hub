# Menu Hub für macOS

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · Deutsch · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md)

[Neueste Version herunterladen](https://github.com/Talljack/menu-hub/releases/latest) · macOS 14 oder neuer · Apple Silicon und Intel

Menu Hub ist ein nativer Menüleisten-Manager für macOS. Über das vierblättrige Symbol kannst du die Menüleistenelemente geöffneter Apps suchen, erkennen, organisieren und auslösen.

<p align="center">
  <img src="docs/images/menu-hub-panel.png" alt="Menu Hub zeigt durchsuchbare Menüleisten-Apps in einem kompakten macOS-Fenster" width="520">
</p>

Menu Hub basiert auf Swift 6, SwiftUI und AppKit und verwendet ausschließlich öffentliche macOS-APIs. Es nutzt weder Electron noch Code-Injektion, Bildschirmaufnahmeberechtigung, Analyse-SDKs, Cloud-Dienste oder Konten.

## Installation

1. Öffne die [neueste GitHub-Version](https://github.com/Talljack/menu-hub/releases/latest).
2. Lade das passende DMG: `arm64` für Apple M1 oder neuer, `x86_64` für einen Intel Mac.
3. Öffne das DMG und ziehe **Menu Hub** in den Ordner **Programme**.
4. Wirf das DMG aus und starte Menu Hub über Programme oder Spotlight.
5. Suche das vierblättrige Symbol in der Menüleiste. Menu Hub zeigt weder ein Dock-Symbol noch ein normales Hauptfenster.

Auf derselben Release-Seite stehen ZIP-Dateien und SHA-256-Prüfsummen bereit. Offizielle Versionen sind mit Developer ID signiert, von Apple notarisiert und durch Gatekeeper geprüft.

## Bedienungshilfen-Berechtigung

Die Bedienungshilfen-Berechtigung ermöglicht das Erkennen unterstützter Menüleistenelemente und das Ausführen ihrer normalen Klickaktion. Ohne sie bleibt ein eingeschränkter App-Starter verfügbar. Eine Bildschirmaufnahmeberechtigung ist nicht erforderlich.

1. Öffne **Einstellungen > Berechtigungen & Datenschutz** und klicke auf **Systemeinstellungen öffnen**.
2. Aktiviere **Menu Hub** unter **Datenschutz & Sicherheit > Bedienungshilfen**.
3. Falls Menu Hub fehlt, klicke auf `+` und wähle `/Applications/Menu Hub.app`.
4. Kehre zu Menu Hub zurück; die Berechtigung wird erneut geprüft und die Menüleiste neu eingelesen.

Ist der Schalter bereits aktiv, aber der Zugriff fehlt weiterhin, wähle **Berechtigung reparieren**, aktiviere Menu Hub in den Systemeinstellungen erneut und klicke auf **Neu einlesen**. Dabei wird nur der Bedienungshilfen-Eintrag `com.local.MenuHub` von Menu Hub zurückgesetzt.

## Verwendung

Bei erteilter Bedienungshilfen-Berechtigung zeigt Menu Hub neben seinem Symbol eine einfarbige Gesamtsumme ungelesener Nachrichten an. Es zählt nur exakte Zahlen, die macOS über die Bedienungshilfen bereitstellt; ein Punkt ohne Zahl zählt als null. Unter **Einstellungen > Elemente & Gruppen** kann jedes Element auf Automatisch, Immer einbeziehen oder Nie einbeziehen gesetzt werden.

- Klicke auf das vierblättrige Symbol, um das Fenster zu öffnen oder zu schließen. Mit Option-Klick blendest du den verwalteten Bereich ein oder aus.
- Drücke in jeder App `⌥M`. Der Kurzbefehl lässt sich unter **Einstellungen > Kurzbefehle** ändern.
- Suche nach einer App oder einem Element und klicke auf ein Ergebnis, um dessen normale Aktion auszuführen.
- `↑` / `↓` wählt aus, `Return` führt aus, `⌘Return` öffnet die Host-App, `⌘K` zeigt Aktionen und `Esc` leert die Suche oder schließt das Fenster.
- Favoriten, zuletzt und häufig verwendete Elemente, Gruppen, Aliasse, Reihenfolge und ignorierte Elemente verwaltest du unter **Einstellungen > Elemente & Gruppen**.

## Sprache, Datenschutz und Einschränkungen

Menu Hub unterstützt 10 Sprachen. Unter **Einstellungen > Allgemein > Sprache** kannst du macOS folgen oder eine Sprache auswählen. Nicht unterstützte Systemsprachen verwenden Englisch.

Katalog, Einstellungen und Nutzungsverlauf bleiben ausschließlich in `~/Library/Application Support/Menu Hub/`. Menu Hub sendet keine Analyse- oder Benutzerdaten.

Öffentliche macOS-APIs garantieren nicht die Verwaltung aller Menüleistenelemente von Drittanbietern. Systemelemente wie Uhr und Kontrollzentrum sind von der Ausblendgarantie ausgenommen. Elemente ohne stabile Bedienungshilfen-Metadaten oder `AXPress` können möglicherweise nur ihre Host-App öffnen. Die Kompatibilität hängt außerdem von macOS, der Displaykonfiguration und Drittanbieter-Versionen ab.

Informationen zu Build, CI und Technik findest du im [englischen README](README.md).
