# Merge Strategy — maxdev-workflow-sync

Detalhes da estratégia **dry-run + diff** adotada pela skill.

## Princípios

1. **Dry-run default**: o script nunca modifica sem confirmação explícita (a menos que `--apply` ou `--force`)
2. **Idempotente**: segundo run = no-op se `workflow_version` em `openspec/config.yaml` == `WORKFLOW_VERSION` em `assets/workflow.version`
3. **Backup implícito**: a skill nunca deleta arquivos existentes — só sobrescreve os 9 canônicos (AGENTS.md, dev-workflow.md, scripts/, openspec/config.yaml, openspec/templates/)
4. **Override local opcional** (`EXTERNAL_OVERRIDES`): se o usuário exportar
   `EXTERNAL_OVERRIDES=/path/para/dir-local` apontando para um diretório com os
   9 canônicos + starters (e opcional `workflow.version`), a skill usa esses arquivos como
   origem; se não, usa defaults embutidos em `assets/`. Sem auto-clone de repo
   externo — a skill é self-contained.

## Tratamento de conflitos por tipo de arquivo

| Tipo | Estratégia | Justificativa |
|---|---|---|
| `scripts/close-change.sh`, `scripts/push-safe.sh` | Sobrescreve | Scripts canônicos — não há motivo para customização por projeto |
| `openspec/templates/*.md` | Sobrescreve | Templates reference — idem |
| `openspec/config.yaml` | Dry-run + diff + confirm | Contém context específico do projeto (placeholders). A skill sobrescreve se drift detectado — o usuário revisa o diff antes |
| `AGENTS.md`, `dev-workflow.md` | Dry-run + diff + confirm | Mesma razão. Se o projeto tem customizações (ex.: seções extras), o usuário pode rejeitar a atualização e fazer merge manual |

## Quando não preserva customizações

A versão atual da skill **não** faz merge inteligente de seções customizadas do projeto dentro de `AGENTS.md`/`dev-workflow.md`. Quando há drift:

- O diff é exibido
- O usuário confirmar explicitamente (`y`) antes de sobrescrever
- Se quer preservar customizações, aborta (`N`) e faz merge manual git-style

**Racional**: merge de markdown é problema difícil (sem AST estável). Para a versão 1.0.0, optamos por simplicidade (dry-run + diff + confirm) em vez de merge automático frágil. Futuras versões podem adicionar merge semântico com marcação de blocos `<!-- MAXDEV:START -->` / `<!-- MAXDEV:END -->`.

## Recomendação para projetos com customizações

Se o projeto já tem `AGENTS.md` customizado e quer adotar o workflow MaxDev:

1. Faça backup: `cp AGENTS.md AGENTS.md.bak`
2. Rode: `./scripts/sync-workflow.sh` (dry-run)
3. Compare `AGENTS.md.bak` vs `AGENTS.md` da skill
4. Faça merge manual ou substitua se a customização for mínima
5. Atualize `workflow_version` em `openspec/config.yaml` manualmente

## Detecção de drift

O script compara `workflow_version` em `openspec/config.yaml` vs `assets/workflow.version`:

- **Igual**: drift check only (a menos que `--force`)
- **Diferente**: exibe diff de cada arquivo canônico, pede confirmação
- **Sem `workflow_version`** (projeto legado): bootstrap mode, copia tudo
