#!/usr/bin/env python3
"""update_canvas.py — Gera/atualiza o Knowledge Graph canvas do projeto.

Lê o índice do projeto, notas de decisão e specs do Basic Memory,
extrai relações e gera um JSON Canvas 1.0 compatível com Obsidian.

Uso: python3 scripts/update_canvas.py [--dry-run]
"""

import json
import re
import sys
from pathlib import Path

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEMORIES_DIR = PROJECT_ROOT / "memories"
SPECS_DIR = PROJECT_ROOT / "openspec" / "specs"
CANVAS_DIR = MEMORIES_DIR / "canvas"
INDEX_FILE = None  # Será detectado automaticamente

# Cores por domínio (IDs 1-6 do Obsidian)
COLORS = {
    "index": "1",       # vermelho — índice central
    "core": "2",        # laranja — foundation/core
    "features": "3",    # verde — features
    "tooling": "4",     # azul — tooling/infra
    "visual": "4",      # azul
    "fixes": "5",       # roxo — fixes
    "spec": "6",        # cinza — specs
}

# Layout por domínio (X base, Y base)
DOMAIN_POSITIONS = {
    "index": (600, 0),
    "core": (-20, 180),
    "features": (-20, 360),
    "tooling": (-20, 540),
    "visual": (-20, 720),
    "fixes": (1060, 180),
}

DOMAIN_COLUMNS = {
    "index": 1,
    "core": 3,
    "features": 3,
    "tooling": 3,
    "visual": 1,
    "fixes": 1,
}


def classify_domain(tags: list[str], title: str) -> str:
    """Classifica uma decisão em um domínio genérico baseado em tags e título."""
    tag_str = " ".join(tags).lower()
    title_lower = title.lower()

    if any(t in title_lower for t in ["fix", "bug", "error", "hotfix"]):
        return "fixes"
    if any(t in title_lower for t in ["redesign", "visual", "ui", "shell", "css"]):
        return "visual"
    if any(t in tag_str for t in ["tooling", "infra", "devops", "ci", "workflow", "sync", "config"]):
        return "tooling"
    if any(t in tag_str for t in ["foundation", "core", "setup", "init", "bootstrap"]):
        return "core"
    return "core"


def parse_frontmatter(content: str) -> dict:
    """Extrai frontmatter YAML entre --- usando PyYAML."""
    m = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not m:
        return {}
    if HAS_YAML:
        try:
            return yaml.safe_load(m.group(1)) or {}
        except yaml.YAMLError:
            pass
    # Fallback manual
    fm = {}
    for line in m.group(1).split("\n"):
        if ":" in line and not line.strip().startswith("-"):
            key, _, val = line.partition(":")
            val = val.strip()
            if val.startswith("[") and val.endswith("]"):
                val = [v.strip().strip('"').strip("'") for v in val[1:-1].split(",")]
            fm[key.strip()] = val
    return fm


def extract_wikilinks(text: str) -> list[str]:
    """Extrai wiki links do texto."""
    return re.findall(r"\[\[([^\]]+)\]\]", text)


def extract_implements(text: str) -> list[str]:
    """Extrai capabilities da seção implements."""
    implements = []
    # Formato novo: [[Spec — cap]]
    for m in re.finditer(r"implements:\s*\[\[Spec\s*[—–-]\s*([^\]]+)\]\]", text):
        implements.append(m.group(1).strip())
    # Formato antigo: `cap` (path)
    if not implements:
        for m in re.finditer(r"implements:\s*`([^`]+)`", text):
            implements.append(m.group(1).strip())
    return implements


def discover_index() -> Path | None:
    """Descobre o arquivo de índice do projeto (nome em CAIXA ALTA)."""
    for f in MEMORIES_DIR.glob("*.md"):
        name = f.stem
        if name == name.upper() and len(name) > 2:
            # Verifica se contém wiki links → é um índice
            content = f.read_text()
            if re.search(r"\[\[Decisões Técnicas", content):
                return f
    return None


def build_canvas() -> tuple[dict, str]:
    """Constrói o canvas completo. Retorna (canvas_dict, index_name)."""
    nodes = []
    edges = []

    # 1. Índice central
    idx = discover_index()
    if not idx:
        print("✗ Índice não encontrado em memories/", file=sys.stderr)
        sys.exit(1)

    idx_content = idx.read_text()
    idx_name = idx.stem
    nodes.append({
        "id": "idx-root",
        "type": "file",
        "file": f"{idx_name}.md",
        "x": 600, "y": 0,
        "width": 300, "height": 80,
        "color": COLORS["index"],
    })
    idx_x, idx_y = 600, 0

    # 2. Extrai decisões do índice
    decision_links = extract_wikilinks(idx_content)
    decisions = [d for d in decision_links if d.startswith("Decisões Técnicas")]

    # 3. Para cada decisão, lê o arquivo e extrai relações
    domain_positions = {k: list(v) for k, v in DOMAIN_POSITIONS.items()}
    domain_items = {k: [] for k in DOMAIN_COLUMNS}  # domain → list of (i, title)
    dec_nodes = {}  # title → node_id

    # Primeiro passe: agrupar por domínio
    for i, dec_title in enumerate(decisions):
        dec_file = MEMORIES_DIR / f"{dec_title}.md"
        if not dec_file.exists():
            continue
        content = dec_file.read_text()
        fm = parse_frontmatter(content)
        tags = fm.get("tags", [])
        domain = classify_domain(tags, dec_title)
        if domain not in domain_items:
            domain_items[domain] = []
        domain_items[domain].append((i, dec_title, dec_file))

    # Segundo passe: posicionar sem colisões entre domínios
    current_y_offset = 0
    Y_GAP = 200  # gap vertical entre linhas

    for domain, items in domain_items.items():
        if domain in domain_positions:
            base_x, domain_base_y = domain_positions[domain]
            base_y = domain_base_y + current_y_offset
        else:
            base_x, base_y = 0, 800 + current_y_offset

        max_cols = DOMAIN_COLUMNS.get(domain, 1)
        spacing = 360

        for idx, (i, dec_title, dec_file) in enumerate(items):
            node_id = f"dec-{i}"
            content = dec_file.read_text()
            fm = parse_frontmatter(content)
            tags = fm.get("tags", [])

            col_idx = idx % max_cols
            row = idx // max_cols

            x = base_x + (col_idx * spacing)
            y = base_y + (row * Y_GAP)

            nodes.append({
                "id": node_id,
                "type": "file",
                "file": f"{dec_title}.md",
                "x": x, "y": y,
                "width": 320, "height": 80,
                "color": COLORS.get(domain, "6"),
            })
            dec_nodes[dec_title] = node_id

            # Aresta: índice → decisão
            edges.append({
                "id": f"e-idx-{i}",
                "fromNode": "idx-root",
                "toNode": node_id,
                "fromSide": "bottom",
                "toSide": "top",
                "label": "index",
            })

            # Relações: depends_on, relates_to
            for m in re.finditer(r"(depends_on|relates_to):\s*\[\[([^\]]+)\]\]", content):
                rel_type, target = m.group(1), m.group(2)
                if target in dec_nodes:
                    edges.append({
                        "id": f"e-{node_id}-{dec_nodes[target]}",
                        "fromNode": node_id,
                        "toNode": dec_nodes[target],
                        "fromSide": "left",
                        "toSide": "right",
                        "label": rel_type,
                    })

    # 4. Specs
    spec_nodes = {}
    if SPECS_DIR.exists():
        specs = sorted([d.name for d in SPECS_DIR.iterdir() if d.is_dir()])
        for j, spec_name in enumerate(specs):
            spec_id = f"spec-{j}"
            spec_file = SPECS_DIR / spec_name / "spec.md"
            spec_exists = spec_file.exists()

            col = j % 8
            row = j // 8
            sx = -380 + col * 240
            sy = 1080 + row * 180

            node = {
                "id": spec_id,
                "type": "text",
                "text": f"# {spec_name}\n`openspec/specs/{spec_name}/`",
                "x": sx, "y": sy,
                "width": 240, "height": 80,
            }

            # Verifica se existe nota-espelho no Basic Memory
            mirror = MEMORIES_DIR / f"Spec — {spec_name}.md"
            if mirror.exists():
                node["type"] = "file"
                node["file"] = f"Spec — {spec_name}.md"

            nodes.append(node)
            spec_nodes[spec_name] = spec_id

    # 5. Arestas: decisão → spec (implements)
    for dec_title, dec_id in dec_nodes.items():
        dec_file = MEMORIES_DIR / f"{dec_title}.md"
        if not dec_file.exists():
            continue
        content = dec_file.read_text()
        for cap in extract_implements(content):
            # Normaliza: remove path, pega só o nome
            cap_clean = cap.split("/")[0].strip()
            if cap_clean in spec_nodes:
                edges.append({
                    "id": f"e-{dec_id}-{spec_nodes[cap_clean]}",
                    "fromNode": dec_id,
                    "toNode": spec_nodes[cap_clean],
                    "fromSide": "bottom",
                    "toSide": "top",
                    "label": "implements",
                })

    return {"nodes": nodes, "edges": edges}, idx_name


def main():
    dry_run = "--dry-run" in sys.argv

    canvas, idx_name = build_canvas()

    if dry_run:
        print(json.dumps(canvas, indent=2, ensure_ascii=False))
        print(f"\n✓ Dry-run: {len(canvas['nodes'])} nós, {len(canvas['edges'])} arestas")
        return

    CANVAS_DIR.mkdir(parents=True, exist_ok=True)
    canvas_file = CANVAS_DIR / f"{idx_name} - Knowledge Graph.canvas"

    with open(canvas_file, "w") as f:
        json.dump(canvas, f, indent=2, ensure_ascii=False)

    print(f"✓ Canvas atualizado: {canvas_file}")
    print(f"  {len(canvas['nodes'])} nós, {len(canvas['edges'])} arestas")


if __name__ == "__main__":
    main()
