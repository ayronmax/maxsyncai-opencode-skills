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
explore ─▶ propose ─▶ [GATE 1: aprovar change] ─▶ apply
                                                       │
                                                       ▼
                          [GATE 2: validar + aprovar] ─▶ PR ─▶ [GATE 3: review humano]
                                                              │
                                                              ▼
                                                           archive ─▶ [GATE 4: closeout verde]
```

- **explore** — entender o problema, investigar, levantar requisitos. Stance, não workflow. Duas modalidades: explore-stance (ideia vaga, thinking time livre) e explore-pré-change (change existe, GATE 0 obrigatório). Detalhes em `dev-workflow.md §1`.
- **propose** — criar a change (`proposal.md` + `design.md` + `specs/**/*.md` + `tasks.md`) com `/opsx-propose` ou `/opsx-ff-change`.
- **apply** — implementar as tasks do `tasks.md` em ordem com `/opsx-apply-change`, marcando `- [x]` a cada conclusão.
- **verify** — validar com `/opsx-verify-change` + `make test*` + `make lint` + `openspec validate`/`doctor` + `push-safe.sh` como comandos explícitos, fora do skill `apply`.
- **PR** — abrir com `gh pr create` (base `main`, head `feature/<change>`, body em pt-BR), revisar diff com IA, pausar em GATE 3.
- **archive** — só após merge: `./scripts/close-change.sh <change>` (orquestra `openspec archive` + chaser PR + limpeza de branches + spec mirrors + canvas).

Se a implementação revelar problema de design, **pausar e atualizar os artefatos** — nunca contornar no código.

## Gates (não-negociáveis)

| Gate | Nome | Tipo | Regra |
|------|------|------|-------|
| **GATE 0** | Lookup obrigatório | Agente | Antes de criar/selecionar change, rode `basic-memory_search` + `basic-memory_recent_activity`. Em explore-stance especulativa é opcional mas recomendado. |
| **GATE 1** | Aprovar change | **Humano** | `/opsx-propose` gera proposal + design + tasks juntos. **PARE** e aguarde `aprovar` explícito. Não avance para apply sem esse sinal. |
| **GATE 2** | Validar + aprovar | Agente→Humano | `make test*` + `make lint` + `openspec validate`/`doctor` + `/opsx-verify-change` como fluxo contínuo. Relatório final → **PARE** e aguarde `aprovar`. CRITICAL/WARNING → corrija ANTES de pedir aprovação. |
| **GATE 3** | Review PR | **Humano** | `gh pr create` → revisão IA do diff → **PARE** e aguarde merge humano. Iterações pós-feedback reabrem o apply sem nova change. |
| **GATE 4** | Closeout verde | Agente | Antes de iniciar nova change, rode `./scripts/close-change.sh <ultima-change>` e exija saída verde (exit 0). Valida: tasks 100% `[x]`, `openspec validate`/`doctor`, working tree limpa, main sincronizada, PR merged, nota BM + índice + spec mirrors. **Uma change ativa por vez.** |

> Bootstrapping: changes que criam/modificam gates são isentas de GATE 4 na própria implementação.

## Ferramentas OpenSpec

```bash
openspec list                             # changes ativas
openspec status --change "<name>" --json  # estado dos artefatos
openspec instructions apply --change "<name>" --json   # instruções + contexto
openspec validate                         # valida raiz
openspec doctor                           # saúde das referências
openspec archive <name>                   # mergeia deltas e arquiva
```

Toda mudança vive em `openspec/changes/<change>/`:
- `proposal.md` — por que mudar (Why, What Changes, Capabilities, Impact)
- `design.md` — decisões técnicas, riscos, migration plan, Open Questions
- `tasks.md` — checklist de implementação (única task list). Suporta Spike: `- [ ] X.Y Spike: <pergunta> → decision em <arquivo>`
- `specs/**/*.md` — deltas de comportamento. **Cada capability no proposal DEVE ter spec delta**, a menos que `skip_specs: true` em `.openspec.yaml`.

Para tooling/docs sem mudança de produto, declare `skip_specs: true` e pule spec deltas.

## Targets Canônicos

`make lint` · `make lint-backend` · `make lint-frontend`
`make test` · `make test-backend` · `make test-backend-fast` · `make test-backend-integration` · `make test-frontend`
`make check` · `make format` · `make build` · `make typecheck` · `make security-scan`

## Convenções do Projeto

<!-- {{PROJECT_CONVENTIONS}} — substitua pelos valores reais do seu projeto. -->
- Linguagem: {{LANG_BACKEND}} (backend), {{LANG_FRONTEND}} (frontend)
- Gestor de pacotes: {{PKG_MANAGER_BACKEND}} (backend), {{PKG_MANAGER_FRONTEND}} (frontend)
- Framework: {{FRAMEWORK_BACKEND}} (backend), {{FRAMEWORK_FRONTEND}} (frontend)
- Framework de testes: {{TEST_FRAMEWORK_BACKEND}} (backend), {{TEST_FRAMEWORK_FRONTEND}} (frontend)
- Linter: {{LINTER_BACKEND}} (backend), {{LINTER_FRONTEND}} (frontend)
- Commit: Conventional Commits (pt-BR); nunca direto na main (hooks bloqueiam)
- Push seguro: `./scripts/push-safe.sh --fast` (desenv) / `--full` (pré-PR) / `--validate-only` (apenas schemas)
- Idioma: código em inglês; UI em pt-BR; artefatos OpenSpec, docs internas e PRs em pt-BR

## Registro de Decisões no Basic Memory

- **Quando**: após merge do PR, **antes** de rodar `close-change.sh`.
- **Título**: `Decisões Técnicas — <change-name>`, diretório `"/"`, `overwrite: true`.
- **Conteúdo**: resumo + decisões do `design.md` + artefatos + stack.
- **Relations** (seção fixa `## Relations`):
  - `implements: [[Spec — <capability>]]` — wiki link para spec mirror note
  - `depends_on: [[Decisões Técnicas — <change>]]` — pré-requisito hard
  - `relates_to: [[Decisões Técnicas — <change>]]` — conexão informativa
- **Índice**: nota `{{PROJECT_NAME_UPPER}}` (nome do projeto em CAIXA ALTA) na raiz com `[[wiki links]]` para todas as decisões técnicas.
- **Spec mirrors**: criadas automaticamente pelo `close-change.sh` — notas `Spec — <capability>` com `note_type: spec` e `source: openspec/specs/<capability>/spec.md`.

Detalhes completos em `dev-workflow.md §6` (archive e Basic Memory).

## Timeout de Comandos

| Tipo | Timeout |
|------|---------|
| Testes (`make test*`) | `600000` (10 min) |
| Commits (`git commit`) | `30000` (30s) |
| Rápidos (lint, status, format) | `30000` |

## Referências

- `dev-workflow.md` — playbook completo: checklists por fase, handover, troubleshooting, performance de testes, modos do push-safe, Basic Memory & Obsidian.
- `openspec/templates/explore-brief.md` — template que alimenta `proposal.md`.
- `openspec/config.yaml` — contexto do projeto + rules de artefatos.
- `.pre-commit-config.yaml` — hooks `block-main` (pre-commit) e `block-main-push` (pre-push).
- `.gitignore` — seção delimitada entre markers `# >>> maxdev-workflow-sync >>>` / `# <<< maxdev-workflow-sync <<<` é re-syncada. Custom acima/abaixo preservado.
- `.editorconfig` — UTF-8/LF/indent 4-Python-2-TS.

<!-- {{OPTIONAL_REFERENCES}} — adicione referências extras do seu projeto aqui (ex.: `TESTING.md`). -->