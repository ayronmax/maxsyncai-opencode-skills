#!/bin/bash
#
# close-change.sh — Orquestra o closeout de uma change OpenSpec após o merge
# do PR de implementação (GATE 4). Implementa o GATE 5 do fluxo MaxDev:
# "Closeout verde antes da próxima change".
#
# Pré-requisitos:
#   - O PR de implementação de <change> (base main, head feature/<change>)
#     já está MERGED no GitHub (GATE 4 cumprido pelo humano).
#   - Você está na branch main, sincronizada, working tree limpa.
#   - A nota "Decisões Técnicas — <change>" existe no Basic Memory.
#
# O que faz (modo padrão, 7 steps, idempotente):
#   [1/7] Valida auditoria antes de mover (tasks 100% [x], openspec(validate|doctor),
#         git limpo e sincronizado, PR merged, nota no Basic Memory).
#   [2/7] Marca N.8 (GATE 4) e N.9 (opsx-archive-change) como [x] em tasks.md.
#   [3/7] Roda `openspec archive <change>` (mergeea deltas e move para archive/).
#   [4/7] Cria branch canônica chore/archive-<change> e commit do closeout.
#   [5/7] Abre PR chaser (base main) e pausa em GATE 4 humano.
#
#   Após o merge humano do chaser PR, rode:
#     ./scripts/close-change.sh --post-merge <change>
#   [6/7] Volta à main, pull, deleta branch do chaser.
#   [7/7] Deleta feature/<change> (local+remoto) — resolve branch pendurada.
#
# Modo correção admin: se <change> JÁ está em openspec/changes/archive/
# (re-rodada em change arquivada mas com tasks [ ] de closeout), o script
# marca N.8/N.9 e abre PR admin (não re-move, não duplica archive).
#
# Uso:
#   ./scripts/close-change.sh <change-name>           # fluxo padrão (steps 1-5)
#   ./scripts/close-change.sh --post-merge <change>   # steps 6-7 após merge do chaser
#
# Saída: exit 0 = ok; exit != 0 = abortou com mensagem.
#
# Robusto: set -e + set -u; falha em qualquer step aborta sem estado parcial
# (move só após todas as validações passarem).
#

set -eo pipefail

# ---------- guardas ----------

if [[ $# -ge 1 && "$1" == "--post-merge" ]]; then
  POST_MERGE=true
  shift
else
  POST_MERGE=false
fi

if [[ $# -ne 1 ]]; then
  echo "Uso:"
  echo "  $0 <change-name>            # fluxo padrão (steps 1-5)"
  echo "  $0 --post-merge <change>    # steps 6-7 após merge do chaser PR"
  echo "Exemplo: $0 fix-timer-session-leak"
  exit 1
fi

CHANGE="$1"
ARCHIVED="openspec/changes/archive/$CHANGE"
ACTIVE="openspec/changes/$CHANGE"

# ---------- helpers ----------

step() { echo -e "\n[$1] $2"; }
abort() { echo "✗ $*"; exit 1; }

# ---------- pós-merge: steps 6-7 ----------

if [[ "$POST_MERGE" == "true" ]]; then
  CHASER="chore/archive-$CHANGE"
  step "6/7" "Pós-merge: voltando à main e pull..."
  git checkout main || abort "git checkout main falhou"
  git pull origin main || abort "git pull main falhou"

  step "7/7" "Limpando branches penduradas..."
  git branch -D "$CHASER" 2>/dev/null && echo "  ✓ deletada local: $CHASER" || echo "  ℹ branch local $CHASER já não existe"
  git push origin --delete "$CHASER" 2>/dev/null && echo "  ✓ deletada remoto: $CHASER" || echo "  ℹ branch remoto $CHASER já não existe"

  FEATURE="feature/$CHANGE"
  if git show-ref --quiet --verify "refs/heads/$FEATURE" 2>/dev/null; then
    git branch -D "$FEATURE" 2>/dev/null && echo "  ✓ deletada local: $FEATURE" || echo "  ℹ não deletei $FEATURE local (ainda merged?)"
  else
    echo "  ℹ branch local $FEATURE já não existe"
  fi
  if git show-ref --quiet --verify "refs/remotes/origin/$FEATURE" 2>/dev/null; then
    git push origin --delete "$FEATURE" 2>/dev/null && echo "  ✓ deletada remoto: $FEATURE" || echo "  ℹ não deletrei $FEATURE remoto"
  else
    echo "  ℹ branch remoto $FEATURE já não existe"
  fi

  echo
  echo "✓ Closeout de '$CHANGE' finalizado. GATE 5 verde."
  exit 0
fi

# ---------- resolve caminho tasks.md ----------

if ! [[ -d "$ACTIVE" ]] && ! [[ -d "$ARCHIVED" ]]; then
  abort "Change '$CHANGE' não encontrada em openspec/changes/ nem archive/"
fi

ADMIN_MODE=false
if [[ -d "$ARCHIVED" ]] && ! [[ -d "$ACTIVE" ]]; then
  ADMIN_MODE=true
  TASKS_FILE="$ARCHIVED/tasks.md"
  echo "ℹ Modo correção admin: '$CHANGE' já arquivado. Vou apenas marcar"
  echo "  N.8/N.9 e abrir PR admin (não re-mover)."
else
  TASKS_FILE="$ACTIVE/tasks.md"
fi

[[ -f "$TASKS_FILE" ]] || abort "tasks.md não encontrado em $TASKS_FILE"

# ---------- [1/7] validação ----------

step "1/7" "Validando auditoria antes de mover..."

# Pending tasks EXCLUDING the closeout markers (N.8 GATE 4, N.9 archive) —
# step 2 will mark those. Only non-closeout tasks should block here.
PENDING=$(grep -E '^- \[ \]' "$TASKS_FILE" | grep -cvE 'GATE 4|opsx-archive-change' || true)
if [[ "$PENDING" -gt 0 ]]; then
  if [[ "$ADMIN_MODE" == "true" ]]; then
    echo "  ℹ tasks [ ] pendentes (modo admin): $PENDING"
  else
    echo "✗ tasks.md tem $PENDING task(s) ainda [- [ ]] (não-closeout). Marque todas como [x] antes."
    grep -nE '^- \[ \]' "$TASKS_FILE" | grep -vE 'GATE 4|opsx-archive-change'
    exit 1
  fi
fi

openspec validate --changes >/dev/null 2>&1 || abort "openspec validate --changes falhou"
openspec doctor >/dev/null 2>&1 || abort "openspec doctor falhou"

[[ -z "$(git status --porcelain)" ]] || abort "git working tree não está limpa. Commit/stash antes."

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$ADMIN_MODE" == "false" ]]; then
  [[ "$BRANCH" == "main" ]] || abort "deve estar na branch main (está em '$BRANCH')"
  git fetch origin main >/dev/null 2>&1
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || abort "main não está sincronizada com origin/main"
fi

# nota no basic-memory (exige título exato "Decisões Técnicas — <change>")
NOTE_TITLE="Decisões Técnicas — $CHANGE"
if ! basic-memory tool search-notes "$NOTE_TITLE" 2>/dev/null | jq -r '.results[].title' | grep -qF "$NOTE_TITLE"; then
  abort "Nota 'Decisões Técnicas — $CHANGE' não encontrada no Basic Memory. Crie-a via basic-memory write_note antes do closeout."
fi

# PR merged (modo não-admin)
if [[ "$ADMIN_MODE" == "false" ]]; then
  PR_STATE=$(gh pr list --state merged --head "feature/$CHANGE" --json state --jq '.[0].state' 2>/dev/null || echo "")
  [[ "$PR_STATE" == "MERGED" ]] || abort "PR de implementação de '$CHANGE' (head feature/$CHANGE) não está MERGED (state='$PR_STATE'). GATE 4 ainda não cumprido."
fi

echo "✓ Auditoria validada."

# ---------- [2/7] marcar closeout ----------

step "2/7" "Marcando N.8 (GATE 4) e N.9 (archive) como [x] em $TASKS_FILE..."

mark_task_done() {
  local f="$1"
  local changed=false
  # Idempotente: marca TODAS as [ ] residuais como [x]. As pendências de
  # implementação já foram bloqueadas no step 1 (excluindo marcadores de
  # closeout). Sobram apenas closeout tasks — marcar todas é correto.
  if grep -qE '^- \[ \]' "$f"; then
    sed -i -E 's/^- \[ \] /- [x] /' "$f"
    changed=true
  fi
  if [[ "$changed" == "true" ]]; then
    echo "✓ Tasks de closeout marcadas. Diff:"
    git --no-pager diff -- "$f" || true
    return 0
  fi
  echo "ℹ Nenhuma task não-marca (já estão [x])."
  return 1
}

mark_task_done "$TASKS_FILE"

# ---------- modo admin: PR só com correção ----------

if [[ "$ADMIN_MODE" == "true" ]]; then
  if [[ -z "$(git status --porcelain)" ]]; then
    echo "ℹ tasks já estavam marcadas — nada a fazer (admin mode)."
    exit 0
  fi
  step "Admin/PR" "Criando PR admin de correção de auditoria..."
  CHASER="chore/admin-closeout-$CHANGE"
  git checkout -b "$CHASER"
  git add "$TASKS_FILE"
  git commit -m "docs(openspec): corrige auditoria tasks<N> de $CHANGE (closeout [x])"
  git push -u origin "$CHASER" 2>&1 | rtk tail -3 || abort "push admin falhou"
  gh pr create --base main --head "$CHASER" \
    --title "chore(openspec): corrige auditoria tasks de $CHANGE" \
    --body "Correção admin (não regressão): as tasks N.8/N.9 (GATE 4 aguardar merge) foram arquivadas sem marcação [x] quando \`openspec archive\` moveu o arquivo. Esta PR atualiza o livro-razão. Justificado em D5 do design de enforce-closeout-gate." \
    || abort "gh pr create admin falhou"
  echo "✓ PR admin criado. AGUARDE o merge humano."
  echo "  Após merge: $0 --post-merge $CHANGE"
  exit 0
fi

# ---------- [3/7] openspec archive ----------

step "3/7" "Rodando openspec archive $CHANGE..."
openspec archive "$CHANGE"

# ---------- [4/7] commit chaser ----------

step "4/7" "Criando commit chaser em chore/archive-$CHANGE..."

CHASER="chore/archive-$CHANGE"
git checkout -b "$CHASER"
git add openspec/

if [[ -z "$(git status --porcelain)" ]]; then
  abort "nada a commitar após openspec archive — possível divergência (change já arquivada?)"
fi

git commit -m "chore(openspec): arquiva change $CHANGE"

# ---------- [5/7] PR chaser ----------

step "5/7" "Abrindo PR chaser (GATE 4 — aguarde merge humano)..."
git push -u origin "$CHASER" 2>&1 | rtk tail -3 || abort "push chaser falhou"

gh pr create --base main --head "$CHASER" \
  --title "chore(openspec): arquiva $CHANGE" \
  --body "Closeout da change \`$CHANGE\` — mergeia deltas em openspec/specs/ e move a change para archive/. Orquestrado por \`./scripts/close-change.sh\` (GATE 5 do fluxo MaxDev)." \
  || abort "gh pr create chaser falhou"

echo
echo "════════════════════════════════════════════════════════════════"
echo "  GATE 4 HUMANO — PARE AQUI"
echo "  Após o merge do chaser PR no GitHub, rode:"
echo "    $0 --post-merge $CHANGE"
echo "════════════════════════════════════════════════════════════════"
echo "✓ PR chaser publicado. Closeou a fase de implementação."
exit 0
