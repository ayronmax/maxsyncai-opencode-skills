# maxdev-workflow-sync — Guia de Uso

Bootstrap, sincronização e drift-check do workflow **MaxDev OpenSpec** em qualquer
repositório. Idempotente, reprodutível, copia só o **contrato** (não skills upstream).

> Este README é o **guia de uso**. O contrato formal vive em `SKILL.md`; detalhes
> técnicos do merge em `references/merge-strategy.md`.

## 1. Sumário

1. [O que a skill faz](#2-o-que-a-skill-faz)
2. [Repositórios em jogo](#3-repositórios-em-jogo)
3. [Pré-requisitos](#4-pré-requisitos)
4. [Modos & flags](#5-modos--flags)
5. [Cenários de uso](#6-cenários-de-uso)
6. [Override local via `EXTERNAL_OVERRIDES` (opt-in)](#7-override-local-via-external_overrides-opt-in)
7. [Autoria & manutenção dos templates](#8-autoria--manutenção-dos-templates)
8. [Placeholders a substituir no bootstrap](#9-placeholders-a-substituir-no-bootstrap)
9. [Verificação pós-sync](#10-verificação-pós-sync)
10. [Troubleshooting](#11-troubleshooting)
11. [Estrutura dos repositórios](#12-estrutura-dos-repositórios)
12. [Glossário](#13-glossário)
13. [Changelog](#14-changelog)

---

## 2. O que a skill faz

Copia **9 canônicos + 5 starters** que definem o workflow MaxDev para a raiz do
projeto-alvo. A skill também executa um **pipeline pós-apply** guardado de 8
etapas (validação, sanity check, hooks, heurística de stack) e suporta **flags
opt-out** para cada etapa.

### Canônicos (clobber em `--apply`/`--force`)

| Arquivo | Natureza |
|---|---|
| `AGENTS.md` | Contrato operacional (gates, fases, MCPs por fase) |
| `dev-workflow.md` | Playbook completo (checklists, handover, troubleshooting) |
| `scripts/close-change.sh` | Orquestra archive + chaser PR + limpeza de branches |
| `scripts/push-safe.sh` | Push seguro (`--fast`/`--full`/`--validate-only`) |
| `openspec/config.yaml` | Contexto do projeto + `workflow_version` (semver nosso) |
| `openspec/templates/explore-brief.md` | Template que alimenta `proposal.md` |
| `openspec/templates/design.md` | Template de design com `## Open Questions` |
| `.pre-commit-config.yaml` | Governança `block-main`/`block-main-push` (reforça GATE 4) |
| `.gitignore` | Bloco delimitado entre markers (preserva entries custom; source no asset é `gitignore.template` — sem dot para escapar blacklist npm) |

### Starters (ADD-only; sobrescreve só com `--force`)

| Arquivo | Natureza |
|---|---|
| `opencode.example.json` | Só MCPs project-scoped + comentário dos globais |
| `TESTING.md` | Skeleton genérico de performance/isolamento |
| `Makefile.example` | Stubs `exit 1` (renomeie p/ `Makefile` e implemente) |
| `.editorconfig` | UTF-8/LF/indent 4-Python-2-TS-JSON-MD |
| `README.md` | Seção "Fluxo de desenvolvimento" como walk-through primeira change |

Skills upstream OpenSpec (`openspec-propose`, `openspec-apply-change`, etc.) **não
são copiadas** — são instaladas à parte via package manager. Esta skill só
distribui o **contrato MaxDev** (camada acima do openspec puro).

---

## 3. Repositórios em jogo

Esta skill envolve **3 entidades distintas**. Confundi-las é a principal fonte de
dúvida — por isso o panorama antes de detalhar:

| # | Entidade | Onde vive | Função | Obrigatória? |
|---|---|---|---|---|
| 1 | **Repo da skill (package)** | Repo que distribui o package (`maxsyncai-opencode-skills`, carrega `skills/maxdev-workflow-sync/`) | Fonte canônica da skill: `SKILL.md`, `scripts/sync-workflow.sh`, `assets/` (templates embutidos como defaults) | Sim |
| 2 | **Override local** (opt-in) | Diretório local apontado via `EXTERNAL_OVERRIDES` (env var) | Override dos 9 canônicos para forks/air-gapped/testes. Default: não usado — skill é self-contained em `assets/` | Não (opcional, avançado) |
| 3 | **Projeto-alvo** | Qualquer repo que adota o workflow MaxDev | Recebe os 9 canônicos + 5 starters na raiz após `--apply` | Sim (é o destino) |

**Relação**: o script `sync-workflow.sh` (entidade 1) lê da entidade 2 (se
explicitamente setado via env) ou do `assets/` embutido (default), e copia os arquivos
para a raiz da entidade 3.

**Dois repos distintos por design**: o package (entidade 1) e o projeto-alvo
(entidade 3) vivem em repos separados desde que a skill virou plugin opencode.
`skills/maxdev-workflow-sync/assets/` no package tem TEMPLATES; a raiz do
projeto-alvo tem arquivos VIVOS — não coexistem no mesmo git. Ver
[§12.5 Dualidade: vivo vs template](#125-dualidade-vivo-vs-template).

---

## 4. Pré-requisitos

- **OpenSpec inicializado** no projeto-alvo: rode `openspec init` antes.
- `bash`, `git`, ferramentas básicas Unix.
- (Opcional) `openspec` no PATH para validação pós-sync (`openspec validate` /
  `openspec doctor`).

Sem `openspec init`, a skill ainda copia os arquivos, mas `openspec validate`
vai falhar — faça o init primeiro.

---

## 5. Modos & flags

Roteie sempre o script `scripts/sync-workflow.sh`. Path depende de onde a
skill está instalada:

- **Via plugin** (recomendado): invocar `/maxdev-workflow-sync` no opencode —
  o agente resolve o path internamente.
- **Manual**: descubra o diretório da skill instalada (ex.: em
  `~/.cache/opencode/packages/maxsyncai-opencode-skills@.../node_modules/maxsyncai-opencode-skills/skills/maxdev-workflow-sync/`)
  e rode:

```bash
bash <skill_dir>/scripts/sync-workflow.sh [modo] [flags...]
```

> **⚠ `PROJECT_ROOT`** — o script usa `PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"`
> (`sync-workflow.sh:35`). Ou seja, **age no diretório atual** se a variável
> não for exportada. Se você roda o script manualmente de fora do projeto-alvo
> (ex.: no diretório da própria skill, num scratch, ou via symlink),
> **sempre exporte `PROJECT_ROOT` apontando para o destino**:
>
> ```bash
> PROJECT_ROOT=/home/usuario/projetos/alvo \
>   bash <skill_dir>/scripts/sync-workflow.sh --apply
> ```
>
> Sem isso, o script copia os arquivos canônicos para o diretório atual —
> podendo sobrescrever arquivos do projeto errado. Isto é comportamento
> documentado (não bug), mas é a principal pegadinha operacional desta skill.
>
> Dica: se você invoca a skill via `/maxdev-workflow-sync` no opencode, o
> `cwd` do agente normalmente já é o projeto-alvo — nesse caso `pwd` resolve
> corretamente e você não precisa exportar nada. O cuidado extra vale só
> quando roda o script manualmente fora do agente.

### 5.1 Semântica MODE × FORCE (v1.2.4+)

MODE (read-write) e FORCE (modifier) são variáveis ortogonais. **A ordem dos
args não altera a semântica**:

| Args | MODE | FORCE | Resultado |
|---|---|---|---|
| `--apply` | apply | false | Aplica drift. Se versão instalada == skill: demote p/ check + aviso explícito |
| `--check` | check | false | **Read-only** garantido (--force não destrava escrita) |
| `--force` | apply | true | Alias `--apply --force`: aplica mesmo se versão igual, re-aplica starters |
| `--check --force` | check | false | ≡ `--check` + warning `⚠ --force ignorado` |

### 5.2 Flags opt-out do pipeline pós-apply

O pipeline pós-apply (8 etapas guardadas) roda automaticamente em `--apply`/
`--force`. Flags para desabilitar seletivamente:

| Flag | Skipa |
|---|---|
| `--no-install-hooks` | Auto-install de hooks pre-commit (`--install-hooks` força mesmo em CI) |
| `--no-validate` | `openspec validate` + `openspec doctor` |
| `--no-tools-check` | Sanity check de tooling |
| `--no-stack-suggest` | Heurística de stack (lê pyproject/package.json; NÃO aplica) |
| `--no-gitignore-sync` | Sync delimitado de `.gitignore` |
| `--no-auto-opencode` | Criação de `opencode.json` em bootstrap |
| `--no-derivable-placeholders` | Substituição de `{{PROJECT_NAME}}` / `{{PROJECT_ABSOLUTE_PATH}}` |

### 5.3 Idempotência

- Segundo run com **mesma versão** → drift check (no-op em escrita a menos que `--force`).
- Versão **diferente** → dry-run default, pede confirmação.
- **Sem `workflow_version`** em `openspec/config.yaml` (bootstrap) → copia todos os templates.

---

## 6. Cenários de uso

### 6.1 Bootstrap num projeto novo

```bash
cd ~/projetos/meu-projeto
openspec init                                    # 1. init OpenSpec puro
# 2. invoque a skill:
#    via opencode: /maxdev-workflow-sync
#    via CLI:      bash <skill_dir>/scripts/sync-workflow.sh --apply
# 3. edite placeholders {{...}} em AGENTS.md e openspec/config.yaml
# 4. valide
openspec validate
openspec doctor
```

> Via `/maxdev-workflow-sync` no opencode: `cwd` do agente já é o projeto-alvo,
> então o `pwd` implícito resolve. Rodando manualmente de outro diretório:
> prefixe `PROJECT_ROOT=/path/alvo`.

### 6.2 Drift-check após `openspec@latest`

```bash
# via skill: /maxdev-workflow-sync --check
# via CLI:
bash <skill_dir>/scripts/sync-workflow.sh --check
# se drift detectado:
bash <skill_dir>/scripts/sync-workflow.sh   # dry-run + diff
```

### 6.3 Adotar o workflow MaxDev noutro projeto

```bash
cd ~/projetos/meu-projeto
openspec init
# /maxdev-workflow-sync ou:
bash <skill_dir>/scripts/sync-workflow.sh --apply
# edite placeholders → valide → comite
```

### 6.4 Re-aplicar forçado (debug)

```bash
bash <skill_dir>/scripts/sync-workflow.sh --force
```

### 6.5 Rodar a partir de outro diretório (não o projeto-alvo)

Quando a skill vive num package compartilhado e você quer aplicá-la num
projeto sem `cd` nele:

```bash
PROJECT_ROOT=/home/usuario/projetos/alvo \
  bash /path/para/skill/scripts/sync-workflow.sh --apply
# OU, override local do template:
PROJECT_ROOT=/home/usuario/projetos/alvo \
EXTERNAL_OVERRIDES=/path/para/template-local \
  bash /path/para/skill/scripts/sync-workflow.sh --apply
```

Sem `PROJECT_ROOT` explícito, o script age no `pwd` atual — risco real de
sobrescrever arquivos no diretório errado. Use sempre que estiver fora do
projeto-alvo.

---

## 7. Override local via `EXTERNAL_OVERRIDES` (opt-in)

A skill é **self-contained** — todos os 9 canônicos + 5 starters vivem em `assets/`
dentro do package. Não há dependência de repo externo nem auto-clone via rede.

Para casos avançados (fork privado do template, ambientes air-gapped, testes
locais antes de bump de package), você pode **override localmente** apontando
uma pasta via env var:

```bash
EXTERNAL_OVERRIDES=/path/para/meu-template-local \
  bash <skill_dir>/scripts/sync-workflow.sh --apply
```

### 7.1 Como funciona

1. O script verifica se `EXTERNAL_OVERRIDES` está setado e aponta para
   diretório válido (`sync-workflow.sh:40-44`). Se não setado → usa `assets/`.
2. Para cada arquivo canônico, se `$EXTERNAL_OVERRIDES/<arquivo>` existir,
   usa ele como origem; senão cai em `assets/<arquivo>` (override **per-file**,
   não tudo-ou-nada).
3. `workflow.version` segue a mesma precedência: se
   `$EXTERNAL_OVERRIDES/workflow.version` existir, override; senão
   `assets/workflow.version` (default da skill instalada).

### 7.2 Estrutura esperada do diretório de override

```
meu-template-local/
├── workflow.version         ← opcional; se publicado, override assets/workflow.version
├── AGENTS.md                ← opcional (se ausente, cai em assets/)
├── dev-workflow.md          ← idem
├── scripts/
│   ├── close-change.sh      ← idem
│   └── push-safe.sh         ← idem
└── openspec/
    ├── config.yaml          ← idem
    └── templates/
        ├── explore-brief.md
        └── design.md
```

Atalho para gerar a árvore a partir de `assets/`:

```bash
mkdir meu-template-local && cd meu-template-local
mkdir -p scripts openspec/templates
SKILL_DIR=<skill_dir>/skills/maxdev-workflow-sync
cp $SKILL_DIR/assets/AGENTS.md $SKILL_DIR/assets/dev-workflow.md .
cp $SKILL_DIR/assets/scripts/*.sh scripts/
cp $SKILL_DIR/assets/openspec/config.yaml openspec/
cp $SKILL_DIR/assets/openspec/templates/*.md openspec/templates/
cp $SKILL_DIR/assets/workflow.version .
# ajuste conforme necessário, comite no seu fork privado
```

### 7.3 Ordem de precedência (por arquivo)

```
1. EXTERNAL_OVERRIDES/<arquivo>  (env, explícito, se existir)  ← mais forte
2. assets/<arquivo>              (default embutido no package)  ← fallback que sempre existe

   (workflow.version: precedência idêntica — 1 > 2)
```

### 7.4 Quando NÃO usar override

- **Default**: não defina `EXTERNAL_OVERRIDES`. A skill funciona offline,
  sem rede, sem depender de GitHub. Único requisito: ter o package instalado
  via `~/.config/opencode/opencode.jsonc`.
- **Bump de versão**: faça no package (`assets/workflow.version` + commit + tag),
  não via override. Override é para experimentação local, não para
  distribuir versão — para distribuir, bump o package.
- **Atualizar conteúdo dos 9 canônicos + 5 starters**: edite `assets/` no repo do package,
  commit, push, tag. Projetos detectam drift no próximo `--check`.

---

## 8. Autoria & manutenção dos templates

### 8.1 Quem cria `AGENTS.md` e `dev-workflow.md` no projeto-alvo

A **própria skill**, via `sync-workflow.sh`, copia de `assets/AGENTS.md` e
`assets/dev-workflow.md` para a raiz do projeto. Esses arquivos em `assets/` **são
templates com placeholders `{{...}}`** — não cópias verbatim de um projeto concreto.

#### Fluxo

```
assets/AGENTS.md        ─┐
assets/dev-workflow.md   │  sync-workflow.sh --apply
assets/openspec/...      │  →  copia para raiz do projeto-alvo
assets/scripts/...      │  →  usuário edita {{...}}
                         ┘
```

Após copiar, o script imprime:

```
ℹ Bootstrap completo. Edite os placeholders {{...}} em:
    - AGENTS.md (seções Targets canônicos, Convenções, Referências)
    - openspec/config.yaml (context, conventions)
```

A substituição dos placeholders stack-specific é **manual** (os deriváveis — PROJECT_NAME, PROJECT_ABSOLUTE_PATH, WORKFLOW_VERSION — são auto-substituídos pela própria skill)
após rodar a skill. A skill não faz substituição automática — só copia o template
e te avisa. **Auto-substituídos**: `{{WORKFLOW_VERSION}}`, `{{PROJECT_NAME}}`, `{{PROJECT_ABSOLUTE_PATH}}` (ver
[§9](#9-placeholders-a-substituir-no-bootstrap)).

### 8.2 Quem mantém os templates

Os templates em `assets/` são mantidos por quem mantém a skill (quem distribui
o package). Quando evoluir o workflow MaxDev:

1. Edite os `assets/` (especialmente `AGENTS.md` e `dev-workflow.md`)
2. Bump `assets/workflow.version` (semver)
3. Redistribua a skill (commit/push no package)
4. Projetos que rodarem `sync-workflow.sh --check` verão drift e poderão sincronizar

**Não** edite `assets/AGENTS.md` confundindo com o `AGENTS.md` "real"
do projeto — o da raiz do projeto é derivado do template (já com placeholders
substituídos pelos valores reais do projeto), o de `assets/` é o template
genérico. Ver [§12.5 Dualidade](#125-dualidade-vivo-vs-template).

### 8.3 Override local como alternativa aos `assets/` (avançado)

Para experimentação local (sem redistribuir package), use
`EXTERNAL_OVERRIDES` apontando para um diretório local com os 9 canônicos + 5 starters.
A skill puxa dele se setado; senão, cai em `assets/`. Ver
[§7 Override local](#7-override-local-via-external_overrides-opt-in).

---

## 9. Placeholders a substituir no bootstrap

Após `--apply` num projeto novo, edite os `{{...}}`. Dividem-se em 3 categorias:

### Auto-substituídos pelo script (A2)

Determinísticos, derivados do cwd — substituídos automaticamente.

| Placeholder | Origem |
|---|---|
| `{{WORKFLOW_VERSION}}` | `assets/workflow.version` |
| `{{PROJECT_NAME}}` | `basename $PROJECT_ROOT` (slug via `slugify_name`) |
| `{{PROJECT_ABSOLUTE_PATH}}` | `$PROJECT_ROOT` (cwd) |

### Auto-substituídos em pipeline advisory (C1) — só sugere, não aplica

Heurística lê `pyproject.toml`/`package.json` e **sugere** (não aplica).

| Placeholder | Onde aparece |
|---|---|
| `{{LANG_BACKEND}}` / `{{LANG_FRONTEND}}` | AGENTS.md, config.yaml, README.md |
| `{{FRAMEWORK_BACKEND}}` / `{{FRAMEWORK_FRONTEND}}` | config.yaml |
| `{{PKG_MANAGER_BACKEND}}` / `{{PKG_MANAGER_FRONTEND}}` | AGENTS.md, config.yaml, Makefile.example, README.md |
| `{{TEST_FRAMEWORK_BACKEND}}` / `{{TEST_FRAMEWORK_FRONTEND}}` | AGENTS.md, config.yaml, TESTING.md, Makefile.example |
| `{{LINTER_BACKEND}}` / `{{LINTER_FRONTEND}}` | AGENTS.md, config.yaml, Makefile.example |
| `{{LINTER_BACKEND_RUFF}}` / `{{LINTER_FRONTEND_ESLINT}}` | .pre-commit-config.yaml |

### Manuais (não-deduzíveis)

| Placeholder | Onde aparece |
|---|---|
| `{{PROJECT_DESCRIPTION}}` | config.yaml, README.md |
| `{{LANG_VERSION}}` | config.yaml |
| `{{DB}}` | config.yaml |
| `{{INFRA}}` | config.yaml |
| `{{MAKE_TARGETS}}` | AGENTS.md |
| `{{OPTIONAL_REFERENCES}}` | AGENTS.md |
| `{{PROJECT_CONVENTIONS}}` | AGENTS.md |
| `{{PROJECT_SPECIFIC_NOTES}}` | config.yaml |

---

## 10. Verificação pós-sync

Sempre rode depois de aplicar mudanças:

```bash
openspec validate       # valida raiz (specs/changes)
openspec doctor         # saúde das referências
git diff                  # revise o que foi sobrescrito
```

Para projetos com customizações em `AGENTS.md`/`dev-workflow.md`: **sempre use
dry-run default**, revise o diff, aborte (`N`) e faça merge manual git-style se
precisar preservar seções customizadas. Veja `references/merge-strategy.md`.

---

## 11. Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| `✗ workflow.version não encontrado` | Skill corrompida / path errado | Verifique `assets/workflow.version`; rode do diretório certo |
| `openspec validate` falha após sync | `openspec init` não rodou | Rode `openspec init` primeiro |
| Drift detectado mas diff vazio | Arquivos novos (ADD) não mostram diff | Normal — `ADD` não tem diff, só `MODIFY` |
| Script não puxa do repo externo | Sem rede, repo privado, ou não existe | Default: usa `assets/`. Defina `EXTERNAL_OVERRIDES` ou torne o repo acessível |
| `--force` sobrescreveu customizações | Esqueceu de fazer backup | `git checkout -- AGENTS.md` se ainda não comitou; da próxima, dry-run |
| `workflow_version` não atualiza | `openspec/config.yaml` sem a chave | Script adiciona ao final do arquivo automaticamente |
| Agente sobrescreveu arquivos do projeto errado | Script rodou com `pwd` num diretório que não é o alvo | Sempre exporte `PROJECT_ROOT=/path/alvo` quando rodar fora do projeto-alvo; se já aconteceu, `git checkout -- AGENTS.md dev-workflow.md openspec/config.yaml scripts/close-change.sh` no projeto afetado |
| `workflow_version:` duplicado em `openspec/config.yaml` | Versão antiga da skill + template com chave hardcoded | Atualize a skill (>=1.0.1) — template atualizado e lógica de sed/append robusta |

---

## 12. Estrutura dos repositórios

### 12.1 Diagrama: package + override local + projeto-alvo

```
┌──────────────────────────────┐         ┌───────────────────────────────┐
│ 1. Repo da skill (package)   │         │ 2. Override local (opt-in)     │
│ maxsyncai-opencode-skills     │         │ EXTERNAL_OVERRIDES=/path/dir   │
│                              │         │                               │
│ skills/maxdev-workflow-sync/ │         │ AGENTS.md (opcional)           │
│ ├── SKILL.md                 │         │ dev-workflow.md (opcional)      │
│ ├── README.md                │         │ scripts/*.sh (opcional)         │
│ ├── scripts/                 │         │ openspec/config.yaml (opcional)│
│ │   └── sync-workflow.sh     │         │ openspec/templates/*.md        │
│ ├── assets/ ← defaults       │         │ workflow.version (opcional)    │
│ │   ├── workflow.version     │         │                               │
│ │   ├── AGENTS.md (template) │         │ Override POR ARQUIVO:          │
│ │   └── ...                  │         │ se ausente → cai em assets/    │
│ └── references/              │         │ Default: não usado              │
└──────────────┬───────────────┘         └─────────────────┬─────────────┘
               │                                          │
               │   sync-workflow.sh --apply               │
               │   (precedência: 1 > 2)                    │
               ▼                                          ▼
        ┌─────────────────────────────────────────────────────┐
        │ 3. Projeto-alvo (qualquer repo)                    │
        │                                                   │
        │ AGENTS.md            ← copiado + {{...}} editados   │
        │ dev-workflow.md      ← copiado                     │
        │ scripts/close-change.sh ← copiado                  │
        │ scripts/push-safe.sh   ← copiado                   │
        │ openspec/config.yaml  ← copiado + workflow_version  │
        │ openspec/templates/   ← copiado                    │
        └─────────────────────────────────────────────────────┘
```

**Ordem de precedência em runtime** (para cada arquivo canônico):

```
EXTERNAL_OVERRIDES/<arquivo> (env explícito, se existir)
        │  não definido OU arquivo ausente
        ▼
assets/<arquivo> embutido no package  ← fallback que SEMPRE existe
```

### 12.2 Árvore: Repo da skill (entidade 1)

Carrega a skill completa como package opencode. Tudo vai no git do repo que
distribui o package:

```
maxsyncai-opencode-skills/              ← repo do package (raiz)
├── package.json
├── LICENSE
├── README.md                              ← README do package (instalação)
├── .opencode/
│   └── plugins/
│       └── maxsyncai-opencode-skills.js   ← entry: registra skills/ em config.skills.paths
└── skills/
    └── maxdev-workflow-sync/              ← ESTA skill
        ├── SKILL.md                       ← contrato (description, when/when-not)
        ├── README.md                      ← este guia de uso
        ├── scripts/
        │   └── sync-workflow.sh           ← orquestrador idempotente
        ├── assets/                        ← defaults embutidos (FALLBACK)
        │   ├── workflow.version           ← WORKFLOW_VERSION (semver, atual: 1.0.2)
        │   ├── AGENTS.md                  ← template com placeholders {{...}}
        │   ├── dev-workflow.md            ← template
        │   ├── scripts/
        │   │   ├── close-change.sh        ← cópia como-is
        │   │   └── push-safe.sh           ← cópia como-is
        │   └── openspec/
        │       ├── config.yaml            ← template (sem workflow_version hardcoded)
        │       └── templates/
        │           ├── explore-brief.md
        │           └── design.md
        └── references/
            └── merge-strategy.md          ← detalhes técnicos do merge dry-run+diff
```

### 12.3 Árvore: Override local (entidade 2, opt-in)

Diretório local apontado via `EXTERNAL_OVERRIDES` (env var). Não é repo — é
um diretório no filesystem. Contém **somente** arquivos que você quer
override; ausentes caem em `assets/`. **Não tem** `SKILL.md`, `README.md`,
`scripts/sync-workflow.sh`, `assets/`, `references/`:

```
meu-template-local/                       ← $EXTERNAL_OVERRIDES
├── AGENTS.md                              ← override (opcional)
├── dev-workflow.md                        ← override (opcional)
├── scripts/
│   ├── close-change.sh                    ← override (opcional)
│   └── push-safe.sh                       ← override (opcional)
├── openspec/
│   ├── config.yaml                        ← override (opcional)
│   └── templates/
│       ├── explore-brief.md              ← override (opcional)
│       └── design.md                     ← override (opcional)
└── workflow.version                       ← override (opcional, desde v1.0.3)
```

Ver [§7](#7-override-local-via-external_overrides-opt-in) para casos de uso
(forks privados, air-gapped, testes locais).

### 12.4 Árvore: Projeto-alvo (entidade 3)

Qualquer repo que adota o workflow. Recebe os canônicos + starters na raiz após `--apply`:

```
<projeto-alvo>/
├── AGENTS.md                      ← VIVO (valores reais, sem {{...}})
├── dev-workflow.md                ← VIVO
├── scripts/
│   ├── close-change.sh            ← VIVO
│   └── push-safe.sh               ← VIVO
└── openspec/
    ├── config.yaml                ← VIVO (com workflow_version: X.Y.Z)
    └── templates/
        ├── explore-brief.md       ← VIVO
        └── design.md              ← VIVO
```

### 12.5 Dualidade: vivo vs template

A principal fonte de confusão: quando o repo da skill (entidade 1) **também é**
projeto-alvo (entidade 3) — caso que **não se aplica mais** desde a migração
para package opencode (a skill vive em repo separado do projeto-alvo). Mantida
para histórico e para o cenário raro em que alguém clona a skill para dentro
do próprio projeto-alvo (não recomendado). Antes da migração para package, era
o caso do repo que distribui a skill em `.opencode/skills/` e a aplicava em
si mesmo na raiz.

Para fins práticos pós-package: dualidade vivo vs template agora é **entre
repos** — `assets/AGENTS.md` (template) vive no repo do package, `AGENTS.md`
(vivo) vive na raiz do projeto-alvo. Não coexistem no mesmo git.

| Arquivo | Estado | Localização | Conteúdo |
|---|---|---|---|
| `AGENTS.md` | **Vivo** | Raiz do projeto-alvo | Valores reais preenchidos (ex.: `Python 3.13`, `uv`, `pytest`) |
| `assets/AGENTS.md` | **Template** | `skills/maxdev-workflow-sync/assets/` no package | Genérico, com `{{...}}` |

**São arquivos diferentes** com papéis diferentes:

- O **vivo** (raiz do projeto-alvo) orienta o agente que trabalha no projeto.
- O **template** (`assets/`) orienta a skill `maxdev-workflow-sync` ao copiar
  para outros projetos.

Não confunda: editar o vivo não propaga para outros projetos; editar o template
propaga (após bump de versão e redistribute). Regra prática:

- Want mudar o comportamento **deste** projeto → edita raiz.
- Want mudar o template que **vai para todos** → edita `assets/` + bump
  `workflow.version` + redistribute.

### 12.6 Hierarquia de docs

- **`README.md`** (este) → **guia de uso**, ponto de entrada para humanos.
- **`SKILL.md`** → **contrato** lido pelo agente (description, when/when-not,
  instruções operacionais). Não editar a menos que o comportamento mude.
- **`references/merge-strategy.md`** → **aprofundamento técnico** do merge.

---

## 13. Glossário

| Termo | Definição |
|---|---|
| **Skill** | Pacote opencode com `SKILL.md` + scripts + assets; invocada via `/maxdev-workflow-sync` |
| **Template (assets)** | Arquivos genéricos com placeholders `{{...}}` em `assets/`, usados como fallback pelo `sync-workflow.sh` |
| **Canônico** | Um dos 9 canônicos que definem o workflow MaxDev (AGENTS.md, dev-workflow.md, 2 scripts, config.yaml, 2 templates) — chaves do array `CANON` em `sync-workflow.sh:52-60` |
| **Placeholder** | Token `{{NOME}}` em templates, substituído manualmente no projeto-alvo (exceto `{{WORKFLOW_VERSION}}`, auto) |
| **Bootstrap** | Primeiro `--apply` num projeto sem `workflow_version` em `openspec/config.yaml` — copia todos os canônicos + starters |
| **Drift** | Diferença entre `workflow_version` instalada e `WORKFLOW_VERSION` da skill — detectado por `--check` |
| **Projeto-alvo** | Repo que adota o workflow MaxDev; recebe os 9 canônicos + 5 starters na raiz |
| **Repo da skill** | Repo que distribui o package (`maxsyncai-opencode-skills`, carrega `skills/maxdev-workflow-sync/`) |
| **Override local** | Diretório apontado via `EXTERNAL_OVERRIDES` (env var) com arquivos canônicos para override (opt-in, avançado). Não é repo — é pasta local. |
| **Package** | Repo distribuído como plugin opencode (instalado em `~/.cache/opencode/packages/.../`). |
| **Plugin entry** | Arquivo `.opencode/plugins/maxsyncai-opencode-skills.js` que registra `skills/` em `config.skills.paths` no startup do opencode. |
| **Override per-file** | Se `EXTERNAL_OVERRIDES/<arquivo>` existe, override; se não, cai em `assets/<arquivo>`. |
| `EXTERNAL_OVERRIDES` | Variável de ambiente apontando para diretório local de override (mais forte na precedência; default: não setada). |
| `PROJECT_ROOT` | Variável de ambiente com path do projeto-alvo; default `$(pwd)` — exporte se rodar fora do alvo |
| `workflow_version` | Chave semver em `openspec/config.yaml` do projeto-alvo (preenchida pela skill) |
| `workflow.version` | Arquivo em `assets/workflow.version` com a versão atual da skill (semver) |
| **GATES** | Checkpoints obrigatórios do workflow MaxDev, definidos em `AGENTS.md` (GATE 0 a GATE 5) |
| **MaxDev** | Nome canônico do workflow distribuído por esta skill (não é nome de projeto) |
| **Sync idempotente** | Segundo run com mesma versão = no-op; só re-aplica se versão mudar ou `--force` |

---

## 14. Changelog

| Versão | Data | Mudanças |
|---|---|---|
| 1.0.0 | (preexistente) | Versão inicial da skill |
| 1.0.1 | 2026-08-05 | Fix `{{WORKFLOW_VERSION}}` auto-substituição + `workflow_version` duplicado |
| 1.0.2 | 2026-08-05 | Reordenação do script + repo externo como fonte de `workflow.version` |
| 1.0.3 | 2026-08-06 | Breaking: remove auto-clone; skill self-contained em `assets/` |
| 1.0.4 | 2026-08-06 | Sync `close-change.sh` refinado do projeto-fonte |
| 1.1.0 | 2026-08-06 | **Starters** (`.pre-commit-config.yaml`, `opencode.example.json`, `TESTING.md`, `Makefile.example`). Pós-sync checklist. |
| 1.2.0 | 2026-08-06 | **Pipeline pós-apply** de 8 etapas guardadas (A1 validação, A2 placeholders deriváveis, A3 opencode.json bootstrap, B2 `.gitignore` markers, B3 sanity check tooling, Hooks auto-install, C1 heurística stack). `.editorconfig`, `README.md`, `.gitignore` delimitado. 8 flags opt-out. |
| 1.2.1 | 2026-08-06 | Fix B3 detectar serena via `uvx --from` (detecção 2 tiers) |
| 1.2.2 | 2026-08-06 | Fix B2 `.gitignore` visível no `--check` (drift check + bug falso MODIFY-G) |
| 1.2.3 | 2026-08-06 | Fix `.gitignore` npm-blacklist — rename p/ `gitignore.template` (escapa packing npm) |
| 1.2.4 | 2026-08-06 | Fix UX — separação MODE×FORCE: `--check` read-only garantido (ordem-agnóstico), aviso explícito em `--apply` demote |
| 1.3.0 | 2026-08-22 | AGENTS enxuto (-62% tokens), 5 gates (0-4), spec mirrors, canvas, genericidade cross-project |
| 1.3.1 | 2026-08-22 | Restore generic placeholders in AGENTS.md & config.yaml (v1.3.0 had MaxCortex-specific hardcoded values) |

---

## Versão

`workflow.version`: **1.3.1** — bump semver a cada mudança de contrato nos 9
canônicos ou no comportamento do `sync-workflow.sh`. Projetos detectam
drift comparando com `workflow_version` em `openspec/config.yaml`.
