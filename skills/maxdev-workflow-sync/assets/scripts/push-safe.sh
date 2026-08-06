#!/bin/bash

set -e

MODE="${1:---fast}"

case "$MODE" in
  --fast)
    echo "🚀 Modo rápido: lint + validações + testes unitários"
    make lint
    openspec validate --changes
    cd backend && uv run pytest tests/unit/ -n auto
    cd ../frontend && npm run test
    ;;
  --full)
    echo "🔍 Modo completo: lint + validações + todos os testes"
    make lint
    openspec validate --changes
    make test
    ;;
  --validate-only)
    echo "✅ Apenas validações (sem testes)"
    make lint
    openspec validate --changes
    ;;
  *)
    echo "Uso: $0 [--fast|--full|--validate-only]"
    exit 1
    ;;
esac
echo "✅ Validações passaram. Fazendo push..."

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  echo "❌ Bloqueado: push direto para '$branch'. Use uma feature branch."
  exit 1
fi

git push origin HEAD
