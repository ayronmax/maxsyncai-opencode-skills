# Design Template — <Nome da Change>

> Template de referência suplementar para alimentar `design.md` na fase
> `propose` do OpenSpec. Diferente dos 4 templates oficiais
> (`proposal`/`spec`/`design`/`tasks`) que o CLI descobre via `openspec
> templates`, este arquivo é uma **convenção de referência** do projeto — não é
> descoberto automaticamente. O agente aponta para ele quando inicia a fase
> `propose` e precisa do detalhe de seções/etiqueta.

## Context

Estado atual e restrições que moldam a abordagem. Não restates a motivação —
ela mora em `proposal.md` (seção Why).

<descreva em 1-3 parágrafos>

## Goals / Non-Goals

**Goals:**
- <o que o design visa alcançar>

**Non-Goals:**
- <o que está explicitamente fora de escopo>

## Decisions

Cada decisão numerada, com **alternativas consideradas** e **racional**. Uma
decisão sem alternativa considerada é frágil — registre o caminho não-tomado.

### D1 — <Nome da decisão>

<explicação da abordagem e racional>

**Alternativas consideradas:**
- <alternativa A>: <por que rejeitada>
- <alternativa B>: <por que rejeitada>

### D2 — <...>

## Risks / Trade-offs

Riscos técnicos conhecidos com **mitigações**. Trade-offs aceitos com custo
explícito.

- Risco 1: <...> → Mitigação: <...>
- Trade-off 1: <...>

## Open Questions

Obrigatório — rule de design em `openspec/config.yaml` exige esta seção (mesmo
que "Nenhuma em aberto" como placeholder). O instruction do artifact `tasks`
do package OpenSpec procura esta seção antes de gerar tasks: "check design.md
for Open Questions. If any of them would change what gets built, resolve them
with the user first — do not bake an unstated assumption into the task list".
**Não criar esta seção é bug latente.**

Formato canônico:

```
## Open Questions

- **Q1**: <pergunta> | Owner: <pessoa/agente> | Spike/Research: <descrição do
  spike ou "n/a"> | Status: aberta | Resolvido em: <change/PR/N/A>
- **Q2**: <...>
```

Ou, quando não houver nenhuma:

```
## Open Questions

Nenhuma em aberto — todas as decisões foram resolvidas em <referência ao
contexto onde (ex.: conversa com o usuário, design D<N>, GATE <N>)>.
```

Open Questions resolvidas permanecem listadas com `Status: resolvida` e
`Resolvido em: <referência>`. Isso preserva a trilha de auditoria — o leitor
futuro vê o que foi perguntado, quando e por quem.

## Migration Plan

Incluir quando houver remoção/migração de tooling, quebra de compatibilidade
ou rollback não-trivial. Caso contrário, omitir.

1. <passo>
2. <passo>

Rollback: <como reverter via git/manualmente>
