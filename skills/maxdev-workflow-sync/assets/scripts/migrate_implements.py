#!/usr/bin/env python3
"""migrate_implements.py — Converte `implements: \`cap\`` para `implements: [[Spec — cap]]`.

Lê todas as notas de decisão em memories/ e converte o formato antigo
de implements (code-formatting) para o novo formato (wiki links).

Uso: uv run python scripts/migrate_implements.py [--dry-run]
"""

import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEMORIES_DIR = PROJECT_ROOT / "memories"
SPECS_DIR = PROJECT_ROOT / "openspec" / "specs"


def get_available_specs() -> set[str]:
    """Lista specs disponíveis em openspec/specs/."""
    if not SPECS_DIR.exists():
        return set()
    return {d.name for d in SPECS_DIR.iterdir() if d.is_dir()}


def migrate_note(filepath: Path, specs: set[str], dry_run: bool) -> bool:
    """Migra uma nota de decisão do formato antigo para o novo."""
    content = filepath.read_text()
    original = content
    changed = False

    # Padrão antigo: implements: `cap` (path)
    def replace_implements(m):
        cap = m.group(1).strip()
        # Remove path suffix se houver
        cap_clean = cap.split("/")[0].strip()
        if cap_clean in specs:
            return f"implements: [[Spec — {cap_clean}]]"
        # Se a spec não existe, mantém o formato antigo
        return m.group(0)

    content = re.sub(
        r"implements:\s*`([^`]+)`\s*\([^)]*\)",
        replace_implements,
        content,
    )

    # Formato sem parênteses: implements: `cap`
    def replace_simple(m):
        cap = m.group(1).strip()
        if cap in specs:
            return f"implements: [[Spec — {cap}]]"
        return m.group(0)

    content = re.sub(
        r"implements:\s*`([^`]+)`\s*$",
        replace_simple,
        content,
        flags=re.MULTILINE,
    )

    # depends_on sem wiki link: depends_on: `change-name`
    def replace_depends(m):
        target = m.group(1).strip()
        return f"depends_on: [[Decisões Técnicas — {target}]]"

    content = re.sub(
        r"depends_on:\s*`([^`]+)`",
        replace_depends,
        content,
    )

    if content != original:
        changed = True
        if not dry_run:
            filepath.write_text(content)

    return changed


def main():
    dry_run = "--dry-run" in sys.argv
    specs = get_available_specs()

    print(f"✓ {len(specs)} specs disponíveis em openspec/specs/")
    print()

    migrated = 0
    for note_file in sorted(MEMORIES_DIR.glob("Decisões Técnicas*.md")):
        changed = migrate_note(note_file, specs, dry_run)
        if changed:
            migrated += 1
            status = "DRY-RUN" if dry_run else "MIGRADO"
            print(f"  [{status}] {note_file.name}")

    if dry_run:
        print(f"\n✓ Dry-run: {migrated} notas seriam migradas")
        print("  Execute sem --dry-run para aplicar.")
    else:
        print(f"\n✓ {migrated} notas migradas para o novo formato")


if __name__ == "__main__":
    main()
