# Clp

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Clp é um gerenciador de área de transferência nativo para macOS 26. Ele roda
como app de barra de menus, sem ícone no Dock, e mantém o histórico somente no
Mac.

## Requisitos

- macOS 26
- Xcode 26 com Swift 6.3
- Permissão de Acessibilidade para a colagem automática no app de destino

O projeto usa apenas SwiftPM, SwiftUI, AppKit e SwiftData. Não há `.xcodeproj`
nem dependências externas.

## Executar

```bash
./run.sh
```

O script compila em release, monta `dist/Clp.app`, aplica assinatura ad-hoc e
abre o bundle. Para executar diretamente pelo SwiftPM:

```bash
FORCE_SWIFT_RUN=1 ./run.sh
```

A execução como `.app` representa melhor o comportamento real de item de menu
bar, hotkey global e permissões do macOS.

## Usar

1. Copie normalmente um texto, link, imagem ou arquivo.
2. Pressione `Cmd+Shift+V` ou clique no ícone do Clp na barra de menus.
3. Digite para buscar imediatamente. A busca considera conteúdo, título,
   arquivo e aplicativo de origem, sem diferenciar caixa ou acentos.
4. Pressione Tab ou seta para baixo para entrar nos resultados. Use as setas,
   Enter ou os atalhos de 1 a 9 para colar.
5. Arraste cards para outros aplicativos ou para um board.

Esc fecha o painel. O clique secundário no ícone da barra de menus oferece
acesso a Configurações e à opção de sair.

## Interface

O painel usa Liquid Glass oficial do macOS 26 por meio de
`GlassEffectContainer` e `glassEffect`. Ele ocupa a largura física da tela,
fica colado à borda inferior e arredonda somente os cantos superiores. O shelf
usa cards fixos e uma pilha horizontal lazy para continuar fluido com históricos
grandes.

O item da barra de menus usa um símbolo nativo do macOS. O bundle inclui
`Resources/AppIcon.icns` via `build-app.sh` quando o arquivo está presente.

Imagens são reduzidas com ImageIO antes de aparecerem nos cards. Thumbnails e
ícones de aplicativos ficam em caches limitados.

## Privacidade e dados

- Bundle ID: `dev.erickribeiro.clp`
- Histórico local em
  `~/Library/Application Support/dev.erickribeiro.clp/Clp.store`
- Sem CloudKit na primeira versão
- Retenção de 24 horas, 7 dias, 30 dias ou nunca
- Itens em boards não expiram
- Conteúdos marcados como confidenciais ou transitórios são ignorados
- Aplicativos podem ser excluídos pelo bundle ID em Configurações
- Imagens usam armazenamento externo do SwiftData
- Arquivos usam bookmarks com escopo de segurança

## Permissão de Acessibilidade

O Clp precisa da permissão de Acessibilidade para enviar o `Cmd+V` ao
aplicativo de destino. O status e os atalhos para conceder a permissão aparecem
em Configurações.

Sem essa permissão, selecionar um card ainda copia seu conteúdo para a área de
transferência, mas não envia o `Cmd+V` automaticamente.

## Desenvolvimento

```bash
swift test -Xswiftc -warnings-as-errors
./build-app.sh
codesign --verify --deep --strict dist/Clp.app
```

O `build-app.sh` gera o bundle, valida o `Info.plist` e aplica assinatura ad-hoc
para desenvolvimento local. Distribuição pública e notarização não fazem parte
desta versão.

## Contribuindo

1. Faça um fork do repositório e crie uma branch a partir de `master`.
2. Implemente a mudança com commits claros.
3. Rode `swift test -Xswiftc -warnings-as-errors`.
4. Abra um pull request descrevendo o problema e a solução.

## Licença

Distribuído sob a licença [MIT](LICENSE).
