#!/bin/bash
#
# close-change.sh — Orquestra o closeout de uma change OpenSpec após o merge
# do PR de implementação (GATE 3). Implementa o GATE 4 do fluxo MaxDev:
# "Closeout verde antes da próxima change".
#
# Pré-requisitos:
#   - O PR de implementação de <change> (base main, head feature/<change>)
#     já está MERGED no GitHub (GATE 3 cumprido pelo humano).
#   - Você está na branch main, sincronizada, working tree limpa.
#   - A nota "Decisões Técnicas — <change>" existe no Basic Memory.
#
# O que faz (modo padrão, 6 steps, idempotente):
#   [1/7] Valida auditoria antes de mover (tasks 100% [x], openspec(validate|doctor),
#         git limpo e sincronizado, PR merged, nota no Basic Memory, e Open
#         Questions do design.md resolvidas — default ON).
#   [2/7] Marca N.8 (GATE 4) e N.9 (opsx-archive-change) como [x] em tasks.md.
#   [3/7] Roda `openspec archive <change>` (mergeea deltas e move para archive/).
#   [3.5] Cria/atualiza spec mirror notes no Basic Memory via basic-memory tool write-note.
#   [4/7] Cria branch canônica chore/archive-<change> e commit do closeout.
#   [5/7] Abre PR chaser (base main) e pausa em GATE 3 humano.
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
# Opções de validação customizada:
#   --validate-hooks <script>     Script de validação customizado (executado no step 1/7)
#   --index-file <path>           Arquivo de índice do projeto (padrão: memories/PROJECT_UPPER.md)
#   --note-title-pattern <pattern> Padrão do título da nota (padrão: "Decisões Técnicas — %s")
#   --min-content-lines <n>       Mínimo de linhas de conteúdo nas decision notes (padrão: 10)
#   --skip-spec-mirror-check      Pula validação de spec mirrors no BM DB
#   --skip-decision-note-check    Pula validação de decision notes
#   --skip-index-check            Pula validação do índice do projeto
#   --skip-open-questions         Pula validação de Open Questions no design.md
#
# Saída: exit 0 = ok; exit != 0 = abortou com mensagem.
#
# Robusto: set -e + set -u; falha em qualquer step aborta sem estado parcial
# (move só após todas as validações passarem).
#

set -eo pipefail

# ---------- parse args ----------

VALIDATE_HOOKS=""
INDEX_FILE_OVERRIDE=""
NOTE_TITLE_PATTERN="Decisões Técnicas — %s"
MIN_CONTENT_LINES=10
SKIP_SPEC_MIRROR_CHECK=false
SKIP_DECISION_NOTE_CHECK=false
SKIP_INDEX_CHECK=false
SKIP_OPEN_QUESTIONS_CHECK=false
POST_MERGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --post-merge)
      POST_MERGE=true
      shift
      ;;
    --validate-hooks)
      VALIDATE_HOOKS="$2"
      shift 2
      ;;
    --index-file)
      INDEX_FILE_OVERRIDE="$2"
      shift 2
      ;;
    --note-title-pattern)
      NOTE_TITLE_PATTERN="$2"
      shift 2
      ;;
    --min-content-lines)
      MIN_CONTENT_LINES="$2"
      shift 2
      ;;
    --skip-spec-mirror-check)
      SKIP_SPEC_MIRROR_CHECK=true
      shift
      ;;
    --skip-decision-note-check)
      SKIP_DECISION_NOTE_CHECK=true
      shift
      ;;
    --skip-index-check)
      SKIP_INDEX_CHECK=true
      shift
      ;;
    --skip-open-questions)
      SKIP_OPEN_QUESTIONS_CHECK=true
      shift
      ;;
    -h|--help)
      echo "Uso:"
      echo "  $0 <change-name>                    # fluxo padrão (steps 1-5)"
      echo "  $0 --post-merge <change>            # steps 6-7 após merge do chaser PR"
      echo ""
      echo "Opções de validação customizada:"
      echo "  --validate-hooks <script>           Script de validação customizado"
      echo "  --index-file <path>                 Arquivo de índice do projeto"
      echo "  --note-title-pattern <pattern>      Padrão do título da nota (%%s = change)"
      echo "  --min-content-lines <n>             Mínimo linhas de conteúdo nas decision notes"
      echo "  --skip-spec-mirror-check            Pula validação spec mirrors no BM DB"
      echo "  --skip-decision-note-check          Pula validação decision notes"
      echo "  --skip-index-check                  Pula validação índice do projeto"
      echo "  --skip-open-questions               Pula validação de Open Questions no design.md"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Opção desconhecida: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 1 ]]; then
  echo "Uso:"
  echo "  $0 <change-name>                    # fluxo padrão (steps 1-5)"
  echo "  $0 --post-merge <change>            # steps 6-7 após merge do chaser PR"
  echo "  $0 --help                           # mostra ajuda completa"
  echo "Exemplo: $0 fix-timer-session-leak"
  exit 1
fi

CHANGE="$1"
ARCHIVED="openspec/changes/archive/$CHANGE"
ACTIVE="openspec/changes/$CHANGE"

# PROJECT_UPPER/LOWER derivados do nome do projeto (pasta atual)
PROJECT_UPPER=$(basename "$(pwd)" | tr '[:lower:]' '[:upper:]')
PROJECT_LOWER=$(echo "$PROJECT_UPPER" | tr '[:upper:]' '[:lower:]')

# Resolve index file
if [[ -n "$INDEX_FILE_OVERRIDE" ]]; then
  INDEX_FILE="$INDEX_FILE_OVERRIDE"
else
  INDEX_FILE="memories/${PROJECT_UPPER}.md"
fi

# Resolve note title
NOTE_TITLE=$(printf "$NOTE_TITLE_PATTERN" "$CHANGE")
NOTE_FILE="memories/${NOTE_TITLE}.md"

# ---------- helpers ----------

step() { echo -e "\n[$1] $2"; }
abort() { echo "✗ $*"; exit 1; }

# ---------- validação de Open Questions ----------
#
# Detecta Open Questions ainda abertas no `## Open Questions` do design.md.
# Tolerante a dois formatos em circulação:
#   (a) tabela:  `| Q | Owner | Spike/Research | Status | Resolvido em |`
#                com status aberto na 4ª coluna (Q→1, Owner→2, Spike→3, Status→4).
#   (b) bullet:  `- **Q1**: ... | Status: open | ...`
#
# Regras: seção ausente → aborta; placeholder "Nenhuma em aberto" → passa;
# qualquer status aberto (open/aberta/em aberto/a ser/a resolver) → aborta listando.

validate_open_questions() {
  local design_file="$1"

  [[ -f "$design_file" ]] || return 0

  if ! grep -qE '^##+ Open Questions' "$design_file"; then
    echo "  ✗ design.md sem seção '## Open Questions' (obrigatória). Adicione-a antes do closeout."
    return 1
  fi

  if grep -qiE 'nenhuma em aberto|no open questions|none open' "$design_file"; then
    echo "  ✓ Open Questions: sem pendências declaradas."
    return 0
  fi

  local section
  section=$(awk '/^##+ Open Questions/{f=1; next} /^##+ /{if(f) exit} f' "$design_file")

  local open_lines=()
  local status_cell
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^[[:space:]]*\|?[[:space:]]*(Q|Owner|Spike|Resolvido) ]]; then
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*\|?[[:space:]]*[-:]{3,} ]]; then
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*\| ]]; then
      status_cell=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5); print $5}')
      if echo "$status_cell" | grep -qiE 'open|aberta|em aberto|a ser|a resolver'; then
        open_lines+=("$line")
        continue
      fi
    fi
    if echo "$line" | grep -qiE 'Status[[:space:]]*:[[:space:]]*(open|aberta|em aberto|a ser|a resolver)'; then
      open_lines+=("$line")
    fi
  done <<< "$section"

  if [[ ${#open_lines[@]} -gt 0 ]]; then
    echo "  ✗ Open Questions ainda abertas no design.md:"
    for l in "${open_lines[@]}"; do
      echo "      $l"
    done
    echo "  Resolva-as no design.md OU mova a dívida para o Basic Memory antes do closeout."
    echo "  (Opt-out se necessário: $0 --skip-open-questions $CHANGE)"
    return 1
  fi

  echo "  ✓ Open Questions: resolvidas."
  return 0
}

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
  echo "✓ Closeout de '$CHANGE' finalizado. GATE 4 verde."
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

# nota no basic-memory (exige título exato conforme pattern)
if [[ ! -f "$NOTE_FILE" ]]; then
  abort "Nota '$NOTE_TITLE' não encontrada em memories/. Crie-a via basic-memory write_note --title \"$NOTE_TITLE\" --folder / --overwrite antes do closeout."
fi

# valida specs quando capabilities declaradas (só modo não-admin)
if [[ "$ADMIN_MODE" == "false" ]] && [[ -f "$ACTIVE/proposal.md" ]]; then
  CAP_COUNT=$(grep -c $'^- \x60[a-z].*\x60:' "$ACTIVE/proposal.md" 2>/dev/null || true)
  if [[ "$CAP_COUNT" -gt 0 ]]; then
    SKIP_SPECS=$(grep -c 'skip_specs:\s*true' "$ACTIVE/.openspec.yaml" 2>/dev/null || true)
    if [[ "$SKIP_SPECS" -eq 0 ]]; then
      if [[ ! -d "$ACTIVE/specs" ]]; then
        abort "Change '$CHANGE' declara $CAP_COUNT capabilities no proposal.md mas não tem specs/. Crie spec deltas em openspec/changes/$CHANGE/specs/<capability>/spec.md."
      fi
      SPEC_COUNT=$(find "$ACTIVE/specs" -name "spec.md" -type f | wc -l)
      if [[ "$SPEC_COUNT" -lt "$CAP_COUNT" ]]; then
        abort "Change '$CHANGE' declara $CAP_COUNT capabilities no proposal.md mas só tem $SPEC_COUNT spec(s). Crie as specs faltantes."
      fi
    fi
  fi
fi

# PR merged (modo não-admin)
if [[ "$ADMIN_MODE" == "false" ]]; then
  PR_STATE=$(gh pr list --state merged --head "feature/$CHANGE" --json state --jq '.[0].state' 2>/dev/null || echo "")
  [[ "$PR_STATE" == "MERGED" ]] || abort "PR de implementação de '$CHANGE' (head feature/$CHANGE) não está MERGED (state='$PR_STATE'). GATE 3 ainda não cumprido."
fi

# Custom validation hooks (executados antes das validações built-in)
if [[ -n "$VALIDATE_HOOKS" && -f "$VALIDATE_HOOKS" ]]; then
  echo "  Executando validação customizada: $VALIDATE_HOOKS"
  bash "$VALIDATE_HOOKS" "$CHANGE" "$ACTIVE" "$ARCHIVED" || abort "Validação customizada falhou"
fi

# Open Questions do design.md: não arquivar dívida técnica em silêncio.
# Default ON (opt-out: --skip-open-questions). Em modo admin (change já
# arquivada), não bloqueia — é correção de livro-razão, não nova auditoria.
if [[ "$SKIP_OPEN_QUESTIONS_CHECK" == "false" && "$ADMIN_MODE" == "false" ]]; then
  step "1/7" "Validando Open Questions do design.md..."
  validate_open_questions "$ACTIVE/design.md" || abort "Open Questions não resolvidas (use --skip-open-questions para pular)"
fi

# ---------- [1/7] validações extras: spec mirrors + decision notes + wikilinks ----------
# Estas validações podem ser desabilitadas via flags

# Spec mirror check (otimizado: 1 chamada em vez de N chamadas sequenciais)
if [[ "$SKIP_SPEC_MIRROR_CHECK" == "false" && -d "openspec/specs" ]]; then
  step "1/7" "Validando spec mirrors no Basic Memory DB (1 chamada)..."
  SPEC_COUNT=$(find "openspec/specs" -name "spec.md" -type f | wc -l)

  # Busca todas as specs tipo 'spec' numa única chamada (~10s em vez de N*10s).
  # Custo dominante é o startup da CLI, não o volume de resultados.
  BM_SPECS_JSON=$(basic-memory tool search-notes --type spec --page-size 40 2>/dev/null || echo "{}")
  if ! echo "$BM_SPECS_JSON" | jq -e '.results' >/dev/null 2>&1; then
    abort "Falha ao consultar spec mirrors no Basic Memory DB. Rode sync antes do closeout."
  fi

  for spec_dir in openspec/specs/*/; do
    spec_name=$(basename "$spec_dir")
    spec_title="Spec — $spec_name"
    if ! echo "$BM_SPECS_JSON" | jq -e --arg t "$spec_title" '.results[] | select(.title == $t)' >/dev/null 2>&1; then
      abort "Spec mirror '$spec_title' não encontrado no Basic Memory DB. Rode sync antes do closeout."
    fi
  done
  echo "  ✓ Todas as $SPEC_COUNT spec mirrors encontradas no BM DB"
fi

# Decision notes check
if [[ "$SKIP_DECISION_NOTE_CHECK" == "false" ]]; then
  step "1/7" "Validando decision notes (conteúdo + implements + wikilinks)..."
  for decision_file in memories/Decisões\ Técnicas\ —\ *.md; do
    [[ -f "$decision_file" ]] || continue

    # 1. Conteúdo mínimo (excluindo frontmatter + Relations)
    CONTENT_LINES=$(grep -vE '^(---|title:|type:|permalink:|# Relations|- implements|- depends_on|- relates_to)' "$decision_file" | grep -cvE '^\s*$' || true)
    if [[ "$CONTENT_LINES" -lt "$MIN_CONTENT_LINES" ]]; then
      abort "Decision note '$(basename "$decision_file")' tem conteúdo insuficiente ($CONTENT_LINES linhas). Mínimo: $MIN_CONTENT_LINES. Adicione resumo, decisões, riscos."
    fi

    # 2. Wikilinks implements válidos
    for spec_link in $(grep -oE '\[\[Spec — [^]]+\]\]' "$decision_file" | sed 's/\[\[Spec — \(.*\)\]\]/\1/'); do
      if [[ ! -d "openspec/specs/$spec_link" ]]; then
        abort "Decision '$(basename "$decision_file")' referencia spec inexistente: '$spec_link'. Crie em openspec/specs/ ou remova da relation."
      fi
    done

    # 3. Wikilinks depends_on/relates_to válidos
    for dec_link in $(grep -oE '\[\[Decisões Técnicas — [^]]+\]\]' "$decision_file" | sed 's/\[\[Decisões Técnicas — \(.*\)\]\]/\1/'); do
      if [[ ! -f "memories/Decisões Técnicas — $dec_link.md" ]]; then
        abort "Decision '$(basename "$decision_file")' referencia decision inexistente: '$dec_link'. Verifique depends_on/relates_to."
      fi
    done

    # 4. Pelo menos um implements se houver specs na change (modo não-admin)
    if [[ "$ADMIN_MODE" == "false" ]] && [[ -f "$ACTIVE/proposal.md" ]]; then
      CAP_COUNT=$(grep -c $'^- \x60[a-z].*\x60:' "$ACTIVE/proposal.md" 2>/dev/null || true)
      if [[ "$CAP_COUNT" -gt 0 ]]; then
        IMPLEMENTS_COUNT=$(grep -cE '^- implements:' "$decision_file" 2>/dev/null || true)
        if [[ "$IMPLEMENTS_COUNT" -eq 0 ]]; then
          abort "Decision note '$(basename "$decision_file")' não tem relations 'implements'. Adicione wikilinks [[Spec — X]]."
        fi
      fi
    fi
  done
  echo "  ✓ Decision notes validadas"
fi

# Index file check
if [[ "$SKIP_INDEX_CHECK" == "false" ]]; then
  if [[ ! -f "$INDEX_FILE" ]]; then
    abort "Índice '$INDEX_FILE' não encontrado em memories/. Crie-o via basic-memory write_note antes do closeout."
  fi
  DECISION_LINK="[[${NOTE_TITLE}]]"
  if ! grep -qF "$DECISION_LINK" "$INDEX_FILE" 2>/dev/null; then
    abort "Índice '$INDEX_FILE' não referencia esta change. Adicione '$DECISION_LINK' ao índice antes do closeout."
  fi
  echo "  ✓ Índice do projeto validado"
fi

# PR merged (modo não-admin)
if [[ "$ADMIN_MODE" == "false" ]]; then
  PR_STATE=$(gh pr list --state merged --head "feature/$CHANGE" --json state --jq '.[0].state' 2>/dev/null || echo "")
  [[ "$PR_STATE" == "MERGED" ]] || abort "PR de implementação de '$CHANGE' (head feature/$CHANGE) não está MERGED (state='$PR_STATE'). GATE 3 ainda não cumprido."
fi

echo "✓ Auditoria validada."

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
  git push -u origin "$CHASER" 2>&1 | tail -3 || abort "push admin falhou"
  gh pr create --base main --head "$CHASER" \
    --title "chore(openspec): corrige auditoria tasks de $CHANGE" \
    --body "Correção admin (não regressão): as tasks N.8/N.9 (GATE 4 aguardar merge) foram arquivadas sem marcação [x] quando \`openspec archive\` moveu o arquivo. Esta PR atualiza o livro-razão." \
    || abort "gh pr create admin falhou"
  echo "✓ PR admin criado. AGUARDE o merge humano."
  echo "  Após merge: $0 --post-merge $CHANGE"
  exit 0
fi

# ---------- [3/7] openspec archive ----------

step "3/7" "Rodando openspec archive $CHANGE..."
openspec archive -y "$CHANGE"

# ---------- [3.5] spec mirror notes via Basic Memory (DUAL STRATEGY) ----------
#
# Estratégia 1 (preferida): Python script com KnowledgeClient direto
#   - Requer: basic_memory package + Python 3.10+
#   - Vantagem: ~7x mais rápido, retries reais, idempotente nativo
# Estratégia 2 (fallback): bash + xargs + basic-memory CLI
#   - Sempre disponível, zero deps extras
#   - Mais lento, menos robusto

step "3.5" "Sincronizando spec mirrors no Basic Memory (dual strategy)..."

if [[ -d "openspec/specs" ]]; then
  # Estratégia 1: Python script (preferido — mais rápido e robusto)
  if [[ -f "scripts/sync-spec-mirrors.py" ]] && command -v python3 >/dev/null 2>&1; then
    echo "  Usando estratégia Python (KnowledgeClient direto, paralelo + retries)..."
    if python3 scripts/sync-spec-mirrors.py --project "$PROJECT_LOWER" --specs-dir "openspec/specs" --concurrency 10 --retries 3; then
      echo "  ✓ Sincronização concluída (Python strategy)"
    else
      echo "  ⚠ Python strategy falhou, tentando fallback bash..."
      _sync_specs_bash
    fi
  else
    # Estratégia 2: bash fallback (portável, zero deps)
    _sync_specs_bash
  fi
fi

# ---------- Função de fallback bash ----------

_sync_specs_bash() {
  echo "  Usando estratégia bash (xargs + basic-memory CLI, paralelo)..."
  spec_files=()
  while IFS= read -r -d '' file; do
    spec_files+=("$file")
  done < <(find openspec/specs -name "spec.md" -type f -print0)

  if [[ ${#spec_files[@]} -eq 0 ]]; then
    echo "  ℹ Nenhuma spec encontrada"
    return 0
  fi

  echo "  Encontradas ${#spec_files[@]} specs — sincronizando em paralelo (max 10 concorrentes)..."

  sync_spec() {
    local spec_file="$1"
    local spec_name=$(basename "$(dirname "$spec_file")")
    local spec_content=$(cat "$spec_file")
    local spec_title="Spec — $spec_name"
    local project_lower="${PROJECT_NAME_LOWER:-$PROJECT_LOWER}"

    for attempt in 1 2 3; do
      if basic-memory tool write-note \
        --title "$spec_title" \
        --content "$spec_content" \
        --type spec \
        --tags "spec,$project_lower,$spec_name" \
        --overwrite \
        --folder "/" \
        >/dev/null 2>&1; then
        echo "  ✓ $spec_title"
        return 0
      fi

      if [[ $attempt -lt 3 ]]; then
        sleep $((2 ** (attempt - 1)))
      fi
    done

    echo "  ⚠ $spec_title (falhou após 3 tentativas)"
    return 1
  }

  export -f sync_spec
  export PROJECT_NAME_LOWER

  printf '%s\0' "${spec_files[@]}" | xargs -0 -P 10 -I {} bash -c 'sync_spec "$@"' _ {} || true

  echo "  Concluído (bash strategy)."
}

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

step "5/7" "Abrindo PR chaser (GATE 3 — aguarde merge humano)..."
git push -u origin "$CHASER" 2>&1 | tail -3 || abort "push chaser falhou"

gh pr create --base main --head "$CHASER" \
  --title "chore(openspec): arquiva $CHANGE" \
  --body "Closeout da change \`$CHANGE\` — mergeia deltas em openspec/specs/, cria spec mirror notes no Basic Memory, e move a change para archive/. Orquestrado por \`./scripts/close-change.sh\` (GATE 4 do fluxo MaxDev)." \
  || abort "gh pr create chaser falhou"

echo
echo "════════════════════════════════════════════════════════════════"
echo "  GATE 3 HUMANO — PARE AQUI"
echo "  Após o merge do chaser PR no GitHub, rode:"
echo "    $0 --post-merge $CHANGE"
echo "════════════════════════════════════════════════════════════════"
echo "✓ PR chaser publicado. Closeou a fase de implementação."
exit 0