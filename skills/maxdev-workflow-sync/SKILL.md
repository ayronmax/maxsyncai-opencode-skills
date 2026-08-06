---
name: maxdev-workflow-sync
description: Bootstrap, sync or drift-check the MaxDev OpenSpec workflow in any repository. Use whenever setting up a new OpenSpec project, after upgrading the openspec package, when adopting the MaxDev workflow in another project, when seeing drift between workflow_version in openspec/config.yaml and the installed skill version, or when the user says "sync workflow", "bootstrap workflow", "check workflow drift", "reproduce maxdev workflow here", "instalar workflow", "aplicar workflow maxdev". Also use when initializing OpenSpec tooling in a fresh repo or wanting to enforce GATE 5 closeout pattern across projects. Do not use for upstream openspec commands (proposal, apply, verify, archive) — those are upstream skills.
license: MIT
---

# MaxDev Workflow Sync

Bootstrap, sincronização e drift-check do workflow MaxDev OpenSpec em qualquer repositório. Robusto, idempotente e reprodutível — copia só o **contrato** (não skills upstream).

## Quando usar

- Projeto novo: `openspec init` rodado, agora quer aplicar o workflow MaxDev (AGENTS.md + dev-workflow.md + scripts + templates)
- Após `npm install openspec@latest` ou `uv tool install -U openspec`: rode para detectar drift entre versão instalada e versão da skill
- Outro projeto: "quero reproduzir o workflow MaxDev aqui"
- Após edições locais que podem ter desynchronizado `workflow_version` em `openspec/config.yaml`

## Quando NÃO usar

- Para executar mudanças OpenSpec (proposal, apply, verify, archive) — use skills upstream `openspec-*`
- Para editar skills upstream OpenSpec — skills upstream NUNCA são editadas (preserva upgrade path)
- Para inicializar OpenSpec puro — rode `openspec init` primeiro, depois esta skill

## Arquitetura

```
maxsyncai-opencode-skills/              ← repo do package (raiz)
├── package.json
├── .opencode/
│   └── plugins/
│       └── maxsyncai-opencode-skills.js  ← entry: registra skills/ em config.skills.paths
└── skills/
    └── maxdev-workflow-sync/           ← esta skill
        ├── SKILL.md                    ← este contrato
        ├── scripts/sync-workflow.sh    ← orquestrador idempotente
        ├── assets/
        │   ├── workflow.version        ← WORKFLOW_VERSION (semver)
        │   ├── AGENTS.md               ← canônico (template com placeholders)
        │   ├── dev-workflow.md         ← canônico (template)
        │   ├── pre-commit-config.yaml  ← canônico (governança block-main/push)
        │   ├── scripts/close-change.sh ← canônico (copia como-is)
        │   ├── scripts/push-safe.sh    ← canônico (copia como-is)
        │   ├── .gitignore              ← canônico delimitado (markers; re-sync só o bloco)
        │   ├── openspec/
        │   │   ├── config.yaml         ← canônico (template + workflow_version)
        │   │   └── templates/
        │   │       ├── explore-brief.md
        │   │       └── design.md
        │   ├── opencode.example.json   ← starter (só ADD; MODIFY exige --force)
        │   ├── TESTING.md              ← starter (skeleton genérico)
        │   ├── Makefile.example        ← starter (stubs exit 1; renomeie p/ Makefile)
        │   ├── .editorconfig           ← starter (UTF-8/LF/indent 4-Python-2-TS)
        │   └── README.md              ← starter (seção "Fluxo de desenvolvimento")
        └── references/
            └── merge-strategy.md       ← detalhes da estratégia dry-run+diff
```

### Canônicos vs starters

- **Canônicos** (9 arquivos): formam o contrato sobrescrevível. Em `--apply`
  ou `--force`, o skill **clobber** o destino (preservando o `workflow_version`).
  Drift entre versão instalada e da skill é detectado e reportado.
  Inclui `.gitignore` com **markers delimitados** — ver "Sync de `.gitignore`".
- **Starters** (5 arquivos): pontapé inicial para o usuário customizar. Em
  `--apply` o skill só **cria se inexistente** — nunca clobber sem `--force`.
  Isso preserva customizações legadas (ex.: `Makefile` real não é tocado;
  `opencode.example.json` não substitui `opencode.json`).

### Sync de `.gitignore` (markers delimitados)

O `.gitignore` é canônico mas usa **bloco delimitado** entre markers:

```
# >>> maxdev-workflow-sync >>>
... (entries gerenciadas pela skill — re-sync substitui este bloco) ...
# <<< maxdev-workflow-sync <<<
```

Comportamento do sync (função B2):

| Estado do `.gitignore` | Ação |
|---|---|
| Inexistente | Cria com o bloco delimitado do template |
| Existente sem markers | Append do bloco delimitado (entries custom preservadas acima) |
| Existente com markers (par begin↔end) | Substitui só o bloco entre markers (entries custom acima/abaixo preservadas) |
| Existente com markers desbalanceados | Warning + skip (evita corrupção) |

Nunca clobbera entries custom do usuário fora do bloco delimitado.

## Reprodutibilidade cross-project

Para aplicar este workflow em outro projeto:
1. Rode `openspec init` no projeto novo
2. Rode `/maxdev-workflow-sync` (invoca a skill via plugin opencode). Para
   rodar o script manualmente, use o path resolvido da skill instalada (ex.:
   `bash $(opencode skill path maxdev-workflow-sync)/scripts/sync-workflow.sh --apply`,
   ou caminho direto bajo `~/.cache/opencode/packages/maxsyncai-opencode-skills@.../node_modules/maxsyncai-opencode-skills/skills/maxdev-workflow-sync/scripts/sync-workflow.sh`).
3. O pipeline pós-apply **automatiza** (ver "Pipeline pós-apply"):
   - Substitui `{{PROJECT_NAME}}` (slug do basename) e `{{PROJECT_ABSOLUTE_PATH}}` (cwd)
   - Cria/re-sync `.gitignore` com bloco delimitado (preserva entries custom)
   - Em bootstrap: cria `opencode.json` (renomeia `.example` com placeholders substituídos)
   - Roda `openspec validate` + `openspec doctor` (advisory, skip em CI/bootstrap)
   - Sanity check de tooling (openspec/gh/jq/python/node/pre-commit/etc)
   - Auto-instala hooks `pre-commit` + `pre-push` (guardado: skip em CI, alt managers, sem .git)
   - Heurística advisory de stack (lê pyproject/package.json, sugere mas não aplica)
4. Edite manualmente os placeholders restantes (stack-specific):
   - `AGENTS.md` (Targets canônicos, Convenções, Referências)
   - `openspec/config.yaml` (context, conventions)
   - `.pre-commit-config.yaml` (`{{LINTER_BACKEND_RUFF}}` / `{{LINTER_FRONTEND_ESLINT}}`)
   - `TESTING.md`, `Makefile.example` → renomeie p/ `Makefile`
   - `README.md`, `.editorconfig` — personalize
5. Rode `openspec validate` + `openspec doctor` + `make help`

Skills upstream OpenSpec são instaladas separadamente via package manager — não copiadas por esta skill.

## Instruções operacionais (rotear o script)

Sempre que esta skill for invocada, rode o script `scripts/sync-workflow.sh`
relativo ao diretório da skill (auto-resolvido pelo `SKILL_DIR` interno do
próprio script):

```bash
# via plugin (recomendado): /maxdev-workflow-sync
# manual: bash <skill_dir>/scripts/sync-workflow.sh
bash "$(dirname "$0")/scripts/sync-workflow.sh"  # se $0 = SKILL.md da skill
```

Modos:

| Modo | Comando | O que faz |
|---|---|---|
| Dry-run (default) | `./sync-workflow.sh` | Gera diff, pede confirmação |
| Apply | `./sync-workflow.sh --apply` | Aplica sem confirmar + roda pipeline pós-apply |
| Drift check | `./sync-workflow.sh --check` | Reporta drift, não modifica (read-only) |
| Force | `./sync-workflow.sh --force` | Sobrescreve mesmo se versão igual |

Flags opt-out do pipeline pós-apply (todas default ON — adaptativas, advisory):

| Flag | Skipa |
|---|---|
| `--no-install-hooks` | auto-install de hooks pre-commit (use `--install-hooks` para forçar mesmo em CI) |
| `--no-validate` | `openspec validate` + `openspec doctor` |
| `--no-tools-check` | sanity check de tooling (openspec/gh/jq/python/node/pre-commit/etc) |
| `--no-stack-suggest` | heurística advisory de stack (lê pyproject/package.json; **não aplica**) |
| `--no-gitignore-sync` | sync delimitado de `.gitignore` (escape raro) |
| `--no-auto-opencode` | criação de `opencode.json` em bootstrap (renomeie `.example` manualmente) |
| `--no-derivable-placeholders` | substituição de `{{PROJECT_NAME}}` / `{{PROJECT_ABSOLUTE_PATH}}` |

`--help` exibe o usage embutido. Flags combinam livremente.

## Pipeline pós-apply

Após copiar canônicos + starters + atualizar `workflow_version` em `openspec/config.yaml`,
o script roda **8 etapas** (somente em `--apply`/`--force` — nunca em `--check`).
Todas são **guardadas advisory**: falhas nunca abortam o sync, só reportam.

```
1. Substitui {{WORKFLOW_VERSION}} em templates (canônicos + starters)
2. A2: substitui {{PROJECT_NAME}} (slug via basename) e {{PROJECT_ABSOLUTE_PATH}} (cwd)
3. B2: sync .gitignore delimitado (markers — ver "Sync de .gitignore")
4. A3: em bootstrap (opencode.json inexistente), cria opencode.json do .example já com placeholders substituídos
5. A1: openspec validate + openspec doctor (skip em CI/bootstrap)
6. B3: sanity check de tooling (detecção em 2 tiers — binário direto no PATH OU fallback `uvx` para tools como serena invocadas via `uvx --from git+…`)
7. Hooks: auto-install pre-commit + pre-push (skip em CI, alt managers, sem .git)
8. C1: heurística advisory de stack (pyproject/package.json; NÃO aplica — só sugere)
```

Guards automáticos (sem flag explícita):

| Guard | Skipa |
|---|---|
| `CI=true`/`GITHUB_ACTIONS`/`GITLAB_CI`/etc | A1 (sem ganho em CI), B3 (sem latência extra), Hooks (sem necessidade em CI) |
| `.git/` inexistente | Hooks (advisory "rode `git init`") |
| `.husky/` / `lefthook.yml` / `.simple-git-hooks` detectado | Hooks (preserva manager alternativo) |
| `pre-commit` ausente no PATH | Hooks (advisory com install hint) |
| Bootstrap (sem `openspec/config.yaml`) | A1 (rode `openspec init` primeiro) |

## Orquetrasção idempotente

- Primeiro run: copia defaults embutidos, adiciona `workflow_version: <v>` em `openspec/config.yaml`
- Segundo run (mesma versão): no-op (workflow_version == $WORKFLOW_VERSION) — a menos que `--force`
- Versão diferente: dry-run default, pede confirmação antes de atualizar
- Override local (opt-in, avançado): defina `EXTERNAL_OVERRIDES` apontando para
  um diretório local com os 9 canônicos + starters (e opcional `workflow.version`)
  — útil para forks privados, ambientes air-gapped ou testes. Default: nada
  externo, skill self-contained em `assets/`.

## Placeholders a substituir no bootstrap

Após aplicar a skill num projeto novo, edite estes placeholders. Eles se
dividem em 3 categorias por substituição:

### Auto-substituídos pelo script (A2)

Determinísticos, derivados do cwd — substituídos em todos os arquivos copiados.

| Placeholder | Origem | Significado |
|---|---|---|
| `{{WORKFLOW_VERSION}}` | `assets/workflow.version` | Versão da skill (auto) |
| `{{PROJECT_NAME}}` | `basename $PROJECT_ROOT` (slug via `slugify_name`) | Nome/slug compatível com Basic Memory |
| `{{PROJECT_ABSOLUTE_PATH}}` | `$PROJECT_ROOT` (cwd) | Path absoluto da raiz do projeto |

### Auto-substituídos em pipeline advisory (C1)

A heurística C1 só **sugere** valores lidos de `pyproject.toml`/`package.json`;
**não aplica** — revise e substitua manualmente nos arquivos.

| Placeholder | Onde | Significado |
|---|---|---|
| `{{LANG_BACKEND}}`/`{{LANG_FRONTEND}}` | AGENTS.md, config.yaml, README.md | Linguagens |
| `{{FRAMEWORK_BACKEND}}`/`{{FRAMEWORK_FRONTEND}}` | config.yaml | Frameworks |
| `{{PKG_MANAGER_BACKEND}}`/`{{PKG_MANAGER_FRONTEND}}` | AGENTS.md, config.yaml, Makefile.example, README.md | Package managers |
| `{{TEST_FRAMEWORK_BACKEND}}`/`{{TEST_FRAMEWORK_FRONTEND}}` | AGENTS.md, config.yaml, TESTING.md, Makefile.example | Test frameworks |
| `{{LINTER_BACKEND}}`/`{{LINTER_FRONTEND}}` | AGENTS.md, config.yaml, Makefile.example | Linters |
| `{{LINTER_BACKEND_RUFF}}`/`{{LINTER_FRONTEND_ESLINT}}` | .pre-commit-config.yaml | Descomentar blocos ruff/eslint conforme stack |

### Manuais (não-deduzíveis)

| Placeholder | Onde | Significado |
|---|---|---|
| `{{PROJECT_DESCRIPTION}}` | config.yaml, README.md | Descrição curta |
| `{{LANG_VERSION}}` | config.yaml | Versão da linguagem |
| `{{DB}}` | config.yaml | Banco de dados |
| `{{INFRA}}` | config.yaml | Infra (Docker Compose, etc.) |
| `{{MAKE_TARGETS}}` | AGENTS.md | Targets canônicos do Makefile (lista) |
| `{{OPTIONAL_REFERENCES}}` | AGENTS.md | Referências extra (ex.: TESTING.md) |
| `{{PROJECT_SPECIFIC_NOTES}}` | config.yaml | Notas específicas do projeto |

## Detecção adaptativa a mudanças futuras do openspec

A skill **não assume** estrutura fixa do openspec upstream:
- `workflow_version` é chave canônica nossa (em `openspec/config.yaml`) — não depende do openspec
- Se uma versão futura do openspec renomear `openspec/changes/`, `openspec/specs/`, etc., a skill ainda copia os 9 arquivos canônicos nossos (que vivem em paths estáveis: `AGENTS.md`, `dev-workflow.md`, `scripts/`, `openspec/config.yaml`, `openspec/templates/`, `.pre-commit-config.yaml`, `.gitignore`)
- Para changes de layout do openspec upstream, rode `/maxdev-workflow-sync --check` para detectar e adaptar

## Referências

Para detalhes da estratégia de merge (dry-run + diff), leia `references/merge-strategy.md`.
