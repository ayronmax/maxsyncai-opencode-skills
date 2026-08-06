# TESTING.md

> Guia de performance e isolamento de testes. Template gerado por
> `maxdev-workflow-sync` v{{WORKFLOW_VERSION}}.

## Comandos por tier

Targets canônicos do Makefile (ver `make help` para a lista atualizada):

| Target | Quando usar | Stack |
|---|---|---|
| `make test-backend-fast` | iteração local (~30s) — unit tests isolados | {{TEST_FRAMEWORK_BACKEND}} |
| `make test-backend` | pré-PR (~10 min) — sequencial, determinístico | {{TEST_FRAMEWORK_BACKEND}} |
| `make test-backend-integration` | CI / validação de contrato | {{TEST_FRAMEWORK_BACKEND}} |
| `make test-frontend` | unit/component do frontend | {{TEST_FRAMEWORK_FRONTEND}} |
| `make test` | tudo (backend + frontend, sequencial) | ambos |
| `make lint` | ruff + eslint | {{LINTER_BACKEND}} / {{LINTER_FRONTEND}} |
| `make check` | lint + fast tests + schemas | pré-push rápido |

## Paralelização

- **Backend**:.Configure paralelização no framework (ex.: `pytest -n auto` via
  `pytest-xdist`). Documente aqui o limite recomendado (ex.: `-n 4` em CI).
- **Frontend**:use threads do framework (ex.: `vitest --threads`).
- **Cuidado**: testes de integração geralmente NÃO são paralelos-safe — rode
  em processo único ou com isolamento de banco por worker.

## Isolamento

- **Banco de dados**: use fixture de DB transacional (rollback por teste) ou
  schema efêmero por teste. Nunca compartilhe estado entre testes.
- **Mocks**: preferir mocks no nível de borda (HTTP/DB driver) sobre mocks
  internos — preserva a fidelidade do comportamento.
- **Timeouts**: configure timeout por teste (ex.: `@pytest.mark.timeout(10)`)
  para capturar hangs early.

## Coverage

- **Meta**: documente a meta de coverage do projeto (ex.: 70% backend, 60%
  frontend). Configure gate no CI se aplicável.
- **Comando**: `make test-backend COVERAGE=1` (ou equivalente do framework).

## Troubleshooting de lentidão

- **Backend lento**: rode `make test-backend-fast` para unit; reserve
  `make test-backend` para pré-PR. Identifique testes lentos com
  `--durations=10` (pytest).
- **Frontend lento**: rode `make test-frontend -- --reporter=verbose` para
  identificar testes pendurados.
- **Pre-commit lento**: se o hook de testes demorar mais que X minutos, considere
  mover testes pesados para `pre-push` (deixando `pre-commit` só com lint).
- **CI vs local**: se CI quebrar onde local passa, verifique flakes (testes
  não-determinísticos) e versione pinning de dependências.