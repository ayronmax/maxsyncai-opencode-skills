# maxsyncai-opencode-skills

Bundle de skills opencode da MaxSyncai. Atualmente inclui:

- **maxdev-workflow-sync** — bootstrap, sync e drift-check do workflow MaxDev
  OpenSpec em qualquer repositório. Veja
  [`skills/maxdev-workflow-sync/README.md`](skills/maxdev-workflow-sync/README.md)
  para o guia de uso completo.

## Instalar (1 linha)

Adicione em `~/.config/opencode/opencode.jsonc`:

```jsonc
{
  "plugin": [
    "maxsyncai-opencode-skills@git+https://github.com/maxsyncai/maxsyncai-opencode-skills.git"
  ]
}
```

Reinicie o opencode. Todas as skills deste package (atualmente
`/maxdev-workflow-sync`) ficam disponíveis em qualquer projeto da máquina.

## Auto-update

Opencode re-fetch do package no startup. Para bump de versão: bump
`package.json.version` no repo, tag git, push. Cada dev recebe a nova versão
no próximo startup.

## Release

```bash
# no repo do package:
bump package.json version (semver)
git add package.json && git commit -m "chore(release): vX.Y.Z"
git tag vX.Y.Z && git push --tags
```

## Como adicionar nova skill neste package

1. Crie `skills/<nova-skill>/SKILL.md` (com frontmatter `name`/`description`)
2. Adicione scripts/assets/references em `skills/<nova-skill>/` conforme precisar
3. Commit + push. Plugin entry já registra `skills/` inteiro — auto-discovers a nova skill
4. Bump `package.json.version`. Tag. Push.

## Repositórios relacionados

- [`maxsyncai/openspec-workflow-template`](https://github.com/maxsyncai/openspec-workflow-template)
  — repo canônico de **overrides** (opcional) para os 9 canônicos + 5 starters
  consumidos pela skill `maxdev-workflow-sync`.