# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Fluxo de desenvolvimento

Este projeto segue o **workflow MaxDev OpenSpec** em 6 fases:
`explore → propose → apply → verify → PR → archive`.

- **Contrato operacional**: [`AGENTS.md`](./AGENTS.md)
- **Playbook completo**: [`dev-workflow.md`](./dev-workflow.md) — checklists
  por fase, handover entre sessões, performance de testes, troubleshooting.
- **Performance de testes**: [`TESTING.md`](./TESTING.md)

## Pré-requisitos

- [OpenSpec](https://www.npmjs.com/package/openspec) — CLI de spec-driven dev
- [opencode](https://opencode.ai) — CLI agéntica (skills `/opsx-*`)
- [pre-commit](https://pre-commit.com) — hooks locais (`block-main`, ruff)
- [Basic Memory](https://github.com/basicmachines-co/basic-memory) — knowledge base
- [Serena](https://github.com/oraios/serena) — LSP para o agente
- Python {{PKG_MANAGER_BACKEND}} · Node {{PKG_MANAGER_FRONTEND}}

## Comandos canônicos

```bash
make help                 # lista targets disponíveis
make test                 # todos os testes (backend + frontend)
make test-backend-fast    # iteração local (~30s)
make lint                 # todos os linters
make check                # lint + fast tests + validação (pré-push)

openspec list             # changes ativas
openspec validate         # valida raiz (specs/changes)
openspec doctor           # saúde das referências
./scripts/push-safe.sh --fast   # push seguro iteração
./scripts/close-change.sh <change>   # closeout pós-merge (GATE 5)
```

## Skills (invocadas via opencode)

- `/maxdev-workflow-sync` — bootstrap/sync/drift-check do workflow
- `/opsx-explore` → `/opsx-propose` → `/opsx-apply-change` →
  `/opsx-verify-change` → `close-change.sh`

## Primeira change (walk-through)

1. `/opsx-explore` — pensar no problema
2. `/opsx-propose` — criar artefatos em `openspec/changes/<change>/`
3. Aguardar **GATE 1** (aprovar proposal)
4. `/opsx-apply-change` — implementar tasks
5. Aguardar **GATE 2** (aprovar plano)
6. `./scripts/push-safe.sh --full && gh pr create` — abrir PR
7. Aguardar **GATE 4** (review humano + merge)
8. `./scripts/close-change.sh <change>` — closeout (GATE 5)

> Template gerado por `maxdev-workflow-sync` v{{WORKFLOW_VERSION}}.
> Edite os placeholders `{{...}}` e personalize conforme o projeto.