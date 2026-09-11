# Menu Hub pour macOS

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · Français · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md)

[Télécharger la dernière version](https://github.com/Talljack/menu-hub/releases/latest) · macOS 14 ou ultérieur · Apple Silicon et Intel

Menu Hub est un gestionnaire natif de la barre des menus de macOS. Cliquez sur son icône à quatre pétales pour rechercher, identifier, organiser et activer les éléments de la barre des menus des applications ouvertes.

<p align="center">
  <img src="docs/images/menu-hub-panel.png" alt="Menu Hub affiche les applications de la barre des menus dans un panneau macOS compact" width="520">
</p>

L'application est développée avec Swift 6, SwiftUI et AppKit et utilise uniquement les API publiques de macOS. Elle n'utilise ni Electron, ni injection de code, ni autorisation d'enregistrement de l'écran, ni SDK d'analyse, ni service cloud, ni compte.

## Installation

1. Ouvrez la [dernière version GitHub](https://github.com/Talljack/menu-hub/releases/latest).
2. Téléchargez le DMG adapté : `arm64` pour Apple M1 ou plus récent, `x86_64` pour un Mac Intel.
3. Ouvrez le DMG et faites glisser **Menu Hub** dans **Applications**.
4. Éjectez le DMG, puis lancez Menu Hub depuis Applications ou Spotlight.
5. Repérez l'icône à quatre pétales dans la barre des menus. Menu Hub n'affiche ni icône dans le Dock ni fenêtre principale classique.

La même page propose les archives ZIP et les sommes de contrôle SHA-256. Les versions officielles sont signées avec Developer ID, notariées par Apple et vérifiées par Gatekeeper.

## Autorisation d'accessibilité

L'autorisation d'accessibilité permet à Menu Hub de détecter les éléments compatibles et d'exécuter leur clic habituel. Sans elle, un mode lanceur d'applications limité reste disponible. L'autorisation d'enregistrement de l'écran n'est pas nécessaire.

1. Ouvrez **Réglages > Autorisations et confidentialité**, puis cliquez sur **Ouvrir Réglages Système**.
2. Activez **Menu Hub** dans **Confidentialité et sécurité > Accessibilité**.
3. S'il n'apparaît pas, cliquez sur `+` et sélectionnez `/Applications/Menu Hub.app`.
4. Revenez à Menu Hub : l'application revérifie l'autorisation et relance l'analyse.

Si l'option est déjà activée mais que l'accès est toujours refusé, choisissez **Réparer l'autorisation**, réactivez Menu Hub dans Réglages Système, puis cliquez sur **Réanalyser**. Seule l'entrée d'accessibilité `com.local.MenuHub` de Menu Hub est réinitialisée.

## Utilisation

Avec l'autorisation d'accessibilité, Menu Hub affiche à côté de son icône un compteur monochrome du total non lu. Seuls les nombres exacts exposés par macOS sont comptés ; un point sans nombre vaut zéro. Dans **Réglages > Éléments et groupes**, chaque élément peut être réglé sur Automatique, Toujours inclure ou Ne jamais inclure.

- Cliquez sur l'icône à quatre pétales pour ouvrir ou fermer le panneau. Faites Option-clic pour masquer ou afficher la zone gérée.
- Appuyez sur `⌥M` depuis n'importe quelle application. Modifiez ce raccourci dans **Réglages > Raccourcis**.
- Recherchez une application ou un élément, puis cliquez sur un résultat pour exécuter son action normale.
- Utilisez `↑` / `↓` pour sélectionner, `Return` pour exécuter, `⌘Return` pour ouvrir l'application hôte, `⌘K` pour les actions et `Esc` pour effacer la recherche ou fermer le panneau.
- Gérez favoris, éléments récents et fréquents, groupes, alias, ordre et éléments ignorés dans **Réglages > Éléments et groupes**.

## Langue, confidentialité et limites

Menu Hub prend en charge 10 langues. Dans **Réglages > Général > Langue**, suivez macOS ou choisissez une langue. Une langue système non prise en charge utilise l'anglais.

Le catalogue, les préférences et l'historique restent uniquement dans `~/Library/Application Support/Menu Hub/`. Aucune donnée d'analyse ou donnée utilisateur n'est envoyée.

Les API publiques de macOS ne garantissent pas la gestion de tous les éléments tiers. Les éléments système tels que l'horloge et le Centre de contrôle ne sont pas couverts par la garantie de masquage. Sans métadonnées d'accessibilité stables ou `AXPress`, un élément peut seulement ouvrir son application. La compatibilité dépend aussi de macOS, des écrans et des versions tierces.

Consultez le [README anglais](README.md) pour la compilation, la CI et la documentation technique.
