# Menu Hub para macOS

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · Português (Brasil) · [Русский](README.ru.md)

[Baixar a versão mais recente](https://github.com/Talljack/menu-hub/releases/latest) · macOS 14 ou posterior · Apple Silicon e Intel

O Menu Hub é um gerenciador nativo da barra de menus do macOS. Clique no ícone de quatro pétalas para pesquisar, identificar, organizar e acionar os itens da barra de menus dos aplicativos abertos.

<p align="center">
  <img src="docs/images/menu-hub-panel.png" alt="Menu Hub mostra aplicativos pesquisáveis da barra de menus em um painel compacto do macOS" width="520">
</p>

Ele é desenvolvido com Swift 6, SwiftUI e AppKit e usa somente APIs públicas do macOS. Não utiliza Electron, injeção de código, permissão de gravação de tela, SDK de análise, serviços em nuvem ou contas.

## Instalação

1. Abra a [versão mais recente no GitHub](https://github.com/Talljack/menu-hub/releases/latest).
2. Baixe o DMG correto: `arm64` para Apple M1 ou mais recente e `x86_64` para Mac com Intel.
3. Abra o DMG e arraste o **Menu Hub** para **Aplicativos**.
4. Ejete o DMG e abra o Menu Hub em Aplicativos ou pelo Spotlight.
5. Procure o ícone de quatro pétalas na barra de menus. O Menu Hub não mostra ícone no Dock nem uma janela principal comum.

A mesma página oferece arquivos ZIP e somas de verificação SHA-256. As versões oficiais são assinadas com Developer ID, notarizadas pela Apple e verificadas pelo Gatekeeper.

## Permissão de Acessibilidade

A permissão de Acessibilidade permite localizar itens compatíveis e executar a ação normal de clique. Sem ela, o Menu Hub ainda funciona como um iniciador de aplicativos limitado. A permissão de gravação de tela não é necessária.

1. Abra **Ajustes > Permissões e Privacidade** e clique em **Abrir Ajustes do Sistema**.
2. Ative **Menu Hub** em **Privacidade e Segurança > Acessibilidade**.
3. Se ele não estiver na lista, clique em `+` e selecione `/Applications/Menu Hub.app`.
4. Volte ao Menu Hub; o aplicativo verificará a permissão e fará uma nova varredura.

Se a opção já estiver ativa, mas o acesso continuar indisponível, escolha **Reparar permissão**, ative o Menu Hub novamente nos Ajustes do Sistema e clique em **Verificar novamente**. Isso redefine apenas a entrada de Acessibilidade `com.local.MenuHub` do Menu Hub.

## Como usar

Com a permissão de Acessibilidade, o Menu Hub sobrepõe no ícone de largura fixa um contador monocromático do total não lido. Apenas números exatos expostos pelo macOS são somados; um ponto sem número conta como zero. Em **Ajustes > Itens e grupos**, cada item pode ser definido como Automático, Sempre incluir ou Nunca incluir.

- Clique no ícone de quatro pétalas para abrir ou fechar o painel. Use Option-clique para ocultar ou mostrar a área gerenciada.
- Pressione `⌥M` em qualquer aplicativo. Altere o atalho em **Ajustes > Atalhos**.
- Pesquise pelo aplicativo ou item e clique em um resultado para executar sua ação normal.
- Use `↑` / `↓` para selecionar, `Return` para executar, `⌘Return` para abrir o aplicativo, `⌘K` para as ações e `Esc` para limpar a pesquisa ou fechar o painel.
- Gerencie favoritos, recentes, frequentes, grupos, aliases, ordem e itens ignorados em **Ajustes > Itens e Grupos**.

## Idioma, privacidade e limitações

O Menu Hub oferece 10 idiomas. Em **Ajustes > Geral > Idioma**, siga o macOS ou escolha um idioma. Idiomas do sistema não compatíveis usam inglês.

O catálogo, as preferências e o histórico ficam somente em `~/Library/Application Support/Menu Hub/`. O Menu Hub não envia dados de análise nem dados do usuário.

As APIs públicas do macOS não garantem o gerenciamento de todos os itens de terceiros. Itens do sistema, como Relógio e Central de Controle, não fazem parte da garantia de ocultação. Itens sem metadados estáveis de Acessibilidade ou `AXPress` podem apenas abrir o aplicativo correspondente. A compatibilidade também varia conforme o macOS, os monitores e as versões de terceiros.

Consulte o [README em inglês](README.md) para informações de compilação, CI e documentação técnica.
