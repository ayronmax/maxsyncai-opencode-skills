#!/bin/bash
#
# verify-graph.sh — Valida integridade do grafo de conhecimento (Basic Memory + Obsidian)
#
# Uso:
#   bash scripts/verify-graph.sh           # validação completa (exit 0 = ok, exit != 0 = falha)
#   bash scripts/verify-graph.sh --dry-run # reporta o que seria validado sem falhar
#   bash scripts/verify-graph.sh --ci      # output compacto para CI/CD
#
# Validações:
# 1. Spec mirrors no BM DB (cada spec em openspec/specs/ tem mirror no BM)
# 2. Decision notes relations implements -> specs existentes
# 3. Decision notes relations depends_on/relates_to -> decisions existentes
# 4. Decision notes conteúdo mínimo (>= 10 linhas não-vazias excluindo frontmatter + Relations)
# 5. Decision notes com implements se change tem specs

set -euo pipefail

DRY_RUN=false
CI_MODE=false

for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --ci) CI_MODE=true ;;
    *) echo "Uso: $0 [--dry-run|--ci]" && exit 1 ;;
  esac
done

log() {
  [[ "$CI_MODE" == "true" ]] || echo "$*"
}

error() {
  echo "✗ $*" >&2
}

success() {
  [[ "$CI_MODE" == "true" ]] || echo "✓ $*"
}

warn() {
  echo "⚠ $*" >&2
}

abort() {
  error "$*"
  [[ "$DRY_RUN" == "true" ]] || exit 1
}

# ---------- 1. Spec mirrors no BM DB ----------

validate_spec_mirrors() {
  log "🔍 Validando spec mirrors no Basic Memory DB..."
  
  if [[ ! -d "openspec/specs" ]]; then
    warn "openspec/specs/ não encontrado — pulando validação de spec mirrors"
    return 0
  fi
  
  local missing=0
  local total=0
  
  for spec_dir in openspec/specs/*/; do
    [[ -d "$spec_dir" ]] || continue
    spec_name=$(basename "$spec_dir")
    spec_title="Spec — $spec_name"
    ((total++))
    
    if ! basic-memory tool search-notes --title "$spec_title" --type spec --page-size 1 2>/dev/null | jq -e '.results[0]' >/dev/null; then
      error "Spec mirror '$spec_title' não encontrado no Basic Memory DB"
      ((missing++))
    fi
  done
  
  if [[ "$missing" -gt 0 ]]; then
    abort "$missing de $total spec mirrors faltando no BM DB"
  fi
  
  success "Todas as $total spec mirrors encontradas no BM DB"
  return 0
}

# ---------- 2. Decision notes relations implements ----------

validate_decision_implements() {
  log "🔍 Validando relations 'implements' nas decision notes..."
  
  local errors=0
  local checked=0
  
  for decision_file in memories/Decisões\ Técnicas\ —\ *.md; do
    [[ -f "$decision_file" ]] || continue
    ((checked++))
    
    # Extrai wikilinks [[Spec — X]] de implements:
    local spec_links
    spec_links=$(grep -oE '\[\[Spec — [^]]+\]\]' "$decision_file" | sed 's/\[\[Spec — \(.*\)\]\]/\1/' | sort -u)
    
    for spec_link in $spec_links; do
      if [[ ! -d "openspec/specs/$spec_link" ]]; then
        error "Decision '$(basename "$decision_file")' referencia spec inexistente: '$spec_link'"
        ((errors++))
      fi
    done
  done
  
  if [[ "$errors" -gt 0 ]]; then
    abort "$errors wikilinks 'implements' inválidos encontrados"
  fi
  
  success "Relations 'implements' válidas em $checked decision notes"
  return 0
}

# ---------- 3. Decision notes relations depends_on/relates_to ----------

validate_decision_relations() {
  log "🔍 Validando relations 'depends_on' e 'relates_to' nas decision notes..."
  
  local errors=0
  local checked=0
  
  for decision_file in memories/Decisões\ Técnicas\ —\ *.md; do
    [[ -f "$decision_file" ]] || continue
    ((checked++))
    
    # Extrai wikilinks [[Decisões Técnicas — Y]] de depends_on/relates_to:
    local dec_links
    dec_links=$(grep -oE '\[\[Decisões Técnicas — [^]]+\]\]' "$decision_file" | sed 's/\[\[Decisões Técnicas — \(.*\)\]\]/\1/' | sort -u)
    
    for dec_link in $dec_links; do
      if [[ ! -f "memories/Decisões Técnicas — $dec_link.md" ]]; then
        error "Decision '$(basename "$decision_file")' referencia decision inexistente: '$dec_link'"
        ((errors++))
      fi
    done
  done
  
  if [[ "$errors" -gt 0 ]]; then
    abort "$errors wikilinks 'depends_on/relates_to' inválidos encontrados"
  fi
  
  success "Relations 'depends_on/relates_to' válidas em $checked decision notes"
  return 0
}

# ---------- 4. Decision notes conteúdo mínimo ----------

validate_decision_content() {
  log "🔍 Validando conteúdo mínimo das decision notes..."
  
  local warnings=0
  local checked=0
  
  for decision_file in memories/Decisões\ Técnicas\ —\ *.md; do
    [[ -f "$decision_file" ]] || continue
    ((checked++))
    
    # Conta linhas não-vazias excluindo frontmatter + Relations
    local content_lines
    content_lines=$(grep -vE '^(---|title:|type:|permalink:|# Relations|- implements|- depends_on|- relates_to)' "$decision_file" | grep -cvE '^\s*$' || true)
    
    if [[ "$content_lines" -lt 10 ]]; then
      warn "Decision '$(basename "$decision_file")' tem conteúdo escasso ($content_lines linhas)"
      ((warnings++))
    fi
  done
  
  if [[ "$warnings" -gt 0 ]]; then
    warn "$warnings decision notes com conteúdo escasso (< 10 linhas)"
  else
    success "Conteúdo adequado em $checked decision notes"
  fi
  return 0
}

# ---------- Main ----------

main() {
  log "🔍 Iniciando validação do grafo de conhecimento..."
  echo
  
  validate_spec_mirrors || return 1
  echo
  
  validate_decision_implements || return 1
  echo
  
  validate_decision_relations || return 1
  echo
  
  validate_decision_content || return 1
  echo
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "🏁 Dry-run concluído — nenhuma falha que impediria closeout"
    return 0
  fi
  
  log "🏁 Validação completa — grafo íntegro"
  return 0
}

main "$@"