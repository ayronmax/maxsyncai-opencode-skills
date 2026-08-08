# AGENTS.md — Contrato Operacional

> Template gerado por `maxdev-workflow-sync` v{{WORKFLOW_VERSION}}.
> Substitua os placeholders `{{...}}` pelos valores do seu projeto.
> Campos entre `<...>` são instruções de preenchimento.

Este projeto segue o fluxo **OpenSpec** em 6 fases:
`explore → propose → apply → verify → PR → archive`.

A **fonte de verdade** do trabalho é `openspec/changes/<change>/tasks.md`
(checklist de implementação — a única "task list" do projeto). Nunca use
backlogs externos. Nunca comite direto na main.

Para o detalhe de processo (checklists por fase, handover, troubleshooting,
performance de testes e modos do push-safe), leia `dev-workflow.md` na raiz.

## Fluxo OpenSpec

```
explore ─▶ propose ─▶ [GATE 1: aprovar proposal] ─▶ apply ─▶ [GATE 2: aprovar plano]
                                                                       │
                                                                       ▼
                                             [GATE 3: validar] ─▶ PR ─▶ [GATE 4: review humano]
                                                                          │
                                                                          ▼
                                                                       archive
```

- **explore** — entender o problema, investigar o codebase, levantar requisitos.
  É **stance, não workflow** (skill `openspec-explore:17`): duas modalidades:
  - **explore-stance** (ideia vaga, sem change concreta): thinking time — sem
    checklist obrigatório, sem `make check`, sem captura forçada. Siga a skill
    ("curious, not prescriptive", "don't auto-capture", "open threads, not
    interrogations", skill:25,139,26). GATE 0 é **opcional mas recomendado**.
  - **explore-pré-change** (change existe ou vai ser criada): checklist
    operacional em `dev-workflow.md §1b` (GATE 0 obrigatório, tríade de
    research, mapear código-alvo). GATE 0 é **obrigatório**.
- **propose** — criar a change (`proposal.md` + `design.md` + `specs/**/*.md` +
  `tasks.md`) com `/opsx-propose` ou `/opsx-ff-change`.
- **apply** — implementar as tasks do `tasks.md` em ordem com `/opsx-apply-change`,
  marcando `- [x]` a cada conclusão.
- **verify** — validar implementação com `/opsx-verify-change`
  (`make test*`, `make lint`, `openspec validate`/`doctor`, `push-safe.sh`) como
  comandos explícitos separados, **fora** do skill `apply` (GATE 3).
- **PR** — abrir com `gh pr create` (base `main`, head `feature/<change>`,
  body em pt-BR), revisar diff com IA, **pausar em GATE 4** (review humano);
  iterações pós-feedback reabrem o apply sem nova change.
- **archive** — só **após merge** do PR: rode `./scripts/close-change.sh <change>`
  (orquestra `openspec archive` + chaser PR `chore/archive-<change>` + limpeza de
  branches). Não invoque `/opsx-archive-change` direto — deixe o script orquestrar.

Se a implementação revelar problema de design, **pausar e atualizar os artefatos
da change** (`proposal.md`/`design.md`/`tasks.md`) — nunca contornar no código.

## Gates (obrigatórios — não negociáveis)

Estes gates NÃO são automáticos: o agente deve obedecer explicitamente. São
diretivas, não narrativa.

- **GATE 0 — Lookup obrigatório:** antes de criar ou selecionar uma change para
  trabalhar, rode `basic-memory_search` + `basic-memory_recent_activity` e leia
  as notas relacionadas. Em **explore-stance** speculativa (ideia vaga, sem
  change concreta — ver "Fase explore" abaixo) o lookup é **opcional mas
  recomendado**: siga a skill `openspec-explore` ("think freely", skill:103-108).
- **GATE 1 — Proposta aprovada antes das tasks:** após `/opsx-propose`, **PARE**
  e aguarde aprovação explícita do humano (`aprovar`). Não avance para `apply`
  nem crie/execute tasks sem esse sinal.
- **GATE 2 — Plano aprovado antes de codar:** NUNCA invoque `/opsx-apply-change`
  (nem escreva código da change) sem antes **apresentar o plano** resumido das
  tasks e receber confirmação literal `aprovar` do humano.
- **GATE 3 — Validação fora do apply (validação estrutural razoável):** os
  passos de validação/commit (`make test*`, `make lint`,
  `./scripts/push-safe.sh`, `git`) são executados **fora** do skill `apply`,
  como comando explícito separado após o apply concluir. A skill
  `/opsx-verify-change` pede "don't require perfect certainty — prefer
  SUGGESTION over WARNING over CRITICAL" (skill:156): não afirme prova com
  inferência; incerteza vira `SUGGESTION`, divergência vira `WARNING`, só
  ausência objetiva vira `CRITICAL`. Antes do PR, confirme que **Open
  Questions do design.md estão resolvidas ou justificadas** (o instruction do
  artifact `tasks` trata disso antes de gerar tasks; o `/opsx-verify-change`
  cruza novamente).
- **GATE 4 — Review humano do PR antes do archive:** após `gh pr create` e
  revisão IA do diff, **PARE** e aguarde merge explícito do humano. Nunca invoque
  `/opsx-archive-change` sem merge confirmado. Se o revisor pedir ajuste,
  reabra o apply (fase 3) e re-pause em GATE 4 após novo push.
- **GATE 5 — Closeout verde antes da próxima change:** antes de iniciar ou
  retomar trabalho em uma change — ou seja, antes de invocar `/opsx-propose`,
  `/opsx-apply-change`, `/opsx-new-change`, `/opsx-ff-change` ou
  `/opsx-continue-change` — rode `./scripts/close-change.sh <ultima-change>`
  (modo padrão) e exija saída verde (exit 0). O script valida: `tasks.md`
  100% `[x]`, `openspec validate`/`doctor` verdes, working tree limpa, `main`
  sincronizada com `origin/main`, PR de implementação MERGED, nota
  `Decisões Técnicas — <change>` existe no Basic Memory, e sem branch
  pendurada. Sem chunk de closeout (N.8/N.9) pendente em `tasks.md`. Para
  a primeira change do projeto: `openspec list` retorna 0 ativas, `git branch`
  sem `feature/*` pendurada, `main` sincronizada. **Uma change ativa por vez**
  — work-in-progress de change anterior precisa ser resolvido (merge via
  `close-change.sh`, ou `openspec archive --delete` documentado) antes de
  iniciar nova. **Bootstrapping**: changes que criam ou modificam gates são
  isentas de GATE 5 na sua própria implementação; GATE 5 vale a partir da
  próxima change depois de merged+archived.

## Ferramentas OpenSpec

Toda mudança vive em `openspec/changes/<change>/`:

- `proposal.md` — por que mudar (Why, What Changes, Capabilities, Impact).
- `specs/**/*.md` — deltas de comportamento quando o produto muda.
  **Cada capability listada no `proposal.md` DEVE ter um spec delta correspondente**
  em `specs/<capability>/spec.md`. O `close-change.sh` valida que o número de
  specs bate com o número de capabilities declaradas (a menos que
  `skip_specs: true` em `.openspec.yaml`).
- `design.md` — decisões técnicas e trade-offs (Decisions, Risks, Migration
  Plan, **e `## Open Questions` obrigatório** — rule em `openspec/config.yaml`;
  o instruction do artifact `tasks` do package procura essa seção antes de
  gerar tasks). Template de referência em `openspec/templates/design.md`.
- `tasks.md` — checklist de implementação (a única "task list"). Suporta tipo
  Spike (`- [ ] X.Y Spike: <pergunta> → decision em <arquivo>`).

Para mudanças puramente de tooling/documentação (sem mudança de comportamento do
produto), declare `skip_specs: true` em `.openspec.yaml` e não crie spec deltas.

```bash
openspec list                             # changes ativas
openspec status --change "<name>" --json  # estado dos artefatos (próxima task)
openspec instructions apply --change "<name>"   # instruções + contexto
openspec validate                         # valida raiz (specs/changes)
openspec doctor                           # saúde das referências
openspec archive <name>                   # mergea deltas e arquiva
```

## Mapa de MCPs por fase

| Fase | MCP principal | Quando / por quê |
|---|---|---|
| explore | Basic Memory (GATE 0 lookup) + Octocode (impls reais, `discovery`/`concise`) + Context7 (`resolve-library-id` → `query-docs`) + webfetch (web) + Serena (`get_symbols_overview`) | Recuperar contexto, validar abordagem, mapear código-alvo sem ler arquivo inteiro |
| propose | Context7 (sintaxe p/ design) + Octocode (validar padrão) + Basic Memory (decisões passadas p/ referenciar) | Informar `design.md` |
| GATE 1 | (humano) | aprovar proposal |
| apply | Serena (edits em nível de símbolo) + Context7 (sintaxe) + Octocode (exemplos) + Basic Memory (commit decisões) | Implementação incremental precisa |
| GATE 2 | (humano) | aprovar plano |
| verify | Serena (`references` p/ dead code) + `make test`/`lint` + `openspec validate`/`doctor` + `/opsx-verify-change` | validação estrutural razoável (incerteza → `SUGGESTION`) |
| PR/GATE 4 | (humano) | aprovar merge |
| archive | Basic Memory (`write_note`) + `openspec archive` (orquestrados por `./scripts/close-change.sh`) | knowledge vivo + closeout padronizado |
| sempre | RTK (auto-comprime output git/test) + TokenScope (`/tokenscope` a ~50% p/ handover) + Engram (captura passiva cross-projeto) | eficiência de tokens, visibilidade |

## Skills OpenSpec — árvore de decisão

- **Pré-requisito**: GATE 5 verde da change anterior (rode
  `./scripts/close-change.sh <ultima-change>`) antes de qualquer skill que
  inicia ou retoma change (`/opsx-propose`, `/opsx-apply-change`,
  `/opsx-new-change`, `/opsx-ff-change`, `/opsx-continue-change`). Skills
  OpenSpec upstream (em `.opencode/skills/openspec-*/`) **não são editadas**
  por este projeto — o contrato mora em `AGENTS.md`/`dev-workflow.md`, não em
  forks de skills (preserva upgrade path do package).
- **Caminho primário** (cada fase):
  `/opsx-explore` → `/opsx-propose` → `/opsx-apply-change` → `/opsx-verify-change` → `close-change.sh`
- **Atalhos**:
  `/opsx-new-change` (do zero, step-by-step) · `/opsx-ff-change` (todos artefatos de uma vez) · `/opsx-continue-change` (próximo artefato faltante)
- **Secundárias**:
  `/opsx-update-change` (revisar plano existente) · `/opsx-sync-specs` (sync deltas sem archive) · `/opsx-bulk-archive-change` (várias changes juntas) · `/opsx-onboard` (tutorial)

## Postura das skills OpenSpec (etiqueta interna prevalece)

As skills OpenSpec têm etiquetas internas que **não substituem gates do
projeto**, mas prevalecem na operação fina dentro de cada fase:

- **`openspec-apply-change` é fluid** (skill:184-185): pode ser invocada
  qualquer hora, atualiza artefatos se design revelar issue. **Pause-livre**
  quando task fica ambígua (skill:100-101,168,172): pausa pontual, **não
  reabre gate novo** — pode perguntar e seguir.
- **`openspec-update-change` revisa artefatos em qualquer direção**
  (skill:58): build order é ordem de leitura, não restrição. Usável quando
  descobrir ambiguidade nas Open Questions — não só no pipeline rígido.
- **`openspec-sync-specs` é reutilizável fora do archive** via `/opsx-sync`.
- **`openspec-verify-change` Heurística**: "don't require perfect certainty
  — prefer SUGGESTION over WARNING over CRITICAL" (skill:156). Incerteza
  vira `SUGGESTION`, divergência vira `WARNING`, só ausência objetiva vira
  `CRITICAL` — não afirme prova com inferência.

## Targets canônicos (use SÓ estes — outros nomes quebram)

<!-- {{MAKE_TARGETS}} — substitua pelos targets reais do seu Makefile. -->
<!-- Exemplo (ajuste ao seu projeto): -->
`make lint` · `make lint-backend` · `make lint-frontend`
`make test` · `make test-backend` · `make test-backend-fast` · `make test-backend-integration` · `make test-frontend`
`make check` · `make format` · `make build`

## Convenções do projeto

<!-- {{PROJECT_CONVENTIONS}} — substitua pelos valores reais do seu projeto. -->
- Linguagem: {{LANG_BACKEND}} (backend), {{LANG_FRONTEND}} (frontend)
- Gestor de pacotes: {{PKG_MANAGER_BACKEND}} (backend), {{PKG_MANAGER_FRONTEND}} (frontend)
- Framework de testes: {{TEST_FRAMEWORK_BACKEND}} (backend), {{TEST_FRAMEWORK_FRONTEND}} (frontend)
- Linter: {{LINTER_BACKEND}} (backend), {{LINTER_FRONTEND}} (frontend)
- Commit: Conventional Commits (pt-BR); nunca direto na main (hooks bloqueiam)
- Push seguro: `./scripts/push-safe.sh --fast` (desenv) / `--full` (pré-PR) / `--validate-only` (apenas schemas)
- **Uma change ativa por vez**: GATE 5 verde (`./scripts/close-change.sh <ultima-change>`)
  é pré-requisito para iniciar nova change — evita branches penduradas e
  acumulo de work-in-progress não arquivado.
- Idioma:
  - Código: inglês (nomes de variáveis, funções, classes, APIs)
  - Interface do usuário: português do Brasil (pt-BR)
  - Artefatos OpenSpec, documentação interna e PRs: português do Brasil (pt-BR)

## Registro de decisões no Basic Memory

- **Quando**: após merge do PR de implementação, **antes** de rodar
  `./scripts/close-change.sh <change>` (o script valida a existência da nota
  no step 1/7 e aborta se não encontrar).
- Título: `Decisões Técnicas — <change-name>` (ex: `Decisões Técnicas — add-auth`)
- Diretório: sempre `"/"` (raiz do projeto Basic Memory)
- Escrita: sempre via `write_note` do Basic Memory com `overwrite: true`
  (garante idempotência em re-execuções) — nunca `.md` manual
  (o `write_note` espelha DB ↔ filesystem em `memories/`; escrever `.md` manual
  não atualiza o banco e cria inconsistência)
- Conteúdo: decisões do `design.md` (resumo, decisões, artefatos, stack)
- Relations:
  - Se a change tem spec deltas (`openspec/changes/<change>/specs/` não vazio),
    extraia as capabilities do `proposal.md` e adicione para cada spec delta:
    `- implements: \`<capability>\` (openspec/specs/<capability>/spec.md)`
    Exemplo: `proposal.md` lista "nucleo-agentico" como capability →
    verifique `specs/nucleo-agentico/spec.md` → adicione:
    `- implements: \`nucleo-agentico\` (openspec/specs/nucleo-agentico/spec.md)`
    Use code-formatting (\`...\`) em vez de wiki links — specs são arquivos
    git, não notas do Basic Memory.
  - `relates_to` / `depends_on` conforme necessário
- As notas `Task N` existentes são **histórico** (não regenerar, não deletar)
- Parâmetros MCP canônicos:
  `title: "Decisões Técnicas — <change-name>"`
  `directory: "/"`
  `overwrite: true`
  `tags: ["decisao-tecnica", "<project-slug>", "<change-name>"]`
  `content: "<markdown com decisões e relations>"`

## Índice do projeto no Basic Memory

- Criar um índice central com o nome do projeto em **CAIXA ALTA** na raiz (`"/"`)
  do Basic Memory. Ex: para o projeto `{{PROJECT_NAME}}` → nota `{{PROJECT_NAME_UPPER}}`.
- O índice lista todas as notas `Decisões Técnicas — *` com wiki links `[[...]]`
  (aqui wiki links SÃO corretos — apontam para outras notas do Basic Memory).
- **Sempre que criar uma nova decisão técnica**, criar ou atualizar o índice:
  - Se o índice ainda não existe (primeiro closeout do projeto), criá-lo com
    `basic-memory_write_note` (parâmetros abaixo) listando a decisão.
  - Se já existe, usar `basic-memory_write_note` com `overwrite: true` para
    adicionar o link `[[Decisões Técnicas — <change-name>]]` à lista.
  - O `close-change.sh` valida que o índice existe e referencia a change
    (step 1/7) — se falhar, o script aborta com instrução explícita.
- Tags da nota de índice: `["projeto", "indice"]`
- Tags das notas de decisão: `["decisao-tecnica", "<project-slug>", "<change-name>"]`
- Parâmetros MCP canônicos para o índice:
  `title: "<PROJECT_NAME_UPPER>"`
  `directory: "/"`
  `overwrite: true`
  `note_type: "index"`
  `tags: ["projeto", "indice"]`

## Timeout de comandos (passe sempre `timeout` em ms no bash tool)

- Testes (`make test*`): `timeout: 600000` (10 min)
- Commits (`git commit`): `timeout: 30000` (30s — hooks são rápidos)
- Comandos rápidos (lint, status, format): `timeout: 30000`

## Finalização obrigatória dos artefatos OpenSpec

Ao concluir TODAS as tasks (ou ao fazer o commit final da implementação),
garanta que o `openspec/changes/<change>/tasks.md` esteja marcado `- [x]` e
**incluso no commit**. O `./scripts/close-change.sh <change>` (pós-merge do
PR de implementação) marca as tasks de closeout (N.8/N.9) e abre o chaser PR
de archive — não invoque `/opsx-archive-change` direto. Nunca finalize a
change com `tasks.md` pendente de commit.

## Referências

- `dev-workflow.md` (raiz) — playbook completo: checklists por fase, handover
  entre sessões, template de explore-brief, performance de testes, modos do
  push-safe e troubleshooting.
- `openspec/templates/explore-brief.md` — template que alimenta `proposal.md`.
- `openspec/config.yaml` — contexto do projeto + rules de artefatos (proposal/
  design/tasks).
- `.pre-commit-config.yaml` — hooks `block-main` (pre-commit) e `block-main-push`
  (pre-push) reforçam GATE 4. Day-0: `pre-commit install --hook-type pre-commit
  --hook-type pre-push` regenera `.git/hooks/*` (não versionar — caminhos
  hardcoded da máquina). Em `--apply` a skill `maxdev-workflow-sync` auto-instala
  se pre-commit existir (skip em CI/alt-managers — rode manualmente se skipou).
- `.gitignore` — seção delimitada entre markers `# >>> maxdev-workflow-sync >>>`
  / `# <<< maxdev-workflow-sync <<<` é re-syncada pela skill. Entries custom
  acima/abaixo dos markers são sempre preservadas.
- `.editorconfig` — UTF-8/LF/indent 4-Python-2-TS. Mantém consistência entre
  editores. Starter — customize conforme o projeto.

<!-- {{OPTIONAL_REFERENCES}} — adicione referências extras do seu projeto aqui (ex.: `TESTING.md`). -->
