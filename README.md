<h1 align="center">Rastro</h1>

<p align="center">
  Sua linha do tempo como dev, nativa para macOS.<br>
  Commits, pull/merge requests, deploys e notas num só lugar, com standup pronto pra colar no chat do time.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-orange" alt="SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licen%C3%A7a-MIT-green" alt="Licença MIT"></a>
  <a href="https://buymeacoffee.com/vitorbellini"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-%E2%98%95-FFDD00" alt="Buy Me a Coffee"></a>
</p>

Tudo offline, com os dados na sua máquina (SQLite).

Planejamento e progresso: [ROADMAP.md](ROADMAP.md).

## O que ele faz

**Timeline**
- Escaneia as pastas que você escolher, acha os repositórios git e importa só os seus commits (filtrados pelo email do autor). Escaneia ao abrir e a cada 30 minutos.
- Trilho no estilo `git log --graph`: um marcador por evento, na cor do projeto, agrupado por dia.
- Clique num commit para ver a descrição completa (corpo da mensagem, lido do git na hora).
- Filtro por tipo com contagem (commits, PRs, deploys, notas) e busca.

**Pull requests e merge requests**
- GitLab: MRs mergeados vêm dos commits de merge locais (`See merge request grupo/projeto!N`), sem API e sem token.
- GitHub: PRs abertos, mergeados e fechados via [GitHub CLI](https://cli.github.com) já logado (`gh auth login`). O app não guarda token.

**Standup** (⌘U)
- Monta o que você fez no último dia de trabalho e hoje até agora, agrupado por projeto, com MRs repetidos juntos numa linha.
- Listas de "Hoje vou" e "Bloqueios", com sugestões do que está em aberto (deploys pendentes, PRs abertos).
- Copia em texto e HTML: cola formatado no Teams/Slack e limpo no terminal.

**Deploy**
- Lista de "precisa ir pra produção" por projeto. Marque um commit ou PR pela caixinha na timeline, pelo clique direito, com ⌘D ou escrevendo `[deploy]` na mensagem do commit.
- Epics: selecione vários commits de um projeto (⌘-clique / ⇧-clique) e agrupe numa epic, que sobe inteira de uma vez.

**Notas**
- Nota rápida de qualquer app com ⌥⌘N: escreve, Enter, volta ao que estava fazendo.
- Notas completas com título opcional, projeto e data, editáveis depois.

**Organização**
- Favoritos, grupos por cliente (com timeline combinada), renomear, trocar cor e esconder repositórios.
- Estatísticas: heatmap anual, sequência de dias com commits e projetos com mais commits.

## Requisitos

- macOS 14 ou mais novo
- Command Line Tools (`xcode-select --install`). Não precisa de Xcode: o build chama o `swiftc` direto.
- Opcional: [GitHub CLI](https://cli.github.com) para os PRs do GitHub.

## Rodando

```bash
make run      # compila em debug e abre build/Rastro.app
make test     # testes do núcleo
make install  # compila em release e copia para /Applications
```

Na primeira execução, abra **Ajustes** (⌘,), adicione as pastas onde ficam seus repositórios (ex: `~/code`) e confira o email do autor (vem do `git config --global user.email`).

Os dados ficam em `~/Library/Application Support/Rastro/timeline.sqlite`.

## Estrutura

```
Sources/
  RastroCore/     lógica sem interface, testável sozinha
                       GitScanner, RepoFinder, GitLogParser, MergeParser (PR/MR),
                       GitHubCLI, CommitMessage, Stats, Standup,
                       Database (SQLite + migrações), Importer, Models, Deploy
  Rastro/
    App/               entrada do app e atalho global
    Services/          AppStore: estado observável, recarrega do banco após cada escrita
    Views/             timeline, estatísticas, standup, deploy, epics, notas, ajustes
    Support/           ajustes, paleta de cores, atalhos
Scripts/               build.sh (swiftc) e quit.sh
Tests/
  RastroCoreTests/  parser, estatísticas, banco, standup, epics e scanner
                         com repositórios git reais em pasta temporária
```

O `Importer` é o único ponto que grava eventos importados e deduplica pelo `uid` de cada evento (`commit:<repo>#<hash>`, `pr:<remote>#<n>:<estado>`). Cada escaneamento busca só a partir do último commit conhecido do projeto, e o `INSERT OR IGNORE` descarta o que já existe.

## Licença

[MIT](LICENSE)

## Apoie

Se este projeto te ajudou, você pode me pagar um café ☕

<a href="https://buymeacoffee.com/vitorbellini"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="40"></a>
