# Explore Brief — <Nome da Change>

> Template de referência para alimentar `proposal.md` na fase `explore` do OpenSpec.
> Preencha cada seção e use como input ao criar a change com `/opsx-explore`,
> `/opsx-new-change` ou `/opsx-propose`. Quanto mais claro o brief, melhor o
> `proposal.md` gerado — e menos retrabalho depois.
>
> Nota: este arquivo é uma **convenção de referência** do projeto (não é
> descoberto automaticamente pelo comando `openspec templates`, que só lista
> os 4 templates do package: `proposal`/`spec`/`design`/`tasks`). O agente
> aponta para ele quando inicia a fase `explore`.

## 1. Contexto

O que existe hoje? Por que essa change precisa existir? Qual é o público e
por que isso importa agora?

<descreva em 1-3 parágrafos>

## 2. Objetivo

Resultado esperado em uma frase única e clara. Foque no **outcome**, não na
feature.

<uma frase>

## 3. Usuário-alvo

Quem usará a solução? Qual é a dor concreta que será resolvida? Inclua
cenários reais quando possível.

<descreva>

## 4. Escopo (nesta versão)

- <Funcionalidade 1>
- <Funcionalidade 2>
- <Funcionalidade 3>

## 5. Fora de escopo (explicitamente)

- <O que NÃO será feito agora>
- <O que pode parecer que entra, mas não entra>

## 6. Requisitos funcionais

- RF01: <Descrição clara, em forma de comportamento esperado>
- RF02: <...>
- RF03: <...>

## 7. Requisitos não funcionais

- RNF01: Segurança e privacidade (<detalhar>)
- RNF02: Observabilidade mínima (<logs / métricas>)
- RNF03: Testabilidade (<cobertura mínima esperada>)
- RNF04: Performance (<SLAs aplicáveis>)

## 8. Arquitetura inicial

Stack escolhida, módulos previstos, integrações externas, decisões já
tomadas com justificativa breve.

<descreva>

## 9. Critérios de aceite

- O sistema DEVE <comportamento testável>
- Os testes DEVEM <cobertura ou cenários específicos>
- A documentação DEVE <o que precisa estar pronto>

## 10. Riscos e validações

Liste riscos técnicos conhecidos e como cada um será validado.

- Risco 1: <...> → Validação: <...>
- Risco 2: <...> → Validação: <...>

## 10. Open Questions / Unknowns

Perguntas em aberto que, se respondidas, mudam o que será construído. Devem
ser espelhadas para `## Open Questions` do `design.md` (rule de design em
`openspec/config.yaml`). O instruction do artifact `tasks` procura essas
perguntas antes de gerar tasks — não cozinhe suposição implícita.

- **Q1**: <pergunta> | Owner: <pessoa/agente> | Spike/Research: <descrição do
  spike ou "n/a"> | Status: aberta | Resolvido em: <change/PR/N/A>
- **Q2**: <...>

> Quando não houver nenhuma, escreva "Nenhuma em aberto" — o placeholder
>: preserva auditabilidade (regra de design exige a seção, mesmo que vazia).

## 11. Spikes sugeridos

Investigações pontuais (código experimental, PoC, A/B de libs) que precisam
rodar para responder Open Questions ou decidir direção. Opcionais — listar só
quando existirem. Spike vira task no `tasks.md` via tipo Spike:
`- [ ] X.Y Spike: <pergunta> → decision em <arquivo>`.

- Spike 1: <pergunta/hipótese> → decision em: <arquivo onde o resultado será
  registrado (geralmente `design.md`)>
- Spike 2: <...>

## 12. Premissas

Hipóteses assumidas como verdadeiras que, se falsas, mudam o projeto.

- <Premissa 1>
- <Premissa 2>

## 13. Métricas de sucesso

Como saberemos, depois do lançamento, que a change deu certo?

<métrica(s) observável(eis)>

---

## Dica de uso

Não economize tempo no brief. Cada hora investida aqui evita 5 horas de
retrabalho depois. Ao terminar, peça ao agente para ler este brief e apontar
ambiguidades **antes** de iniciar `/opsx-propose` — ambiguidades não
resolvidas viram `proposal.md` vago, que vira `tasks.md` vago, que vira
implementação errada.
