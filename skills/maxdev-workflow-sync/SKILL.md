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
        │   ├── AGENTS.md               ← template com placeholders
        │   ├── dev-workflow.md         ← template
        │   ├── scripts/close-change.sh ← copia como-is
        │   ├── scripts/push-safe.sh    ← copia como-is
        │   └── openspec/
        │       ├── config.yaml         ← template com placeholders + workflow_version
        │       └── templates/
        │           ├── explore-brief.md
        │           └── design.md
        └── references/
            └── merge-strategy.md       ← detalhes da estratégia dry-run+diff
```

## Reprodutibilidade cross-project

Para aplicar este workflow em outro projeto:
1. Rode `openspec init` no projeto novo
2. Rode `/maxdev-workflow-sync` (invoca a skill via plugin opencode). Para
   rodar o script manualmente, use o path resolvido da skill instalada (ex.:
   `bash $(opencode skill path maxdev-workflow-sync)/scripts/sync-workflow.sh --apply`,
   ou caminho direto bajo `~/.cache/opencode/packages/maxsyncai-opencode-skills@.../node_modules/maxsyncai-opencode-skills/skills/maxdev-workflow-sync/scripts/sync-workflow.sh`).
3. Edite os placeholders `{{...}}` em `AGENTS.md` e `openspec/config.yaml`
4. Rode `openspec validate` + `openspec doctor`

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
| Apply | `./sync-workflow.sh --apply` | Aplica sem confirmar |
| Drift check | `./sync-workflow.sh --check` | Reporta drift, não modifica |
| Force | `./sync-workflow.sh --force` | Sobrescreve mesmo se versão igual |

## Orquetrasção idempotente

- Primeiro run: copia defaults embutidos, adiciona `workflow_version: <v>` em `openspec/config.yaml`
- Segundo run (mesma versão): no-op (workflow_version == $WORKFLOW_VERSION) — a menos que `--force`
- Versão diferente: dry-run default, pede confirmação antes de atualizar
- Override local (opt-in, avançado): defina `EXTERNAL_OVERRIDES` apontando para
  um diretório local com os 7 canônicos (e opcional `workflow.version`) — útil
  para forks privados, ambientes air-gapped ou testes. Default: nada externo,
  skill self-contained em `assets/`.

## Placeholders a substituir no bootstrap

Após aplicar a skill num projeto novo, edite estes placeholders:

| Placeholder | Onde | Significado |
|---|---|---|
| `{{PROJECT_NAME}}` | AGENTS.md, config.yaml | Nome do projeto |
| `{{PROJECT_DESCRIPTION}}` | config.yaml | Descrição curta |
| `{{LANG_BACKEND}}`/`{{LANG_FRONTEND}}` | AGENTS.md, config.yaml | Linguagens |
| `{{FRAMEWORK_BACKEND}}`/`{{FRAMEWORK_FRONTEND}}` | config.yaml | Frameworks |
| `{{PKG_MANAGER_BACKEND}}`/`{{PKG_MANAGER_FRONTEND}}` | AGENTS.md, config.yaml | Package managers |
| `{{TEST_FRAMEWORK_BACKEND}}`/`{{TEST_FRAMEWORK_FRONTEND}}` | AGENTS.md, config.yaml | Test frameworks |
| `{{LINTER_BACKEND}}`/`{{LINTER_FRONTEND}}` | AGENTS.md, config.yaml | Linters |
| `{{DB}}` | config.yaml | Banco de dados |
| `{{INFRA}}` | config.yaml | Infra (Docker Compose, etc.) |
| `{{MAKE_TARGETS}}` | AGENTS.md | Targets canônicos do Makefile (lista) |
| `{{OPTIONAL_REFERENCES}}` | AGENTS.md | Referências extra (ex.: TESTING.md) |
| `{{PROJECT_SPECIFIC_NOTES}}` | config.yaml | Notas específicas do projeto |

## Detecção adaptativa a mudanças futuras do openspec

A skill **não assume** estrutura fixa do openspec upstream:
- `workflow_version` é chave canônica nossa (em `openspec/config.yaml`) — não depende do openspec
- Se uma versão futura do openspec renomear `openspec/changes/`, `openspec/specs/`, etc., a skill ainda copia os 7 arquivos canônicos nossos (que vivem em paths estáveis: `AGENTS.md`, `dev-workflow.md`, `scripts/`, `openspec/config.yaml`, `openspec/templates/`)
- Para changes de layout do openspec upstream, rode `/maxdev-workflow-sync --check` para detectar e adaptar

## Referências

Para detalhes da estratégia de merge (dry-run + diff), leia `references/merge-strategy.md`.
