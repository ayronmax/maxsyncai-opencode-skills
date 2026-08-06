#!/bin/bash
#
# sync-workflow.sh — Bootstrap, sync ou drift-check do workflow MaxDev OpenSpec.
# Idempotente: segundo run = no-op se a versão instalada == versão da skill.
#
# Modos:
#   ./sync-workflow.sh                # dry-run default (gera diff, pede confirm)
#   ./sync-workflow.sh --apply        # aplica mudanças sem confirmar
#   ./sync-workflow.sh --check        # drift check (não modifica, só reporta)
#   ./sync-workflow.sh --force        # sobrescreve mesmo se versão igual
#
# Override local (opt-in, avançado):
#   EXTERNAL_OVERRIDES=/path/para/dir-local ./sync-workflow.sh --apply
#   (dir local com 7 canônicos + opcional workflow.version)
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

# ---------- modos ----------

MODE="dry-run"
[[ "$1" == "--apply" ]] && MODE="apply"
[[ "$1" == "--check" ]] && MODE="check"
[[ "$1" == "--force" ]] && MODE="force"

# ---------- arquivos canônicos (caminho → origem skill) ----------
# Canônicos: clobber em --apply / --force (comportamento padrão). Formam o
# "contrato" sobrescrevível — mudanças neles são drift a sincronizar.

declare -A CANON=(
  ["AGENTS.md"]="$ASSETS/AGENTS.md"
  ["dev-workflow.md"]="$ASSETS/dev-workflow.md"
  ["scripts/close-change.sh"]="$ASSETS/scripts/close-change.sh"
  ["scripts/push-safe.sh"]="$ASSETS/scripts/push-safe.sh"
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
)

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
  if [[ "$INSTALLED_VERSION" == "$WORKFLOW_VERSION" && "$MODE" != "force" ]]; then
    echo "  ✓ Mesma versão — drift check apenas (use --force para re-aplicar)."
    MODE="check"
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
  elif [[ "$MODE" == "force" ]]; then
    STARTER_FORCES+=("$dst")
  else
    STARTER_SKIPS+=("$dst")
  fi
done

TOTAL_CHANGES=$(( ${#CHANGES[@]} + ${#STARTER_ADDS[@]} + ${#STARTER_FORCES[@]} ))

if [[ $TOTAL_CHANGES -eq 0 ]]; then
  echo "  ✓ Nenhum drift detectado. Workflow sincronizado."
  if [[ ${#STARTER_SKIPS[@]} -gt 0 ]]; then
    echo "  ℹ Starters preservados (use --force para sobrescrever):"
    for s in "${STARTER_SKIPS[@]}"; do echo "    - $s"; done
  fi
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
if [[ ${#STARTER_SKIPS[@]} -gt 0 ]]; then
  echo "  ℹ Starters preservados (use --force para sobrescrever):"
  for s in "${STARTER_SKIPS[@]}"; do echo "    - $s"; done
fi

# ---------- mode check: para aqui ----------

if [[ "$MODE" == "check" ]]; then
  echo
  echo "ℹ Modo --check: nenhum arquivo modificado. Para aplicar, rode:"
  echo "    $0 --apply"
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

# O template assets/AGENTS.md carrega placeholder {{WORKFLOW_VERSION}} (linha 3,
# comentário "Template gerado por maxdev-workflow-sync v{{WORKFLOW_VERSION}}.").
# Substituir no destino após cada apply (bootstrap ou drift update). Seguro:
# sed no-op se o placeholder não existir (usuário já substituiu manualmente).
# Os starters (pre-commit-config.yaml, opencode.example.json, TESTING.md,
# Makefile.example) também carregam {{WORKFLOW_VERSION}} nos cabeçalhos.

for f in "AGENTS.md" ".pre-commit-config.yaml" "opencode.example.json" \
         "TESTING.md" "Makefile.example"; do
  full="$PROJECT_ROOT/$f"
  if [[ -f "$full" ]] && grep -q -F '{{WORKFLOW_VERSION}}' "$full"; then
    sed -i "s|{{WORKFLOW_VERSION}}|$WORKFLOW_VERSION|g" "$full"
    echo "  ✓ $f: {{WORKFLOW_VERSION}} → $WORKFLOW_VERSION"
  fi
done

# ---------- pós-sync checklist ----------

echo
echo "✓ Workflow MaxDev v$WORKFLOW_VERSION sincronizado em $PROJECT_ROOT"
echo
echo "Próximos passos (edite os placeholders {{...}} conforme seu stack):"
echo "  1. AGENTS.md                     — Targets canônicos, Convenções, Referências"
echo "  2. openspec/config.yaml          — context, conventions"
echo "  3. .pre-commit-config.yaml       — {{LINTER_BACKEND_RUFF}} / {{LINTER_FRONTEND_ESLINT}}"
echo "  4. opencode.example.json (renomeie → opencode.json)"
echo "                                   — {{PROJECT_NAME}}, {{PROJECT_ABSOLUTE_PATH}}"
echo "  5. TESTING.md                    — {{TEST_FRAMEWORK_BACKEND}}, {{TEST_FRAMEWORK_FRONTEND}}"
echo "  6. Makefile.example (renomeie → Makefile)"
echo "                                   — implemente os targets (stubs saem com exit 1)"
echo
echo "Aplique os hooks do pre-commit (regenera .git/hooks/*):"
echo "     pre-commit install --hook-type pre-commit --hook-type pre-push"
echo "   NÃO versionar .git/hooks/* (caminhos hardcoded da máquina)."
echo
echo "Valide o resultado:"
echo "     openspec validate && openspec doctor && make help"
exit 0
