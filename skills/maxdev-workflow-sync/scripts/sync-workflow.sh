#!/bin/bash
#
# sync-workflow.sh — Bootstrap, sync ou drift-check do workflow MaxDev OpenSpec.
# Idempotente: segundo run = no-op se a versão instalada == versão da skill.
#
# Modos:
#   ./sync-workflow.sh                # dry-run default (gera diff, pede confirm)
#   ./sync-workflow.sh --apply        # aplica mudanças (se versão igual: demote p/ check e avisa)
#   ./sync-workflow.sh --check        # read-only — reporta drift, não-modifica (--force não destrava)
#   ./sync-workflow.sh --force        # alias p/ --apply --force: aplica mesmo se versão igual
#
# Combinações comuns:
#   --apply --force                  # alias p/ --force (escrita + re-aplica starters)
#   --check --force                  # ≡ --check (read-only), warning que --force foi ignorado
#   --force --check                  # ≡ --check (idem acima — ordem-agnóstico)
#
# Flags opt-out (pipeline pós-apply, todas default ON — ver "Pipeline pós-apply"):
#   --no-install-hooks               # skip auto-install de hooks pre-commit
#   --install-hooks                  # força install mesmo se guards skipariam
#   --no-validate                    # skip openspec validate + doctor
#   --no-tools-check                 # skip sanity check de tooling
#   --no-stack-suggest               # skip heurística advisory de stack
#   --no-gitignore-sync              # skip sync delimitado de .gitignore
#   --no-auto-opencode               # skip criação de opencode.json em bootstrap
#   --no-derivable-placeholders      # skip substituição de {{PROJECT_NAME}}/{{PROJECT_ABSOLUTE_PATH}}
#
# Override local (opt-in, avançado):
#   EXTERNAL_OVERRIDES=/path/para/dir-local ./sync-workflow.sh --apply
#   (dir local com arquivos canônicos + starters + opcional workflow.version)
#   Útil para: fork privado do template, ambientes air-gapped, testes locais.
#   Default: nada externo — skill é self-contained em assets/.
#
# Detecta:
#   - workflow_version em openspec/config.yaml (se existir) vs WORKFLOW_VERSION
#     da skill (assets/workflow.version, ou EXTERNAL_OVERRIDES/workflow.version se setado)
#   - estado dos 7 arquivos canônicos vs defaults embutidos
#
# Saída: exit 0 = ok; exit != 0 = abortou com mensagem.
#

set -eo pipefail

# ---------- paths ----------

SKILL_DIR="${SKILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
ASSETS="$SKILL_DIR/assets"

# ---------- helpers ----------

step() { echo -e "\n[$1] $2"; }
abort() { echo "✗ $*"; exit 1; }
warn() { echo "  ⚠ $*"; }
advisory() { echo "  ℹ $*"; }

# slugify: converte string para slug compatível com Basic Memory project name
# (lowercase, [a-z0-9-], sem espaços/accentos/pontuação).
slugify() {
  local raw="$1"
  echo "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | iconv -t 'ascii//translit' 2>/dev/null || echo "$raw" | tr '[:upper:]' '[:lower:]'
  # fallback se iconv falhar (translit acima pode inserir aspas — sanitize)
}
# versão robusta sem iconv (portável):
slugify_name() {
  local raw="$1"
  echo "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9.-]+/-/g; s/^-+//; s/-+$//'
}

# is_ci: detecta ambiente CI (true se CI=true, GITHUB_ACTIONS, GITLAB_CI, etc).
is_ci() {
  [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" \
     || -n "${CIRCLECI:-}" || -n "${JENKINS_URL:-}" || -n "${BUILDKITE:-}" \
     || -n "${DRONE:-}" || -n "${TF_BUILD:-}" ]]
}

# has_git_dir: verifica .git/ no PROJECT_ROOT.
has_git_dir() { [[ -d "$PROJECT_ROOT/.git" ]]; }

# detect_alt_hook_manager: true se detecta husky/lefthook/simple-git-hooks.
detect_alt_hook_manager() {
  [[ -d "$PROJECT_ROOT/.husky" ]] \
    || [[ -f "$PROJECT_ROOT/lefthook.yml" ]] \
    || [[ -f "$PROJECT_ROOT/lefthook.yaml" ]] \
    || [[ -f "$PROJECT_ROOT/.simple-git-hooks" ]] \
    || grep -q "simple-git-hooks" "$PROJECT_ROOT/package.json" 2>/dev/null
}

# ---------- override local (opt-in, env var) ----------
# Resolvido EXPLICITAMENTE pelo usuário (path para diretório local).
# Não há mais auto-clone de repo externo — skill é self-contained em assets/.

EXTERNAL_OVERRIDES="${EXTERNAL_OVERRIDES:-}"
if [[ -n "$EXTERNAL_OVERRIDES" && ! -d "$EXTERNAL_OVERRIDES" ]]; then
  echo "✗ EXTERNAL_OVERRIDES='$EXTERNAL_OVERRIDES' não é um diretório válido."
  exit 1
fi

# ---------- determina WORKFLOW_VERSION da fonte efetiva ----------
# Precedência: EXTERNAL_OVERRIDES/workflow.version > assets/workflow.version
WORKFLOW_VERSION=""
if [[ -n "$EXTERNAL_OVERRIDES" && -f "$EXTERNAL_OVERRIDES/workflow.version" ]]; then
  WORKFLOW_VERSION=$(cat "$EXTERNAL_OVERRIDES/workflow.version" 2>/dev/null | tr -d '[:space:]')
fi
if [[ -z "$WORKFLOW_VERSION" && -f "$ASSETS/workflow.version" ]]; then
  WORKFLOW_VERSION=$(cat "$ASSETS/workflow.version" 2>/dev/null | tr -d '[:space:]')
fi

if [[ -z "$WORKFLOW_VERSION" ]]; then
  echo "✗ workflow.version não encontrado (tentei: EXTERNAL_OVERRIDES=$EXTERNAL_OVERRIDES, assets=$ASSETS)"
  exit 1
fi

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
OPENSPEC_CONFIG="$PROJECT_ROOT/openspec/config.yaml"

# ---------- parser de modos + flags ----------
#
# MODE = read-write state:  dry-run (default) | apply | check
# FORCE = modifier:         false (default) | true
#   - --apply      MODE=apply          FORCE=false
#   - --check      MODE=check          FORCE=false (sempre read-only, --force não destrava)
#   - --force      MODE=apply          FORCE=true  (alias: --apply --force)
#   - --apply --force  idem --force
#   - --check --force   MODE=check, FORCE=true  → warning "--check é read-only; --force ignorado"
#                        (ordem dos args não altera semântica — --check vence como read-only)
#
# Quando versão instalada == versão da skill:
#   - MODE=apply  + FORCE=false → demote p/ check com aviso explícito "use --force p/ re-aplicar"
#   - MODE=apply  + FORCE=true  → aplica normalmente

MODE="dry-run"
FORCE=false
# Flags opt-out do pipeline pós-apply (todas default ON — zero friction):
OPT_INSTALL_HOOKS=true          # auto-install pre-commit hooks
OPT_INSTALL_HOOKS_FORCE=false   # força install mesmo se guards skipariam (--install-hooks)
OPT_VALIDATE=true              # openspec validate + doctor
OPT_TOOLS_CHECK=true            # sanity check de tooling
OPT_STACK_SUGGEST=true          # heurística advisory de stack
OPT_GITIGNORE_SYNC=true         # sync delimitado de .gitignore
OPT_AUTO_OPENCODE=true          # criar opencode.json em bootstrap
OPT_DERIVABLE_PLACEHOLDERS=true # substituir {{PROJECT_NAME}}/{{PROJECT_ABSOLUTE_PATH}}

WARN_FORCE_IGNORED=false  # avisar ao final se --force foi ignorado por --check

for arg in "$@"; do
  case "$arg" in
    --apply)      MODE="apply"; FORCE=false ;;
    --check)
      # --check é read-only. Se --force estava pendente (FORCE=true via args
      # anteriores), --check.cancela sua intenção de escrita e sinaliza warning
      # no final — independente da ordem: `--force --check` ≡ `--check --force`.
      if [[ "$FORCE" == "true" ]]; then
        WARN_FORCE_IGNORED=true
        FORCE=false
      fi
      MODE="check" ;;
    --force)
      # --force = "escrever mesmo se versão igual". Se MODE já é check, --force
      # não destrava escrita (read-only prevalece) — sinalizar warning no final.
      if [[ "$MODE" == "check" ]]; then
        WARN_FORCE_IGNORED=true
      else
        MODE="apply"; FORCE=true
      fi
      ;;
    --no-install-hooks)            OPT_INSTALL_HOOKS=false ;;
    --install-hooks)               OPT_INSTALL_HOOKS=true; OPT_INSTALL_HOOKS_FORCE=true ;;
    --no-validate)                 OPT_VALIDATE=false ;;
    --no-tools-check)              OPT_TOOLS_CHECK=false ;;
    --no-stack-suggest)            OPT_STACK_SUGGEST=false ;;
    --no-gitignore-sync)           OPT_GITIGNORE_SYNC=false ;;
    --no-auto-opencode)            OPT_AUTO_OPENCODE=false ;;
    --no-derivable-placeholders)   OPT_DERIVABLE_PLACEHOLDERS=false ;;
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      abort "flag desconhecida: $arg (use --help)"
      ;;
  esac
done

# ---------- arquivos canônicos (caminho → origem skill) ----------
# Canônicos: clobber em --apply / --force (comportamento padrão). Formam o
# "contrato" sobrescrevível — mudanças neles são drift a sincronizar.

declare -A CANON=(
  ["AGENTS.md"]="$ASSETS/AGENTS.md"
  ["dev-workflow.md"]="$ASSETS/dev-workflow.md"
  ["scripts/close-change.sh"]="$ASSETS/scripts/close-change.sh"
  ["scripts/push-safe.sh"]="$ASSETS/scripts/push-safe.sh"
  ["scripts/update-canvas.sh"]="$ASSETS/scripts/update-canvas.sh"
  ["scripts/update_canvas.py"]="$ASSETS/scripts/update_canvas.py"
  ["scripts/migrate_implements.py"]="$ASSETS/scripts/migrate_implements.py"
  ["openspec/config.yaml"]="$ASSETS/openspec/config.yaml"
  ["openspec/templates/explore-brief.md"]="$ASSETS/openspec/templates/explore-brief.md"
  ["openspec/templates/design.md"]="$ASSETS/openspec/templates/design.md"
  [".pre-commit-config.yaml"]="$ASSETS/pre-commit-config.yaml"
)

# ---------- starters (caminho → origem skill) ----------
# Starters: só ADD se inexistente. MODIFY exige --force (preserva custom do
# usuário). Não são drift — são pontapé inicial para o usuário editar.

declare -A STARTERS=(
  ["opencode.example.json"]="$ASSETS/opencode.example.json"
  ["TESTING.md"]="$ASSETS/TESTING.md"
  ["Makefile.example"]="$ASSETS/Makefile.example"
  [".editorconfig"]="$ASSETS/.editorconfig"
  ["README.md"]="$ASSETS/README.md"
)

# Arquivos canônicos + starters que carregam {{WORKFLOW_VERSION}} no cabeçalho
# (substituído pós-copy se ainda presente — sed no-op se já substituído).
declare -a VERSIONED_TEMPLATES=(
  "AGENTS.md"
  ".pre-commit-config.yaml"
  "opencode.example.json"
  "TESTING.md"
  "Makefile.example"
  ".editorconfig"
  "README.md"
)

# Markers delimitadores do bloco .gitignore (v1.2.0+). Re-sync substitui só
# o trecho entre markers — entries custom acima/abaixo são preservadas.
GITIGNORE_BEGIN="# >>> maxdev-workflow-sync >>>"
GITIGNORE_END="# <<< maxdev-workflow-sync <<<"
# Arquivo-template vive em assets/gitignore.template (sem dot) — npm/packaging
# blacklist default sempre omite '.gitignore' mesmo com 'files: ["skills", ...]'
# no package.json. Renomear para 'gitignore.template' escapa da blacklist.
# EXTERNAL_OVERRIDES aceita 'gitignore.template' (preferido) ou '.gitignore'
# (back-compat — dir local sem filtro npm pode ter qualquer nome).
GITIGNORE_TEMPLATE="$ASSETS/gitignore.template"

# ---------- B2 analyze_gitignore_state() ----------
# Read-only: classifica estado do .gitignore sem tocar arquivos. Usada tanto
# no drift check (computa diffs) quanto no apply (sync_gitignore_delimited).
# Casos no stdout para captura via $():
#   add        : .gitignore não existe → será criado com markers + entries
#   append     : .gitignore existe sem markers → append do bloco delimitado
#   update     : .gitignore existe com markers par; bloco entre markers != template
#   up-to-date : .gitignore existe com markers par; bloco já igual ao template
#   unbalanced : markers desbalanceados (begin != end) → warning, não tocar
#   skip-noopt : --no-gitignore-sync ativo
#   skip-notpl : template não encontrado em assets/ override
#   skip-empty  : template não tem markers delimitados (skill corrompida?)

# resolve_gitignore_template: retorna path do template efetivo (override > default).
# Override aceita 'gitignore.template' (preferido) ou '.gitignore' (back-compat).
# Echo no stdout: path absoluto do template, ou string vazia se não encontrado.
resolve_gitignore_template() {
  if [[ -n "$EXTERNAL_OVERRIDES" ]]; then
    if [[ -f "$EXTERNAL_OVERRIDES/gitignore.template" ]]; then
      echo "$EXTERNAL_OVERRIDES/gitignore.template"; return
    fi
    if [[ -f "$EXTERNAL_OVERRIDES/.gitignore" ]]; then
      echo "$EXTERNAL_OVERRIDES/.gitignore"; return
    fi
  fi
  if [[ -f "$GITIGNORE_TEMPLATE" ]]; then
    echo "$GITIGNORE_TEMPLATE"; return
  fi
  echo ""
}

analyze_gitignore_state() {
  local dst="$PROJECT_ROOT/.gitignore"
  local src
  src=$(resolve_gitignore_template)

  if [[ "$OPT_GITIGNORE_SYNC" != "true" ]]; then
    echo "skip-noopt"; return
  fi
  if [[ -z "$src" ]]; then
    echo "skip-notpl"; return
  fi

  # Caso 1: inexistente → add
  if [[ ! -f "$dst" ]]; then
    echo "add"; return
  fi

  # Lê a seção delimitada do template ({{WORKFLOW_VERSION}} deixado literal —
  # comparado com o destino que também pode ter placeholder se recém-criado)
  local template_section
  template_section=$(awk "/^${GITIGNORE_BEGIN//\//\\/}/,/^${GITIGNORE_END//\//\\/}/" "$src")
  if [[ -z "$template_section" ]]; then
    echo "skip-empty"; return
  fi
  # Normaliza {{WORKFLOW_VERSION}} em ambos (template e destino) ANTES de
  # comparar, para evitar falso "update" quando o apply-case-add criou o
  # .gitignore com placeholder literal (sem substituir). Normaliza só para
  # a comparação — o sync aplica a versão real ao escrever.
  local template_norm current_norm
  template_norm="${template_section//\{\{WORKFLOW_VERSION\}\}/$WORKFLOW_VERSION}"

  # Caso 2: existe sem markers → append
  if ! grep -q -F "$GITIGNORE_BEGIN" "$dst"; then
    echo "append"; return
  fi

  # Caso 3/4: existe com markers. Valida par begin↔end.
  local count_begin count_end
  count_begin=$(grep -c -F "$GITIGNORE_BEGIN" "$dst" || true)
  count_end=$(grep -c -F "$GITIGNORE_END" "$dst" || true)
  if [[ "$count_begin" -ne "$count_end" ]]; then
    echo "unbalanced"; return
  fi

  # Extrai o bloco atual entre markers do destino e compara com template
  # (ambos normalizados para $WORKFLOW_VERSION — cobre caso add que copia
  # literal e caso update que já tem versão substituída).
  local current_section
  current_section=$(awk "/^${GITIGNORE_BEGIN//\//\\/}/,/^${GITIGNORE_END//\//\\/}/" "$dst")
  current_norm="${current_section//\{\{WORKFLOW_VERSION\}\}/$WORKFLOW_VERSION}"
  if [[ "$current_norm" == "$template_norm" ]]; then
    echo "up-to-date"; return
  fi
  echo "update"; return
}

# ---------- detecta estado ----------

step "1" "Analisando estado do projeto em $PROJECT_ROOT..."

# bootstrap = não existe openspec/config.yaml
BOOTSTRAP=true
if [[ -f "$OPENSPEC_CONFIG" ]]; then
  BOOTSTRAP=false
  INSTALLED_VERSION=$(grep -E '^workflow_version:' "$OPENSPEC_CONFIG" 2>/dev/null | sed -E 's/^workflow_version:[[:space:]]*//' | tr -d '[:space:]' || true)
fi

if [[ "$BOOTSTRAP" == "true" ]]; then
  echo "  ℹ Bootstrap: openspec/config.yaml não encontrado. Vou copiar todos os templates."
else
  echo "  ℹ Versão instalada: ${INSTALLED_VERSION:-<none>}"
  echo "  ℹ Versão da skill:    $WORKFLOW_VERSION"
  # Versão igual: --apply (sem --force) é demoted para --check com aviso explícito.
  # --apply --force / --force: aplica normalmente (FORCE=true não cai neste branch).
  # --check / --check --force: permanece read-only (FORCE não destrava escrita).
  if [[ "$INSTALLED_VERSION" == "$WORKFLOW_VERSION" && "$FORCE" != "true" ]]; then
    if [[ "$MODE" == "apply" ]]; then
      echo "  ℹ Versão igual — drift check apenas. Para re-aplicar use --force."
      MODE="check"
    else
      echo "  ✓ Mesma versão — drift check apenas (use --force para re-aplicar)."
    fi
  fi
fi

if [[ -n "$EXTERNAL_OVERRIDES" ]]; then
  echo "  ℹ Override local ativo: $EXTERNAL_OVERRIDES"
else
  echo "  ℹ Usando assets/ embutidos na skill (default)."
fi

# ---------- computa diffs ----------

step "2" "Comparando arquivos canônicos..."

CHANGES=()        # "<ADD|MODIFY> <dst>"  para canônicos
STARTER_ADDS=()   # "<dst>"              starters a criar (inexistentes)
STARTER_FORCES=() # "<dst>"              starters a sobrescrever (só em --force)
STARTER_SKIPS=()  # "<dst>"              starters existentes preservados

for dst in "${!CANON[@]}"; do
  src="${CANON[$dst]}"
  # override por EXTERNAL_OVERRIDES se setado e o arquivo existir lá
  if [[ -n "$EXTERNAL_OVERRIDES" && -f "$EXTERNAL_OVERRIDES/$dst" ]]; then
    src="$EXTERNAL_OVERRIDES/$dst"
  fi
  full_dst="$PROJECT_ROOT/$dst"
  if [[ ! -f "$full_dst" ]]; then
    CHANGES+=("ADD $dst")
  elif ! diff -q "$src" "$full_dst" >/dev/null 2>&1; then
    CHANGES+=("MODIFY $dst")
  fi
done

for dst in "${!STARTERS[@]}"; do
  src="${STARTERS[$dst]}"
  if [[ -n "$EXTERNAL_OVERRIDES" && -f "$EXTERNAL_OVERRIDES/$dst" ]]; then
    src="$EXTERNAL_OVERRIDES/$dst"
  fi
  full_dst="$PROJECT_ROOT/$dst"
if [[ ! -f "$full_dst" ]]; then
     STARTER_ADDS+=("$dst")
   elif [[ "$FORCE" == "true" && "$MODE" == "apply" ]]; then
     # --force (ou --apply --force): sobrescreve mesmo starter existente
     STARTER_FORCES+=("$dst")
   else
     STARTER_SKIPS+=("$dst")
  fi
done

# ---------- B2 preview (.gitignore drift check) ----------
# analyze_gitignore_state() é read-only: classifica sem tocar arquivos.
# Casos relevantes para o drift report:
#   add        → conta como "ADD-G .gitignore"
#   append     → conta como "ADD-G .gitignore (append delimitado)"
#   update     → conta como "MODIFY-G .gitignore (bloco entre markers)"
#   unbalanced → warning (não action, mas avisa problema)
#   up-to-date / skip-* → sem relato

GITIGNORE_DRIFT=""
GITWARNING=""
# Resolve template efetivo (assets ou EXTERNAL_OVERRIDES) — se não há template,
# skip case `skip-notpl` será retornado por analyze (sem efeito colateral em
# --check). O guard evita chamar analyze se claramente não há template.
_gtemplate=$(resolve_gitignore_template)
if [[ -n "$_gtemplate" ]]; then
  _gstate=$(analyze_gitignore_state)
  case "$_gstate" in
    add)      GITIGNORE_DRIFT="ADD-G .gitignore  (markers + entries; novo)" ;;
    append)   GITIGNORE_DRIFT="ADD-G .gitignore  (append delimitado — preserva custom)" ;;
    update)   GITIGNORE_DRIFT="MODIFY-G .gitignore  (bloco entre markers; preserva custom)" ;;
    unbalanced) GITWARNING=".gitignore markers desbalanceados (skip ao aplicar — antecorruption)" ;;
    up-to-date) ;;
    skip-noopt) ;;
    skip-notpl) ;;
    skip-empty) ;;
  esac
fi

GITIGNORE_COUNT=0
[[ -n "$GITIGNORE_DRIFT" ]] && GITIGNORE_COUNT=1

TOTAL_CHANGES=$(( ${#CHANGES[@]} + ${#STARTER_ADDS[@]} + ${#STARTER_FORCES[@]} + GITIGNORE_COUNT ))

if [[ $TOTAL_CHANGES -eq 0 && -z "$GITWARNING" ]]; then
  echo "  ✓ Nenhum drift detectado. Workflow sincronizado."
  if [[ ${#STARTER_SKIPS[@]} -gt 0 ]]; then
    echo "  ℹ Starters preservados (use --force para sobrescrever):"
    for s in "${STARTER_SKIPS[@]}"; do echo "    - $s"; done
  fi
  exit 0
fi

if [[ -n "$GITWARNING" ]]; then
  warn "$GITWARNING"
fi

if [[ $TOTAL_CHANGES -eq 0 ]]; then
  echo "  ✓ Nenhum drift de arquivos. Workflow sincronizado."
  [[ "$WARN_FORCE_IGNORED" == "true" ]] && warn "--check é read-only; --force ignorado. Use --force (sem --check) para re-aplicar."
  exit 0
fi

echo "  $TOTAL_CHANGES change(s) detectada(s):"
for c in "${CHANGES[@]}"; do
  echo "    - $c"
done
for dst in "${STARTER_ADDS[@]}"; do
  echo "    - ADD-S $dst  (starter novo)"
done
for dst in "${STARTER_FORCES[@]}"; do
  echo "    - MODIFY-S $dst  (starter sobrescrito --force)"
done
[[ -n "$GITIGNORE_DRIFT" ]] && echo "    - $GITIGNORE_DRIFT"
if [[ ${#STARTER_SKIPS[@]} -gt 0 ]]; then
  echo "  ℹ Starters preservados (use --force para sobrescrever):"
  for s in "${STARTER_SKIPS[@]}"; do echo "    - $s"; done
fi

# ---------- mode check: para aqui ----------

if [[ "$MODE" == "check" ]]; then
  echo
  echo "ℹ Modo --check: nenhum arquivo modificado. Para aplicar, rode:"
  echo "    $0 --apply"
  [[ "$WARN_FORCE_IGNORED" == "true" ]] && warn "--check é read-only; --force ignorado. Use --force (sem --check) para re-aplicar."
  exit 0
fi

# ---------- dry-run: gera diff ----------

if [[ "$MODE" == "dry-run" ]]; then
  step "3" "Dry-run — diff dos arquivos a atualizar:"
  for c in "${CHANGES[@]}"; do
    action=$(echo "$c" | cut -d' ' -f1)
    dst=$(echo "$c" | cut -d' ' -f2)
    src="${CANON[$dst]}"
    if [[ -n "$EXTERNAL_OVERRIDES" && -f "$EXTERNAL_OVERRIDES/$dst" ]]; then
      src="$EXTERNAL_OVERRIDES/$dst"
    fi
    echo "  ─── $dst ───"
    if [[ "$action" == "ADD" ]]; then
      echo "  (arquivo novo — não exibe diff)"
    else
      diff -u "$PROJECT_ROOT/$dst" "$src" | head -30 || true
    fi
  done
  for dst in "${STARTER_ADDS[@]}"; do
    echo "  ─── $dst ───"
    echo "  (starter novo — não exibe diff)"
  done
  for dst in "${STARTER_FORCES[@]}"; do
    src="${STARTERS[$dst]}"
    if [[ -n "$EXTERNAL_OVERRIDES" && -f "$EXTERNAL_OVERRIDES/$dst" ]]; then
      src="$EXTERNAL_OVERRIDES/$dst"
    fi
    echo "  ─── $dst ───"
    diff -u "$PROJECT_ROOT/$dst" "$src" | head -30 || true
  done
  echo
  read -r -p "[?] Aplicar $TOTAL_CHANGES mudança(s)? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || abort "abortado pelo usuário."
fi

# ---------- apply ----------

step "3" "Aplicando $TOTAL_CHANGES mudança(s)..."

for c in "${CHANGES[@]}"; do
  dst=$(echo "$c" | cut -d' ' -f2)
  src="${CANON[$dst]}"
  if [[ -n "$EXTERNAL_OVERRIDES" && -f "$EXTERNAL_OVERRIDES/$dst" ]]; then
    src="$EXTERNAL_OVERRIDES/$dst"
  fi
  full_dst="$PROJECT_ROOT/$dst"
  mkdir -p "$(dirname "$full_dst")"
  cp "$src" "$full_dst"
  chmod +x "$full_dst" 2>/dev/null || true  # scripts
  echo "  ✓ $dst"
done

# starters: só ADD (ou --force overwrite)
for dst in "${STARTER_ADDS[@]}" "${STARTER_FORCES[@]}"; do
  src="${STARTERS[$dst]}"
  if [[ -n "$EXTERNAL_OVERRIDES" && -f "$EXTERNAL_OVERRIDES/$dst" ]]; then
    src="$EXTERNAL_OVERRIDES/$dst"
  fi
  full_dst="$PROJECT_ROOT/$dst"
  mkdir -p "$(dirname "$full_dst")"
  cp "$src" "$full_dst"
  echo "  ✓ $dst  (starter)"
done

# ---------- atualiza workflow_version ----------

# Lógica robusta (não depende de bootstrap):
# - se config.yaml já tem workflow_version: → sed substitui
# - senão → append no final
# Obs.: o template assets/openspec/config.yaml NÃO define workflow_version:
# (linha comentada com placeholder), então em bootstrap puro cai no append.
# Em projeto legado com versão antiga, sed substitui corretamente.
if grep -q '^workflow_version:' "$OPENSPEC_CONFIG"; then
  sed -i -E "s/^workflow_version:.*/workflow_version: $WORKFLOW_VERSION/" "$OPENSPEC_CONFIG"
else
  echo "workflow_version: $WORKFLOW_VERSION" >> "$OPENSPEC_CONFIG"
fi

# ---------- substitui {{WORKFLOW_VERSION}} em arquivos copiados ----------

# Templates (canônicos + starters) carregam {{WORKFLOW_VERSION}} no cabeçalho.
# Substituir no destino após cada apply (bootstrap ou drift update). Seguro:
# sed no-op se o placeholder não existir (usuário já substituiu manualmente).

for f in "${VERSIONED_TEMPLATES[@]}"; do
  full="$PROJECT_ROOT/$f"
  if [[ -f "$full" ]] && grep -q -F '{{WORKFLOW_VERSION}}' "$full"; then
    sed -i "s|{{WORKFLOW_VERSION}}|$WORKFLOW_VERSION|g" "$full"
    echo "  ✓ $f: {{WORKFLOW_VERSION}} → $WORKFLOW_VERSION"
  fi
done

# ---------- A2 — substituir placeholders deriváveis ----------
# {{PROJECT_NAME}}          = slug do basename do PROJECT_ROOT
# {{PROJECT_ABSOLUTE_PATH}} = $PROJECT_ROOT
# Determinísticos, deduzíveis do cwd — substituir pós-copy reduz friction.

AUTO_PROJECT_NAME=""
AUTO_OPENCODE_CREATED=false

if [[ "$OPT_DERIVABLE_PLACEHOLDERS" == "true" ]]; then
  AUTO_PROJECT_NAME=$(slugify_name "$(basename "$PROJECT_ROOT")")
  AUTO_PROJECT_PATH="$PROJECT_ROOT"
  step "A2" "Substituindo placeholders deriváveis..."
  echo "  ℹ {{PROJECT_NAME}} → $AUTO_PROJECT_NAME"
  echo "  ℹ {{PROJECT_ABSOLUTE_PATH}} → $AUTO_PROJECT_PATH"
  for f in "${VERSIONED_TEMPLATES[@]}" "openspec/config.yaml" "AGENTS.md"; do
    full="$PROJECT_ROOT/$f"
    [[ -f "$full" ]] || continue
    if grep -q -F '{{PROJECT_NAME}}' "$full"; then
      sed -i "s|{{PROJECT_NAME}}|$AUTO_PROJECT_NAME|g" "$full"
      echo "  ✓ $f: {{PROJECT_NAME}} → $AUTO_PROJECT_NAME"
    fi
    if grep -q -F '{{PROJECT_ABSOLUTE_PATH}}' "$full"; then
      sed -i "s|{{PROJECT_ABSOLUTE_PATH}}|$AUTO_PROJECT_PATH|g" "$full"
      echo "  ✓ $f: {{PROJECT_ABSOLUTE_PATH}} → $AUTO_PROJECT_PATH"
    fi
  done
fi

# ---------- B2 — sync delimitado de .gitignore ----------
#
# Dois componentes:
#   analyze_gitignore_state()  — read-only: classifica estado do .gitignore
#                                (definida em "B2 constants" acima para uso no drift check)
#   sync_gitignore_delimited() — apply: executa a ação correspondente

sync_gitignore_delimited() {
  local dst="$PROJECT_ROOT/.gitignore"
  local src
  src=$(resolve_gitignore_template)

  local state
  state=$(analyze_gitignore_state)

  case "$state" in
    skip-noopt)
      advisory "B2 .gitignore sync: skipada por --no-gitignore-sync"
      return ;;
    skip-notpl)
      advisory "B2 .gitignore: template não encontrado (esperado em assets/gitignore.template)."
      advisory "  Causa comum: packing npm omite '.gitignore' por default. Skill usa"
      advisory "  'gitignore.template' (sem dot) p/ evitar isso. Se atualizou da cache,"
      advisory "  force re-fetch do package: rm -rf ~/.cache/opencode/packages/maxsyncai*"
      return ;;
    skip-empty)
      warn "B2 .gitignore: template sem markers delimitados — skipada (preserva custom)"
      return ;;
    up-to-date)
      echo "  ✓ .gitignore: bloco entre markers já está sincronizado"
      return ;;
    add)
      # Substitui {{WORKFLOW_VERSION}} no template antes de copiar — caso
      # contrário, 2º --check reportaria MODIFY-G false positive (analyze
      # compara com placeholder já substituído).
      sed "s|{{WORKFLOW_VERSION}}|$WORKFLOW_VERSION|g" "$src" > "$dst"
      echo "  ✓ .gitignore criado com seção delimitada (markers)"
      return ;;
    append)
      local template_section
      template_section=$(awk "/^${GITIGNORE_BEGIN//\//\\/}/,/^${GITIGNORE_END//\//\\/}/" "$src")
      template_section="${template_section//\{\{WORKFLOW_VERSION\}\}/$WORKFLOW_VERSION}"
      {
        echo ""
        echo "$template_section"
      } >> "$dst"
      echo "  ✓ .gitignore: seção delimitada appended (entries custom preservadas acima)"
      return ;;
    unbalanced)
      local count_begin count_end
      count_begin=$(grep -c -F "$GITIGNORE_BEGIN" "$dst" || true)
      count_end=$(grep -c -F "$GITIGNORE_END" "$dst" || true)
      warn "B2 .gitignore: markers desbalanceados (begin=$count_begin end=$count_end) — skipada para evitar corrupção"
      warn "    remova manualmente os markers restantes e rode novamente"
      return ;;
    update)
      local template_section tmp
      template_section=$(awk "/^${GITIGNORE_BEGIN//\//\\/}/,/^${GITIGNORE_END//\//\\/}/" "$src")
      template_section="${template_section//\{\{WORKFLOW_VERSION\}\}/$WORKFLOW_VERSION}"
      tmp=$(mktemp)
      awk -v begin="$GITIGNORE_BEGIN" -v end="$GITIGNORE_END" \
          -v new="$template_section" '
        BEGIN {state="before"; printed_new=0}
        $0 == begin && state=="before" {
          state="inside"; next
        }
        $0 == end && state=="inside" {
          if (!printed_new) { print new; printed_new=1 }
          state="after"; next
        }
        state=="inside" { next }
        { print }
        END {
          if (!printed_new && state!="inside") print new
        }
      ' "$dst" > "$tmp"
      if [[ -s "$tmp" ]]; then
        mv "$tmp" "$dst"
        echo "  ✓ .gitignore: bloco entre markers atualizado (entries custom preservadas)"
      else
        rm -f "$tmp"
        warn "B2 .gitignore: awk resultou vazio — rollback preservou o original"
      fi
      return ;;
    *)
      warn "B2 .gitignore: estado desconhecido '$state' — skipada"
      return ;;
  esac
}

# ---------- A3 — criar opencode.json em bootstrap ----------

maybe_create_opencode_json() {
  if [[ "$OPT_AUTO_OPENCODE" != "true" ]]; then
    advisory "A3 opencode.json: skipada por --no-auto-opencode (renomeie .example manualmente)"
    return
  fi

  local example="$PROJECT_ROOT/opencode.example.json"
  local real="$PROJECT_ROOT/opencode.json"

  if [[ ! -f "$example" ]]; then
    return  # starter não foi copiado (preservado de versão antiga, etc)
  fi

  if [[ -f "$real" ]]; then
    advisory "A3 opencode.json: já existe — .example mantido ao lado para referência"
    return
  fi

  # .example existe, real não — renomeia (placeholders já substituídos por A2)
  cp "$example" "$real"
  echo "  ✓ opencode.json criado (renomeado de .example com placeholders substituídos)"
  AUTO_OPENCODE_CREATED=true
}

# ---------- A1 — openspec validate + doctor ----------

post_apply_validate_openspec() {
  if [[ "$OPT_VALIDATE" != "true" ]]; then
    advisory "A1 openspec validate: skipado por --no-validate"
    return
  fi

  if [[ "$BOOTSTRAP" == "true" ]]; then
    advisory "A1 openspec validate: skipado em bootstrap (rode 'openspec init' primeiro)"
    return
  fi

  if is_ci; then
    advisory "A1 openspec validate: skipado em CI (sem ganho marginal)"
    return
  fi

  if ! command -v openspec >/dev/null 2>&1; then
    advisory "A1 openspec: binário não encontrado no PATH — instale via 'npm install -g openspec' ou 'uv tool install openspec'"
    return
  fi

  step "A1" "Validando com openspec..."
  if openspec validate 2>&1 | sed 's/^/    /'; then
    echo "  ✓ openspec validate"
  else
    warn "openspec validate falhou — revise openspec/changes e openspec/specs"
  fi
  if openspec doctor 2>&1 | sed 's/^/    /'; then
    echo "  ✓ openspec doctor"
  else
    warn "openspec doctor falhou — revise referências em openspec/"
  fi
}

# ---------- B3 — sanity check de tooling ----------
#
# Schema de tool (delimitador § — não aparece em URLs, suporta pipes em hints):
#   "bin§uvx_ref§uvx_subcmd§hint"
#     bin       : nome do binário para command -v (detecção direta no PATH)
#     uvx_ref   : flags uvx para fallback (ex.: "--from git+...") — vazio se não há
#     uvx_subcmd: subcomando uvx (ex.: "serena") — vazio se uvx_ref é vazio
#     hint      : instrução de instalação (exibida se ambos tiers falham)
# Para tools sem fallback uvx: "bin§§§hint" (uvx_ref e uvx_subcmd vazios).
#
# Detecção em 2 tiers (primeiro sucesso vence):
#   1. command -v <bin>                          (rápido — binário direto no PATH)
#   2. timeout 8 uvx <uvx_ref> <uvx_subcmd> --version  (fallback — tools uvx-wrapped
#      como serena: 'uvx --from git+https://github.com/oraios/serena serena')
#      Timeout 8s: cache uvx aquecido responde em ~2s; sem cache pode precisar
#      fetch git. Opt-out: --no-tools-check. Timeout 124 → warning (cache frio).

sanity_check_tooling() {
  if [[ "$OPT_TOOLS_CHECK" != "true" ]]; then
    advisory "B3 tools check: skipado por --no-tools-check"
    return
  fi

  if is_ci; then
    advisory "B3 tools check: skipado em CI"
    return
  fi

  step "B3" "Sanity check de tooling esperado..."
  # bin§uvx_ref§uvx_subcmd§hint  (§ é separador; suporta pipes em URLs/hints)
  local entries=(
    "openspec§§§npm install -g openspec"
    "gh§§§ver https://github.com/cli/cli#installation"
    "jq§§§instale jq via package manager (apt/brew/portable binary)"
    "python3§§§https://www.python.org/downloads/"
    "node§§§https://nodejs.org/"
    "pre-commit§§§uv tool install pre-commit | pip install pre-commit"
    "basic-memory§§§uv tool install basic-memory"
    "serena§--from git+https://github.com/oraios/serena§serena§uvx --from git+https://github.com/oraios/serena serena"
  )
  for entry in "${entries[@]}"; do
    local bin uvx_ref uvx_subcmd hint rest
    bin="${entry%%§*}";       rest="${entry#*§}"
    uvx_ref="${rest%%§*}";   rest="${rest#*§}"
    uvx_subcmd="${rest%%§*}"; rest="${rest#*§}"
    hint="$rest"

    # Tier 1: binário direto no PATH
    if command -v "$bin" >/dev/null 2>&1; then
      printf "    ✓ %-15s %s\n" "$bin" "$(command -v "$bin")"
      continue
    fi

    # Tier 2: fallback uvx-wrapper (se uvx_ref declarado e uvx existe)
    if [[ -n "$uvx_ref" ]] && command -v uvx >/dev/null 2>&1; then
      local uvx_out uvx_exit
      uvx_out=$(timeout 8 uvx $uvx_ref $uvx_subcmd --version 2>&1 | head -1)
      uvx_exit=$?
      if [[ $uvx_exit -eq 0 ]] && [[ -n "$uvx_out" ]]; then
        printf "    ✓ %-15s via uvx (%s)\n" "$bin" "$uvx_out"
        continue
      elif [[ $uvx_exit -eq 124 ]]; then
        printf "    ⚠ %-15s via uvx (timeout >8s — cache não aquecido?)\n" "$bin"
        continue
      fi
    fi

    printf "    ✗ %-15s instale: %s\n" "$bin" "$hint"
  done
}

# ---------- v1.1.1 — auto-install hooks pre-commit ----------

post_apply_install_hooks() {
  if [[ "$MODE" == "check" ]]; then
    return  # read-only
  fi
  if [[ "$OPT_INSTALL_HOOKS" != "true" ]]; then
    advisory "Hooks: auto-install skipado por --no-install-hooks"
    advisory "  Para instalar manualmente: pre-commit install --hook-type pre-commit --hook-type pre-push"
    return
  fi

  # --install-hooks força passar direto para install (ignora guards)
  if [[ "$OPT_INSTALL_HOOKS_FORCE" != "true" ]]; then
    if ! has_git_dir; then
      advisory "Hooks: .git/ ausente em $PROJECT_ROOT — rode 'git init' e depois 'pre-commit install ...'"
      return
    fi
    if is_ci; then
      advisory "Hooks: CI detectado — auto-install skipado (rode em ambiente local se quiser hooks)"
      return
    fi
    if detect_alt_hook_manager; then
      advisory "Hooks: detectado hook manager alternativo (.husky/lefthook.yml/.simple-git-hooks). Não instalei pre-commit — consulte a doc do manager detectado."
      return
    fi
  fi

  if ! command -v pre-commit >/dev/null 2>&1; then
    advisory "Hooks: 'pre-commit' não encontrado no PATH — instale via 'uv tool install pre-commit' ou 'pip install pre-commit', depois rode:"
    advisory "    pre-commit install --hook-type pre-commit --hook-type pre-push"
    return
  fi

  step "Hooks" "Regenerando .git/hooks/pre-commit e .git/hooks/pre-push..."
  if pre-commit install --hook-type pre-commit --hook-type pre-push 2>&1 | sed 's/^/    /'; then
    echo "  ✓ Hooks pre-commit e pre-push instalados"
    echo "  ℹ NÃO versionar .git/hooks/* (INSTALL_PYTHON hardcoded da máquina)"
  else
    warn "pre-commit install falhou (exit $?) — rode manualmente:"
    warn "    pre-commit install --hook-type pre-commit --hook-type pre-push"
  fi
}

# ---------- C1 — heurística advisory de stack ----------

suggest_stack_placeholders() {
  if [[ "$OPT_STACK_SUGGEST" != "true" ]]; then
    advisory "C1 stack suggest: skipado por --no-stack-suggest"
    return
  fi

  step "C1" "Heurística advisory de stack (não aplica — revise manualmente)..."

  local py="$PROJECT_ROOT/pyproject.toml"
  local pkg="$PROJECT_ROOT/package.json"

  if [[ -f "$py" ]]; then
    advisory "pyproject.toml detectado:"
    local content; content=$(cat "$py" 2>/dev/null)
    if echo "$content" | grep -q -i "fastapi"; then
      echo "    {{FRAMEWORK_BACKEND}} = FastAPI"
    fi
    if echo "$content" | grep -q -i "flask"; then
      echo "    {{FRAMEWORK_BACKEND}} = Flask"
    fi
    if echo "$content" | grep -q -i "django"; then
      echo "    {{FRAMEWORK_BACKEND}} = Django"
    fi
    if echo "$content" | grep -q -i "ruff"; then
      echo "    {{LINTER_BACKEND}} = ruff"
    fi
    if echo "$content" | grep -q -i "pytest"; then
      echo "    {{TEST_FRAMEWORK_BACKEND}} = pytest"
    fi
    echo "    {{LANG_BACKEND}} = Python"
    echo "    {{PKG_MANAGER_BACKEND}} = uv (recomendado) ou pip"
  else
    advisory "pyproject.toml não encontrado — stack backend não deduzida"
  fi

  if [[ -f "$pkg" ]]; then
    advisory "package.json detectado:"
    local content; content=$(cat "$pkg" 2>/dev/null)
    if echo "$content" | grep -q -i "\"next\""; then
      echo "    {{FRAMEWORK_FRONTEND}} = Next.js"
    fi
    if echo "$content" | grep -q -i "\"react\""; then
      echo "    {{FRAMEWORK_FRONTEND}} = React"
    fi
    if echo "$content" | grep -q -i "\"vue\""; then
      echo "    {{FRAMEWORK_FRONTEND}} = Vue"
    fi
    if echo "$content" | grep -q -i "\"eslint\""; then
      echo "    {{LINTER_FRONTEND}} = eslint"
    fi
    if echo "$content" | grep -q -i "\"vitest\""; then
      echo "    {{TEST_FRAMEWORK_FRONTEND}} = vitest"
    elif echo "$content" | grep -q -i "\"jest\""; then
      echo "    {{TEST_FRAMEWORK_FRONTEND}} = jest"
    fi
    echo "    {{LANG_FRONTEND}} = TypeScript/JavaScript"
    echo "    {{PKG_MANAGER_FRONTEND}} = npm (default) ou pnpm/yarn"
  else
    advisory "package.json não encontrado — stack frontend não deduzida"
  fi

  advisory "Sugestões são advisory — revise e substitua manualmente em:"
  advisory "    AGENTS.md / openspec/config.yaml / .pre-commit-config.yaml / TESTING.md / Makefile.example"
}

# ---------- executa pipeline pós-apply (somente em apply/force) ----------
# Após MODE x FORCE separation: pipeline pós-apply só roda em MODE=apply.
# --check (--force ignorado) → read-only, não roda pipeline.
# --apply --force / --force (--apply + FORCE=true) → roda normalmente.

if [[ "$MODE" == "apply" ]]; then
  step "B2" "Sync .gitignore delimitado..."
  sync_gitignore_delimited

  step "A3" "Bootstrap de opencode.json..."
  maybe_create_opencode_json

  post_apply_validate_openspec

  sanity_check_tooling

  post_apply_install_hooks

  suggest_stack_placeholders
fi

# ---------- pós-sync checklist adaptativo ----------

echo
echo "✓ Workflow MaxDev v$WORKFLOW_VERSION sincronizado em $PROJECT_ROOT"
echo
echo "Próximos passos:"
echo "  1. AGENTS.md                     — Targets canônicos, Convenções"
echo "  2. openspec/config.yaml          — context, conventions"
echo "  3. .pre-commit-config.yaml       — {{LINTER_BACKEND_RUFF}} / {{LINTER_FRONTEND_ESLINT}}"
if [[ "$AUTO_OPENCODE_CREATED" == "true" ]]; then
  echo "  4. opencode.json                 — ✓ criado automaticamente (revise {{PROJECT_NAME}})"
else
  echo "  4. opencode.example.json         — renomeie → opencode.json e edite"
fi
echo "  5. TESTING.md                     — {{TEST_FRAMEWORK_BACKEND}}, {{TEST_FRAMEWORK_FRONTEND}}"
echo "  6. Makefile.example               — renomeie → Makefile e implemente targets"
echo "     (stubs saem com exit 1 — não suba Makefile com stubs)"
echo "  7. README.md / .editorconfig      — personalize conforme o projeto"
echo
echo "Aplique os hooks do pre-commit se ainda não o fez:"
echo "     pre-commit install --hook-type pre-commit --hook-type pre-push"
echo
echo "Valide o resultado:"
echo "     openspec validate && openspec doctor && make help"
exit 0
