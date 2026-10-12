# Roadmap do Rastro

## Visão

Um app nativo de Mac que registra automaticamente tudo que você faz como dev (commits, PRs, deploys, notas) e transforma isso em linha do tempo, estatísticas e relatórios. Funciona offline, sem servidor, com os dados na sua máquina.

## v0.1: base

- [x] Escaneamento de repositórios locais com importação incremental
- [x] Filtro por email do autor
- [x] Timeline agrupada por dia, busca e filtro por projeto e tipo
- [x] Notas manuais
- [x] Heatmap anual, sequências e ranking de projetos

## Fase 1: deixar redondo (v0.2)

Objetivo: usar no dia a dia sem atrito.

- [x] Validar o build e corrigir o que aparecer (build via `swiftc`, sem Xcode)
- [x] Escaneamento automático (ao abrir o app e a cada 30 min)
- [x] Várias pastas raiz
- [x] Renomear projeto, trocar cor, favoritar e esconder repositórios que não interessam
- [x] Agrupar projetos por cliente (grupo na barra lateral com timeline combinada)
- [ ] Mostrar branch e quantidade de arquivos alterados em cada commit
- [ ] Clicar num commit abre o diff ou o repositório no editor
- [x] Standup: resumo do último dia de trabalho e de hoje, agrupado por projeto, pronto pra colar no chat (⌘U)
- [x] Editar nota já salva
- [x] Lista de deploy por projeto: clique direito, caixinha no hover, ⌘D, `[deploy]` na mensagem ou tarefa escrita à mão
- [x] Epics: commits/PRs de um projeto que sobem juntos (⌘/⇧-clique na timeline ou clique direito); a epic é um item só no deploy

## Fase 2: barra de menu (v0.3)

Objetivo: o app vive no seu dia sem precisar abrir a janela.

- [ ] Ícone na barra de menu com contagem de commits de hoje e sequência atual
- [x] Nota rápida por atalho global (⌥⌘N), sobre qualquer app, inclusive em tela cheia
- [ ] Notificação no fim do dia com o resumo
- [ ] Abrir ao iniciar o macOS

> Vale desenhar a barra de menu pensando em reaproveitar em outros apps de barra de menu.

## Fase 3: fontes externas (v0.4)

Objetivo: a timeline mostrar mais que commits.

- [x] GitHub: PRs abertos, mergeados e fechados via `gh` já logado (sem token no app)
- [x] GitLab: MRs mergeados lidos dos commits de merge locais (`See merge request …!N`), sem API
- [ ] GitHub: reviews e issues
- [ ] Laravel Forge: deploys com status por site
- [ ] Arquitetura de fontes como protocolo (`EventSource`), pra adicionar GitLab, Bitbucket ou DigitalOcean sem mexer no resto
- [x] Tipo de evento `pullRequest`
- [ ] Tipos de evento `review` e `deploy`

## Fase 4: inteligência e relatórios (v0.5)

Objetivo: transformar histórico em algo útil pra você e pros clientes.

- [ ] Resumo semanal gerado por IA (API do Claude ou modelo local)
- [ ] Exportar período por projeto em PDF ou Markdown, pronto pra mandar ao cliente
- [ ] Estimativa de horas por projeto com base na distribuição dos commits ao longo do dia
- [ ] Detectar stack de cada repo lendo `composer.json`, `package.json` e afins, e mostrar estatísticas por tecnologia

## Fase 5: distribuição (v1.0)

- [ ] Ícone do app (bundle id e Info.plist já existem via `Scripts/build.sh`)
- [ ] App Sandbox com acesso às pastas via security scoped bookmarks
- [ ] Assinatura e notarização com Developer ID
- [ ] Atualização automática com Sparkle
- [ ] Decidir canal: gratuito no GitHub, pago no Gumroad ou Mac App Store

## Arquitetura

1. **Camada de dados:** SQLite do sistema (sem dependências), com migrações por `user_version`. Tabelas `projects`, `events` e futuramente `sources` (configuração de cada integração; credenciais no Keychain). Trocado do SwiftData porque os macros dele exigem Xcode.
2. **Fontes:** cada integração implementa `EventSource` e devolve eventos normalizados
3. **Importer:** único ponto que grava no banco e deduplica por `uid`
4. **Views:** SwiftUI puro, sem dependências externas até a fase de distribuição

## Decisões em aberto

- [ ] Manter o histórico só local ou oferecer sincronização (iCloud Drive com o arquivo SQLite, ou CloudKit manual)
- [ ] IA na nuvem (melhor resultado) ou local (privacidade, já que tem código de cliente)
- [ ] Produto pessoal ou algo pra vender a outros devs (muda o esforço nas fases 4 e 5)
