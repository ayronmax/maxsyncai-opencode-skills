# dev-workflow.md — Playbook Operacional

> Playbook completo do fluxo OpenSpec. Lido sob demanda (o `AGENTS.md` carrega
> o contrato enxuto a cada sessão; este arquivo contém o detalhe de processo
> para quando o agente precisar). Se há divergência entre `AGENTS.md` e este
> arquivo, `AGENTS.md` prevalece como contrato.

## Sumário

1. [Fase explore — antes de começar](#1-fase-explore--antes-de-começar)
2. [Fase propose — proposta e tasks](#2-fase-propose--proposta-e-tasks)
3. [Fase apply — implementação](#3-fase-apply--implementação)
4. [Fase validate (GATE 3 — fora do apply)](#4-fase-validate-gate-3--fora-do-apply)
5. [Fase PR (GATE 4)](#5-fase-pr-gate-4)
6. [Fase archive — após merge](#6-fase-archive--após-merge)
7. [Mapa de MCPs por fase](#7-mapa-de-mcps-por-fase)
8. [Skills OpenSpec — árvore de decisão](#8-skills-openspec--árvore-de-decisão)
9. [Handover entre sessões](#9-handover-entre-sessões)
10. [Template de explore-brief](#10-template-de-explore-brief)
11. [Performance de testes](#11-performance-de-testes)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Fase explore — antes de começar

Objetivo: entender o problema, investigar o codebase, levantar requisitos e
validar a abordagem antes de qualquer escrita de código.

A fase explore tem **duas modalidades** — siga a skill `openspec-explore`
("stance, not workflow", skill:17; "curious, not prescriptive", skill:25):
a etiqueta da skill prevalece na operação fina dentro de cada modalidade.

### 1a. Explore-stance (ideia vaga, sem change concreta)

Thinking time. Sem checklist obrigatório. Sem `make check`. Sem captura
forçada (skill:139 "don't auto-capture" — offer, don't just do it). GATE 0 é
**opcional mas recomendado**. O fluxo:

- A skill `openspec-explore` é "curious, not prescriptive" (skill:25), "open
  threads, not interrogations" (skill:26), "patient — let the shape of the
  problem emerge" (skill:29), "be brief — this is thinking time" (skill:150).
- Pode usar ASCII diagrams, comparar opções, challenge assumptions, surface
  risks/unknowns (skill:74-77 — gera Open Questions/Spikes que alimentam o
  `explore-brief.md` se virar change).
- A tríade de research (1b) é **ferramenta sugerida, não step obrigatório**:
  pivot, solte threads, siga o que emergir. Use-a só quando densidade técnica
  justificar.
- Se insights cristalizarem, ofereça criar proposal (skill:104-108 — "Want me
  to create a proposal?" — o usuário decide, não pressure).

### 1b. Explore-pré-change (change existe ou vai ser criada)

Modo operacional: checklist reconcilia contexto e mapeia o trabalho. GATE 0 é
**obrigatório**.

### Checklist da fase explore-pré-change

- [ ] **GATE 0 — Lookup obrigatório no Basic Memory**:
  - `basic-memory_search` pelo tópico da change
  - `basic-memory_recent_activity` dos últimos 7 dias
  - Leia as notas relacionadas — nunca comece sem recuperar o contexto persistido
- [ ] **Localizar a change atual** (se existir):
  ```bash
  openspec list
  openspec status --change "<name>" --json
  ```
- [ ] **Ler os artefatos da change**: `proposal.md`, `design.md` (incl.
  `## Open Questions`), `tasks.md` (e `specs/**/*.md` quando houver)
- [ ] **Tríade de research (paralela, batch)** — ferramenta sugerida para
  destravar densidade técnica; **não obrigatória** se a skill explore está
  seguindo thread emergente mais produtiva. Substitui a antiga análise
  automática de complexidade:
  | Sub-questão | Tool |
  |---|---|
  | "Como a lib é descrita pelos autores?" | **Context7** — `resolve-library-id` → `query-docs` |
  | "Como devs reais a usam em produção?" | **Octocode** — `ghSearchCode` (modo `discovery`/`concise`), `ghViewRepoStructure` |
  | "O que a web diz de boas práticas atuais?" | **webfetch** nativo do agente |
  Execute as três em paralelo numa única mensagem de tool calls — depois
  consolide o que aprendeu no `design.md` (decisão registrada).
- [ ] **Mapear código-alvo sem ler arquivo inteiro** — rode
  `serena get_symbols_overview` nos arquivos-alvo prováveis. Barato e preciso.
- [ ] **Confirmar branch main limpa** (quando criar nova change):
  ```bash
  git status
  git checkout -b feature/<descricao-curta>
  ```
- [ ] **Preencher `openspec/templates/explore-brief.md`** quando a change for
  nova (ou usar como checklist mental quando já existe proposta). As seções
  "Open Questions / Unknowns" e "Spikes sugeridos" alimentam diretamente o
  `## Open Questions` do `design.md`.

> `make check` (~10 min QA pré-dev) **não pertence à fase explore** (é
> thinking time, skill:150). Migrou para o início do §3 apply.

### Onde a "complexidade" mora agora

No fluxo OpenSpec, a análise de complexidade vira julgamento **humano + IA
informado pela tríade de research**, registrado em `design.md` na seção
`Decisions` (com alternativas consideradas) e `Risks / Trade-offs` (com
mitigações) e `## Open Questions` (com owner e status). É executada na fase
`propose`, antes do GATE 1 — não há step automático que pontua; há decisão
registrada.

---

## 2. Fase propose — proposta e tasks

> **Pré-requisito**: GATE 5 verde da change anterior — rode
> `./scripts/close-change.sh <ultima-change>` antes de iniciar nova change.
> Se há work in progress de change anterior (branch pendurada, tasks
> penduradas), resolva via `close-change.sh` (ou `openspec archive --delete`
> documentado) antes de criar change nova. **Uma change ativa por vez.**

Objetivo: criar os artefatos da change com a decisão técnica registrada.

### Passos

1. **Criar a change** usando a skill apropriada:
   - `/opsx-propose` — cria `proposal.md` + `design.md` + `tasks.md` (+ specs
     se houver mudança de produto)
   - `/opsx-ff-change` — fast-forward: todos artefatos de uma vez
   - `/opsx-new-change` — step-by-step, do zero
   - `/opsx-continue-change` — cria o próximo artefato faltante
2. **Preencher `design.md`**: registrar a decisão técnica com base no
   research da fase explore. Seções canônicas:
   - `## Decisions` — cada decisão numerada, com alternativa considerada
   - `## Risks / Trade-offs` — riscos e mitigações
   - `## Migration Plan` — quando houver remoção/migração de tooling
   - `## Open Questions` (rule em `openspec/config.yaml`) — formato
     `Q | Owner | Spike/Research | Status | Resolvido em`. Mesmo que "Nenhuma
     em aberto" como placeholder. O instruction do artifact `tasks` do package
     procura essa seção antes de gerar tasks — não a omita.
   Template de referência em `openspec/templates/design.md`.
3. **Quebrar `tasks.md` em chunks ≤ 2h** (regra do `openspec/config.yaml`).
   Antes de submeter, valide que Open Questions do `design.md` estão
   resolvidas ou justificadas (instruction do artifact `tasks` exige — não
   cozinhe suposição implícita). Tipo Spike suportado:
   `- [ ] X.Y Spike: <pergunta> → decision em <arquivo>`.
   Últimas tasks de cada change: **validação** (`openspec validate`,
   `make lint`, `make test-backend-fast`, `push-safe.sh`) e **PR**.
4. **Declarar `skip_specs: true`** em `.openspec.yaml` quando a change for de
   tooling/documentação (sem mudança de comportamento do produto).

> **Reusável fora do pipeline rígido**: `/opsx-update-change` revisa
> artefatos em qualquer direção (build order é ordem de leitura, não
> restrição, skill:58) — use quando descobrir ambiguidade nas Open Questions.
> `/opsx-sync` roda `openspec-sync-specs` sem archive.

### GATE 1 — PARE

Após criar os artefatos, **PARE** e aguarde aprovação explícita do humano
(palavra literal `aprovar`). Não avance para `apply` nem crie/execute tasks
sem esse sinal. Se o humano pedir ajustes, atualize os artefatos e pare
novamente.

---

## 3. Fase apply — implementação

Objetivo: implementar as tasks do `tasks.md` em ordem, com precisão.

### GATE 5 — Closeout da anterior (pré-apply)

Antes de retomar trabalho numa change (invocar `/opsx-apply-change`), rode
`./scripts/close-change.sh <ultima-change>` (modo padrão) e exija saída verde.
Se houver work in progress de change anterior (branch pendurada, tasks
penduradas), resolva via `close-change.sh` (ou `openspec archive --delete`
documentado) antes de codar. Para a primeira change do projeto: `openspec list`
retorna 0 ativas, `git branch` sem `feature/*` pendurada, `main` sincronizada.
**Uma change ativa por vez.** (Bootstrapping: changes que criam/modificam
gates são isentas de GATE 5 na própria implementação — GATE 5 vale a partir
da próxima change depois de merged+archived.)

### GATE 2 — Plano aprovado antes de codar

NUNCA invoque `/opsx-apply-change` (nem escreva código da change) sem antes
**apresentar o plano resumido das tasks** e receber confirmação literal
`aprovar` do humano.

### Pré-apply (QA pré-dev)

Confirme baseline limpa ANTES da primeira edição de código:

```bash
git status                            # branch feature/<change>, sem sujeira
make check                            # QA pré-dev (~10 min) — migrou da
                                      # fase explore (era thinking time)
```

Se `make check` falhar em testes pré-existentes da branch (`feature/<outra>`)
que não são desta change, registre como conhecido em `design.md` (Risk) e siga.

### Checklist durante o apply

- [ ] Trabalhar as tasks do `tasks.md` em **ordem** (ordem = sequência de
  dependências)
- [ ] Marcar `- [x]` imediatamente após concluir cada task (não ao final)
- [ ] Implementar incrementalmente, revisando diffs a cada step
- [ ] Usar **Serena** para edits em nível de símbolo (`replace_symbol_body`,
  `insert_before_symbol`, `find_referencing_symbols`) — não regex frágil
- [ ] Usar **Context7** para validar sintaxe de API antes de escrever
- [ ] Usar **Octocode** para achar exemplos de padrões reais quando travar
- [ ] Usar **Basic Memory** para commit de decisões verificadas durante a
  implementação (não espere o fim; se descobriu algo, registre)
- [ ] **Pause-livre quando task clara ficou ambígua** (skill
  `openspec-apply-change:100-101,168,172`): pause pontual, pergunte ao usuário,
  siga. **Não reabre GATE novo** — é pause de etiqueta interna, não gate do
  projeto. A skill é fluid (skill:184-185): pode ser invocada anytime, atualiza
  artefatos se design revelar issue.

### Se a implementação revelar problema de design

**Pausar e atualizar os artefatos da change** (`proposal.md`/`design.md`/`tasks.md`).
Nunca contornar no código — contornar cria divergência entre o que está escrito
no OpenSpec e o que está implementado, quebrando a auditoria no archive.

---

## 4. Fase validate (GATE 3 — fora do apply)

Objetivo: validação estrutural razoável de que a implementação está correta.
Executada como **comandos explícitos separados, fora do skill `apply`**.

> **Heurística da skill `/opsx-verify-change`** (skill:156): "don't require
> perfect certainty — prefer SUGGESTION over WARNING over CRITICAL". Incerteza
> vira `SUGGESTION`, divergência vira `WARNING`, só ausência objetiva vira
> `CRITICAL`. Não afirme prova com inferência.

### Checklist de validação

- [ ] **Testes**:
  - `make test-backend-fast` (desenvolvimento iterativo, ~10 min)
  - `make test` (pré-PR, completo, ~10 min)
  - `make test-frontend` (quando houver mudança no frontend)
- [ ] **Linter**: `make lint` (roda `ruff` no backend + ESLint no frontend)
- [ ] **OpenSpec structural**:
  ```bash
  openspec validate
  openspec doctor
  ```
- [ ] **Open Questions do design.md resolvidas ou justificadas** antes do PR
  (alinhado ao instruction do artifact `tasks`: "check design.md for Open
  Questions. If any of them would change what gets built, resolve them with
  the user first"). Se sobe alguma em aberto: resolva com o usuário ou
  justifique por que o PR pode avançar (decisão registrada em `design.md`).
- [ ] **Skill `/opsx-verify-change`**: rodar **antes** do push. Cruza a
  implementação com os artefatos da change (`tasks.md`, specs) e confirma
  cobertura — flag de inconsistência antes de abrir PR.
- [ ] **Dead code check** (opcional, em refactors): rode
  `serena find_referencing_symbols` em símbolos removidos/renomeados para
  confirmar que não há referências órfãs
- [ ] **Push-safe antes do push**:
  ```bash
  ./scripts/push-safe.sh --fast          # iteração (~30s)
  ./scripts/push-safe.sh --full          # pré-merge (~5min)
  ./scripts/push-safe.sh --validate-only # só schemas (~10s)
  ```

### Quando NÃO usar o push-safe

- Commits intermediários durante desenvolvimento (use `git commit` direto)
- Quando tiver certeza que testes passaram recentemente (use `git push --no-verify`)
- Em branches de experimentação que não serão merged

---

## 5. Fase PR (GATE 4)

Objetivo: publicar a change para revisão humana e **aguardar merge**. Nada é
archiveado antes do merge — o GATE 4 é não negociável.

### Sequência canônica (obrigatória)

1. **Confirmar `tasks.md` marcado `[x]` e commitado** — regra anti-regressão.
   Ao concluir todas as tasks, garanta que o
   `openspec/changes/<change>/tasks.md` esteja `- [x]` e incluso no commit.
   Rode `git status --porcelain` e, se houver mudanças não comitadas em
   `openspec/`, faça um commit extra dedicado
   (`docs(openspec): atualiza tasks da change <change>`). Nunca abra PR com
   `tasks.md` pendente de commit.
2. **`git push -u origin feature/<change>`** — publica a branch no remoto.
3. **`gh pr create`** — base `main`, head `feature/<change>`, body em pt-BR
   resumindo a change (Why + o que mudou + critérios de aceite).
4. **Review IA do diff** — auto-crítica antes de pedir tempo humano: rode
   a skill `/opsx-verify-change` ou uma revisão manual do `git diff main...HEAD`
   procurando bugs, convenções quebradas, tasks não cobertas.
5. **GATE 4 — PARE e aguarde review humano**. Não invoque
   `/opsx-archive-change`. Não force-push. Apenas aguarde.
6. **Após merge explícito do humano** → rode
   `./scripts/close-change.sh <change>` (orquestra `openspec archive` +
   chaser PR `chore/archive-<change>` + limpeza de branches). Veja
   [Fase 6 (archive)](#6-fase-archive--após-merge) para detalhes.
7. **Após merge do chaser PR** → rode
   `./scripts/close-change.sh --post-merge <change>` (steps 6-7: volta à
   main, pull, limpa branches penduradas).
8. **Registrar decisão no Basic Memory** — via `basic-memory_write_note`
   (details na Fase 6).

### Feedback no PR (loop de iteração)

Se o revisor humano pedir ajuste, **reabra o apply** (fase 3) — não crie nova
change:

- [ ] Atualizar `tasks.md` (adicionar task de correção nomeando a pendência).
- [ ] Se o design mudou, atualizar `design.md` (decisão registrada — **nunca
  contornar no código**; contornar quebra a auditoria no archive).
- [ ] Implementar a correção (apply incremental, Serena symbol edits).
- [ ] Re-rodar local: `make test-backend-fast` + `make lint` +
  `./scripts/push-safe.sh --fast`.
- [ ] `git push` — o PR atualiza automaticamente (mesmo branch/head). Nunca
  force-push sem coordenação com o revisor.
- [ ] Re-pausar em **GATE 4** (aplica-se a cada iteração, sem GATE novo).

### Quando NÃO usar push-safe nesta fase

- Commits intermediários durante o loop de feedback (use `git commit` direto).
- Quando tiver certeza que testes passaram recentemente (use `git push --no-verify`).
- Em branches de experimentação que não serão merged.

---

## 6. Fase archive — após merge

Objetivo: mergear deltas nas main specs e atualizar o knowledge vivo. Só executa
**após merge confirmado do PR** (GATE 4 cumprido). O fluxo é **orquestrado pelo
script `./scripts/close-change.sh <change>`** — não invoque `/opsx-archive-change`
direto; o script garante auditoria (marca N.8/N.9 **antes** de mover),
padroniza o closeout como **chaser PR canônico** (`chore/archive-<change>`) e
limpa branches penduradas após o merge.

### Fluxo do closeout

1. Após merge do PR de implementação, na branch `main` sincronizada:
   ```bash
   ./scripts/close-change.sh <change>
   ```
   O script roda 5 steps idempotentes:
   - **[1/7]** valida auditoria (tasks 100% `[x]`, `openspec validate`/`doctor`
     verdes, working tree limpa, `main` sincronizada, PR merged, nota no
     Basic Memory)
   - **[2/7]** marca `N.8` (GATE 4) e `N.9` (archive) como `[x]` em `tasks.md`
   - **[3/7]** roda `openspec archive <change>` (mergea deltas em
     `openspec/specs/`, move a change para `openspec/changes/archive/`)
   - **[4/7]** cria branch `chore/archive-<change>`, commit
     `chore(openspec): arquiva change <change>`
   - **[5/7]** abre PR chaser (base `main`) e **pausa em GATE 4 humano** (merge
     do chaser)

2. **Após merge do chaser PR**, limpe as branches penduradas:
   ```bash
   ./scripts/close-change.sh --post-merge <change>
   ```
   Steps 6-7: +`checkout main` +`pull` + deleta `chore/archive-<change>`
   (local+remoto) + deleta `feature/<change>` (local+remoto).

### Modo correção admin

Se `<change>` já está em `openspec/changes/archive/` mas tem tasks `N.8`/`N.9`
ainda `[ ]` (auditoria quebrada — sintoma do fluxo antigo), rode o script
novamente:
```bash
./scripts/close-change.sh <change>   # detecta estado arquivado, modo admin
```
Ele marca as tasks como `[x]` e abre PR admin
(`chore/admin-closeout-<change>`) — **não re-move** nem duplica archive.
Justificativa: correção de livro-razão, não regressão (D5 de
`enforce-closeout-gate`).

### Registro de decisão no Basic Memory

Após merge do chaser PR, registre a decisão técnica no Basic Memory via
`basic-memory_write_note` (nunca `.md` manual):
- Título: `Decisões Técnicas — <change-name>`
- Diretório: `"/"` (raiz do projeto Basic Memory)
- Relations:
  `- implements [[<capability>: <spec>]]` (quando a change tem spec deltas);
  `relates_to` / `depends_on` conforme necessário

As notas `Task N` existentes em `memories/` são **histórico** — não
regenerar, não deletar.

### Validação do Basic Memory

```bash
basic-memory status   # mostra "No changes" quando DB e filesystem estão sincronizados
basic-memory doctor   # valida consistência file/DB
```

---

## 7. Mapa de MCPs por fase

| Fase | MCP principal | Quando / por quê |
|---|---|---|
| explore | Basic Memory (GATE 0 lookup) + Octocode (impls reais, `discovery`/`concise`) + Context7 (`resolve-library-id` → `query-docs`) + webfetch (web) + Serena (`get_symbols_overview`) | Recuperar contexto, validar abordagem, mapear código-alvo sem ler arquivo inteiro |
| propose | Context7 (sintaxe p/ design) + Octocode (validar padrão) + Basic Memory (decisões passadas p/ referenciar) | Informar `design.md` |
| GATE 1 | (humano) | aprovar proposal |
| apply | Serena (edits em nível de símbolo) + Context7 (sintaxe) + Octocode (exemplos) + Basic Memory (commit decisões) | Implementação incremental precisa |
| GATE 2 | (humano) | aprovar plano |
| verify | Serena (`references` p/ dead code) + `make test`/`lint` + `openspec validate`/`doctor` + `/opsx-verify-change` | prova estrutural |
| PR/GATE 4 | (humano) | aprovar merge |
| archive | Basic Memory (`write_note`) + `openspec archive` (orquestrados por `./scripts/close-change.sh`) | knowledge vivo + closeout padronizado |
| sempre | RTK (auto-comprime output git/test) + TokenScope (`/tokenscope` a ~50% p/ handover) + Engram (captura passiva cross-projeto) | eficiência de tokens, visibilidade |

---

## 8. Skills OpenSpec — árvore de decisão

- **Caminho primário** (cada fase):
  `/opsx-explore` → `/opsx-propose` → `/opsx-apply-change` → `/opsx-verify-change` → `/opsx-archive-change`
- **Atalhos**:
  `/opsx-new-change` (do zero, step-by-step) · `/opsx-ff-change` (todos artefatos de uma vez) · `/opsx-continue-change` (próximo artefato faltante)
- **Secundárias**:
  `/opsx-update-change` (revisar plano existente) · `/opsx-sync-specs` (sync deltas sem archive) · `/opsx-bulk-archive-change` (várias changes juntas) · `/opsx-onboard` (tutorial)

---

## 9. Handover entre sessões

Use handover quando a sessão estiver longa, especialmente após tarefas grandes
ou quando o consumo de contexto passar de ~50% da janela útil do modelo (audite
com `/tokenscope`).

### Gatilhos

- `/tokenscope` mostra > ~50% de uso
- Após concluir uma task grande (que consumiu pesquisa, decisions, edits)
- Antes de uma pausa longa (deixar claro onde parar)

### Snippet canônico de handover

```
## Handover — <change-name> @ <YYYY-MM-DD>

### Feito nesta sessão
- <bullet do que foi implementado>

### Arquivos alterados
- <path>: <o que mudou>

### Decisões tomadas
- <decisão 1>
- <decisão 2>

### Testes executados
- `make test-backend-fast` → <verde/vermelho>

### Pendências
- <o que ainda falta>

### Próxima task recomendada
- <task-X.Y do tasks.md com一句话 do por quê>
```

### Nova sessão — como retomar

1. Colar o handover como primeira mensagem
2. Pedir ao agente: **"Leia `dev-workflow.md` e o handover; continue da próxima task."**
3. Confirmar onde estamos via:
   ```bash
   openspec status --change "<name>" --json
   ```
4. Retomar do bullet "Próxima task recomendada" do handover

---

## 10. Template de explore-brief

Em `openspec/templates/explore-brief.md` mora o template que alimenta
`proposal.md`. Use-o quando iniciar uma change nova (preencha como checklist
mental quando a change já existe).

Estrutura canônica:

1. Contexto — o que existe hoje, por que mudar, público
2. Objetivo — outcome em uma frase
3. Usuário-alvo — dor concreta, cenários reais
4. Escopo (nesta versão) — bullets
5. Fora de escopo (explicitamente) — bullets
6. Requisitos funcionais (RF01…RFnn)
7. Requisitos não funcionais (segurança, observabilidade, testabilidade, performance)
8. Arquitetura inicial — stack, módulos, integrações, decisões
9. Critérios de aceite — comportamento testável
10. Riscos e validações
11. Premissas
12. Métricas de sucesso

**Dica**: cada hora investida no brief evita 5 horas de retrabalho depois. Peça
ao agente para ler o brief e apontar ambiguidades **antes** de iniciar
`/opsx-propose`.

---

## 11. Performance de testes

| Comando | Tempo aprox. | Quando usar |
|---|---|---|
| `make test-backend-fast` | ~10 min | Desenvolvimento diário (unitários paralelos + integração sequencial) |
| `make test-backend` | ~10 min | CI / pre-commit (sequencial, determinístico) |
| `make test-backend-integration` | ~5 min | Só testes de integração |
| `make test-frontend` | ~1 min | Vitest |
| `make test` | ~10 min | Ambos (backend + frontend) |
| `make check` | ~10 min | QA pré-dev (lint + testes sequenciais) |

### Regras para evitar lentidão em novos testes

- **NUNCA usar `asyncio.sleep()` com tempo real em testes** — injete `_sleep` /
  `_asyncio_sleep` nas classes `PeladaTimer` e `PlacarManager` (ver
  `TESTING.md` seção "Otimizações de Performance")
- **NUNCA paralelizar testes de integração** — usam banco PostgreSQL
  compartilhado; execução concorrente quebra fixtures
- **Preferir `make test-backend-fast`** durante desenvolvimento iterativo
- **Fixtures de limpeza de DB** devem truncar apenas **antes** do teste (não
  antes E depois — dobra o tempo)
- **Timeout de comandos**: passe sempre `timeout` em ms nas chamadas do bash:
  - Testes (`make test*`): `timeout: 600000` (10 min)
  - Commits (`git commit`): `timeout: 30000` (30s — hooks são rápidos)
  - Comandos rápidos (lint, status, format): `timeout: 30000`

---

## 12. Troubleshooting

### OpenSpec não valida a change

- Rode `openspec validate` e leia o erro linha a linha — geralmente é link
  quebrado em `specs/**/*.md` ou campo faltando em `proposal.md`
- Rode `openspec doctor` para checar relações entre specs e changes
- Verifique se `.openspec.yaml` está na raiz da change com `schema: spec-driven`

### O agente começou a change sem GATE 0

Isso é bug do agente, não do fluxo. Reforce: **GATE 0 é lookup obrigatório no
Basic Memory antes de iniciar QUALQUER change**. Se pegar no meio, pare e
rode `basic-memory_search` retrospectivamente.

### PR sem merge (GATE 4 não cumprido)

Se o agente invocou `/opsx-archive-change` sem merge confirmado, isso é bug do
agente. **GATE 4 é não negociável**: após `gh pr create`, PARE e aguarde o humano
fazer merge explícito. Se precisar reverter, restaure a change de
`openspec/changes/archive/` para `openspec/changes/` (não há dano permanente
enquanto o merge via PR não ocorrer).

### Serena: "language server failed to start"

- Confirme que a linguagem do projeto é suportada (Python/TS suportados)
- Reinstale: `uv tool install --force serena`
- Reindexe: `uvx --from git+https://github.com/oraios/serena serena project index`
- Aumente o `timeout` no `opencode.json` (ex.: `120000` para projetos grandes)

### Basic Memory: "project not found"

- Rode `basic-memory project list` e confirme que `{{PROJECT_NAME}}` está registrado
- Verifique que o path é absoluto em `basic-memory project list`
- Confirme que o `opencode.json` do projeto usa `--project {{PROJECT_NAME}}`

### RTK não está comprimindo

- Confirme que `rtk init -g` foi executado após instalar o cliente
- `rtk gain` mostra se o hook está sendo acionado; se vazio, o hook não ativa
- Lembre: o hook só roda em chamadas do Bash tool, não nas tools nativas
  (Read/Grep/Glob). Para ter benefício nesses, chame `rtk read`, `rtk grep`,
  `rtk find` explicitamente

### Comandos não encontrados no Linux/WSL

Após instalar via `uv tool install` ou `npm install -g`, pode ser necessário
adicionar ao PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### OpenCode não carrega MCPs

- Verifique que o `opencode.json` é JSON válido: `jq . opencode.json`
- Reinicie o OpenCode por completo após qualquer alteração no arquivo
- Verifique que o `command` no MCP existe e é executável (`which <bin>`)

### Hooks do pre-commit não rodam / `.git/hooks/*` ausentes

- O skill `maxdev-workflow-sync` entrega `.pre-commit-config.yaml` mas não os
  hooks em `.git/hooks/*` — esses são **regenerados pela ferramenta `pre-commit`
  a partir do `.pre-commit-config.yaml`** (não versionar: caminhos hardcoded da
  máquina).
- Em `--apply` a skill **auto-instala** hooks se `pre-commit` existir. Skipa
  automaticamente em CI, ambientes com hook manager alternativo (`.husky/`,
  `lefthook.yml`, `.simple-git-hooks`), ou sem `.git/`. Force com `--install-hooks`.
- Day-0 manual: `pre-commit install --hook-type pre-commit --hook-type pre-push`
  regenera os 2 hooks usados pelo workflow (`block-main` em pre-commit,
  `block-main-push` em pre-push).
- Confirme com `pre-commit run --all-files` (deve executar hooks declarados).

### `.gitignore` desatualizado

- A skill sincroniza `.gitignore` com uma seção delimitada entre markers
  `# >>> maxdev-workflow-sync >>>` / `# <<< maxdev-workflow-sync <<<`.
- O re-sync substitui **só o bloco entre markers** — entries custom
  acima/abaixo são preservadas.
- Se markers aparecerem desbalanceados (begin sem end ou vice-versa),
  o sync aborta a atualização do `.gitignore` com warning — remova
  manualmente os markers restantes e rode novamente.

### Push-safe demora muito

- Use `--fast` (iteração) ou `--validate-only` (só schemas)
- Se falhar em lint: rode `make fix` para auto-corrigir
- Se falhar em testes: rode `make test` para ver output completo

### Closeout não fecha (`close-change.sh` aborta)

- **`tasks.md tem N task(s) ainda [- [ ]]`**: marque todas como `[x]` no
  `tasks.md` antes de rodar o closeout (são chunks de implementação, não de
  closeout — não cabem no admin mode)
- **`PR não está MERGED`**: o script exige PR de implementação merged
  (`gh pr list --state merged --head feature/<change>`). Faça o merge no
  GitHub primeiro (GATE 4 humano)
- **`main não está sincronizada`**: `git pull origin main` antes de rodar
- **`basic-memory search não retornou resultados`**: crie a nota
  `Decisões Técnicas — <change>` via `basic-memory write_note` antes do
  closeout (regra do AGENTS.md)
- **Modo admin não tem nada a fazer**: tasks `N.8`/`N.9` já marcadas —
  auditoria já está correta, pule esta change
- **`nada a commitar após openspec archive`**: a change já pode estar
  arquivada — cheque `openspec/changes/archive/<change>/`. Use `--post-merge`
  para limpeza de branches penduradas que sobraram de close-out anterior
