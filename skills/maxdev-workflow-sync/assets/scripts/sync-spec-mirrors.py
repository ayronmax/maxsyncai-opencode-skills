#!/usr/bin/env python3
"""Sync all spec mirrors to Basic Memory using KnowledgeClient directly.

Robust, parallel, idempotent replacement for the slow sequential CLI loop.
"""
import argparse
import asyncio
import hashlib
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional

try:
    from basic_memory.config import ConfigManager
    from basic_memory.mcp.clients import KnowledgeClient
    from basic_memory.mcp.project_context import get_project_client
    from basic_memory.mcp.tools import list_memory_projects
except ImportError as e:
    print(f"Erro: basic_memory package não encontrado. Instale com: pip install basic-memory", file=sys.stderr)
    print(f"Detalhe: {e}", file=sys.stderr)
    sys.exit(1)


class SpecMirrorSyncer:
    def __init__(self, project: str, max_concurrency: int = 10, max_retries: int = 3):
        self.project = project
        self.max_concurrency = max_concurrency
        self.max_retries = max_retries
        self.semaphore: Optional[asyncio.Semaphore] = None
        self.knowledge_client: Optional[KnowledgeClient] = None
        self.project_external_id: Optional[str] = None
        self._client_ctx = None
        self._client = None

    async def __aenter__(self):
        # Resolve project external_id via API
        projects_result = await list_memory_projects(output_format="json")
        project_data = next((p for p in projects_result.get("projects", []) if p["name"] == self.project), None)
        if not project_data:
            raise ValueError(f"Project '{self.project}' not found in Basic Memory")

        self.project_external_id = project_data["external_id"]
        self.semaphore = asyncio.Semaphore(self.max_concurrency)

        # Get and KEEP the client context manager alive
        self._client_ctx = get_project_client(self.project)
        self._client, _ = await self._client_ctx.__aenter__()
        self.knowledge_client = KnowledgeClient(self._client, self.project_external_id)

        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self._client_ctx:
            await self._client_ctx.__aexit__(exc_type, exc_val, exc_tb)

    def _compute_checksum(self, content: str) -> str:
        return hashlib.sha256(content.encode()).hexdigest()

    def _spec_to_entity(self, spec_name: str, content: str) -> dict:
        title = f"Spec — {spec_name}"
        return {
            "title": title,
            "directory": "/",
            "note_type": "spec",
            "content": content,
            "entity_metadata": {
                "tags": ["spec", self.project.replace("_", "-"), spec_name]
            },
        }

    async def _upsert_spec(self, spec_name: str, content: str) -> tuple[str, bool]:
        """Create or update a spec mirror. Returns (spec_name, success)."""
        async with self.semaphore:
            entity_data = self._spec_to_entity(spec_name, content)

            for attempt in range(self.max_retries):
                try:
                    # Try to create first
                    try:
                        await self.knowledge_client.create_entity(entity_data)
                        return spec_name, True
                    except Exception as e:
                        if "409" in str(e) or "conflict" in str(e).lower() or "already exists" in str(e).lower():
                            # Entity exists, update it
                            file_path = f"Spec — {spec_name}.md"
                            entity_id = await self.knowledge_client.resolve_entity(file_path, strict=True)
                            await self.knowledge_client.update_entity(entity_id, entity_data)
                            return spec_name, True
                        raise
                except Exception as e:
                    if attempt == self.max_retries - 1:
                        print(f"  ✗ {spec_name}: falhou após {self.max_retries} tentativas: {e}", file=sys.stderr)
                        return spec_name, False
                    wait_time = 2 ** attempt
                    print(f"  ↻ {spec_name}: tentativa {attempt + 1} falhou, retry em {wait_time}s...", file=sys.stderr)
                    await asyncio.sleep(wait_time)

            return spec_name, False

    async def sync_all(self, specs_dir: Path) -> tuple[int, int]:
        """Sync all spec.md files. Returns (success_count, fail_count)."""
        spec_files = list(specs_dir.glob("*/spec.md"))
        if not spec_files:
            print(f"Nenhuma spec encontrada em {specs_dir}")
            return 0, 0

        print(f"Encontradas {len(spec_files)} specs para sincronizar...")

        # Read all files in parallel (local I/O)
        def read_spec(spec_file: Path) -> tuple[str, str]:
            spec_name = spec_file.parent.name
            content = spec_file.read_text(encoding="utf-8")
            return spec_name, content

        with ThreadPoolExecutor(max_workers=min(10, len(spec_files))) as executor:
            spec_data = list(executor.map(read_spec, spec_files))

        # Upsert all in parallel with controlled concurrency
        tasks = [self._upsert_spec(name, content) for name, content in spec_data]
        results = await asyncio.gather(*tasks)

        success = sum(1 for _, ok in results if ok)
        failed = len(results) - success

        for name, ok in results:
            status = "✓" if ok else "✗"
            print(f"  {status} {name}")

        return success, failed


async def main():
    parser = argparse.ArgumentParser(description="Sync spec mirrors to Basic Memory")
    parser.add_argument("--project", required=True, help="Basic Memory project name")
    parser.add_argument("--specs-dir", default="openspec/specs", help="Directory containing spec subdirectories")
    parser.add_argument("--concurrency", type=int, default=10, help="Max concurrent API calls")
    parser.add_argument("--retries", type=int, default=3, help="Max retries per spec")
    args = parser.parse_args()

    specs_dir = Path(args.specs_dir).resolve()
    if not specs_dir.exists():
        print(f"Diretório não encontrado: {specs_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Sincronizando specs de {specs_dir} para projeto '{args.project}'...")

    async with SpecMirrorSyncer(args.project, args.concurrency, args.retries) as syncer:
        success, failed = await syncer.sync_all(specs_dir)

    print(f"\nResultado: {success} sincronizadas, {failed} falharam")
    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    import os
    os.environ["LOGFIRE_IGNORE_NO_CONFIG"] = "1"
    asyncio.run(main())