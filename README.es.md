# Menu Hub para macOS

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · Español · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md)

[Descargar la última versión](https://github.com/Talljack/menu-hub/releases/latest) · macOS 14 o posterior · Apple Silicon e Intel

Menu Hub es un gestor nativo de la barra de menús de macOS. Haz clic en su icono de cuatro pétalos para buscar, identificar, organizar y activar los elementos de la barra de menús de las aplicaciones abiertas.

<p align="center">
  <img src="docs/images/menu-hub-panel.png" alt="Menu Hub muestra aplicaciones de la barra de menús en un panel compacto de macOS" width="520">
</p>

Está desarrollado con Swift 6, SwiftUI y AppKit, y solo utiliza API públicas de macOS. No usa Electron, inyección de código, permiso de grabación de pantalla, SDK de analítica, servicios en la nube ni cuentas.

## Instalación

1. Abre la [última versión en GitHub](https://github.com/Talljack/menu-hub/releases/latest).
2. Descarga el DMG adecuado: `arm64` para Apple M1 o posterior y `x86_64` para un Mac Intel.
3. Abre el DMG y arrastra **Menu Hub** a **Aplicaciones**.
4. Expulsa el DMG y abre Menu Hub desde Aplicaciones o Spotlight.
5. Busca el icono de cuatro pétalos en la barra de menús. Menu Hub no muestra un icono en el Dock ni una ventana principal convencional.

La misma página ofrece archivos ZIP y sumas SHA-256. Las versiones oficiales están firmadas con Developer ID, notarizadas por Apple y verificadas por Gatekeeper.

## Permiso de Accesibilidad

El permiso de Accesibilidad permite descubrir elementos compatibles y ejecutar su acción de clic habitual. Sin él, Menu Hub sigue disponible como lanzador de aplicaciones limitado. No necesita permiso de grabación de pantalla.

1. Ve a **Ajustes > Permisos y privacidad** y pulsa **Abrir Ajustes del Sistema**.
2. Activa **Menu Hub** en **Privacidad y seguridad > Accesibilidad**.
3. Si no aparece, pulsa `+` y selecciona `/Applications/Menu Hub.app`.
4. Vuelve a Menu Hub; la aplicación comprobará el permiso y volverá a explorar.

Si ya está activado pero Menu Hub sigue sin acceso, elige **Reparar permiso** en esa misma pantalla, vuelve a activarlo en Ajustes del Sistema y pulsa **Volver a explorar**. Solo se restablece la entrada de Accesibilidad `com.local.MenuHub` de Menu Hub.

## Uso

Con el permiso de Accesibilidad, Menu Hub superpone un contador monocromo del total sin leer dentro de su icono de ancho fijo. Solo suma números exactos expuestos por macOS; un punto sin número cuenta como cero. En **Ajustes > Elementos y grupos** puedes configurar cada elemento como Automático, Incluir siempre o No incluir.

- Haz clic en el icono de cuatro pétalos para abrir o cerrar el panel. Haz Option-clic para ocultar o mostrar el área gestionada.
- Pulsa `⌥M` desde cualquier aplicación. Puedes cambiarlo en **Ajustes > Atajos**.
- Busca por aplicación o elemento y haz clic en un resultado para ejecutar su acción normal.
- Usa `↑` / `↓` para seleccionar, `Return` para ejecutar, `⌘Return` para abrir la aplicación, `⌘K` para ver acciones y `Esc` para borrar la búsqueda o cerrar el panel.
- Gestiona favoritos, recientes, frecuentes, grupos, alias, orden y elementos ignorados en **Ajustes > Elementos y grupos**.

## Idioma, privacidad y limitaciones

Menu Hub admite 10 idiomas. En **Ajustes > General > Idioma** puedes seguir el idioma de macOS o elegir uno. Los idiomas del sistema no compatibles utilizan inglés.

El catálogo, las preferencias y el historial se guardan únicamente en `~/Library/Application Support/Menu Hub/`. Menu Hub no envía analítica ni datos personales.

Las API públicas de macOS no garantizan la gestión de todos los elementos de terceros. Los elementos del sistema, como el reloj y el Centro de control, no están cubiertos por la función de ocultación. Los elementos sin metadatos de Accesibilidad estables o sin `AXPress` pueden limitarse a abrir su aplicación. La compatibilidad puede variar según macOS, las pantallas y las versiones de terceros.

Consulta el [README en inglés](README.md) para información sobre compilación, CI y documentación técnica.
