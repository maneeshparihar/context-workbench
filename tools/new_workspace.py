#!/usr/bin/env python3
"""
Context Workbench — create engagement folders from blueprints, or sync latest blueprint files.

Reads registry.json from the repository root (parent of tools/), not from tools/ — it is the
catalog for the whole repo next to BLUEPRINTS/.

Parallel CLIs (same commands, no Python): tools/new-workspace.sh (Bash + jq),
tools/new-workspace.ps1 (Windows PowerShell 5.1+). Prefer Python when you extend logic in one place.

Create (named flags — robust; omit --blueprint for default):
  python tools/new_workspace.py create --name="Olive Grove"
  python tools/new_workspace.py create --blueprint=presales --name=olive-grove
  python tools/new_workspace.py create -b presales -n "Olive Grove" --parent ./engagements

Create (positional — same as before; relative paths use --parent, default PROJECTS/):
  python tools/new_workspace.py create "Acme Corporation"
  python tools/new_workspace.py create presales "Acme Corporation"
  python tools/new_workspace.py create ./my-folder
  python tools/new_workspace.py create presales ./engagements/custom-name

Create (--path for explicit folder):
  python tools/new_workspace.py create --path=./engagements/olive
  python tools/new_workspace.py create -b presales --path ./engagements/olive

Each new workspace gets WORKBENCH.json (blueprint id/version, client slug, timestamps) for sync.

Sync:
  python tools/new_workspace.py sync ./presales_acmecorpor
  python tools/new_workspace.py sync presales ./some/path   # legacy: blueprint + path

Blueprint metadata: _shared carries a stub; each overlay’s metadata.json lands in the workspace root (last wins).
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

WORKBENCH_FILENAME = "WORKBENCH.json"
MAX_CLIENT_SLUG_LEN = 10
# Default parent for `create` (under the context-bench repo root).
DEFAULT_PROJECTS_DIR = "PROJECTS"
DEFAULT_BLUEPRINT_ID = "default"


def repo_root(script_path: Path) -> Path:
    return script_path.resolve().parent.parent


def load_registry(root: Path) -> dict:
    path = root / "registry.json"
    if not path.is_file():
        sys.stderr.write(f"Missing registry.json at {path}\n")
        sys.exit(1)
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def blueprint_overlay_dir(repo: Path, registry: dict, blueprint_id: str) -> Path:
    overlays = registry["blueprints"].get(blueprint_id, {}).get("overlays") or []
    if overlays:
        return repo / overlays[0]
    return repo / registry["sharedRoot"]


def load_blueprint_metadata(repo: Path, registry: dict, blueprint_id: str) -> dict:
    d = blueprint_overlay_dir(repo, registry, blueprint_id)
    meta_path = d / "metadata.json"
    if meta_path.is_file():
        with meta_path.open(encoding="utf-8") as f:
            return json.load(f)
    entry = registry["blueprints"].get(blueprint_id) or {}
    return {
        "blueprint_id": blueprint_id,
        "version": "0",
        "label": entry.get("label", ""),
        "description": entry.get("description", ""),
    }


def normalize_client_slug(raw: str, max_len: int = MAX_CLIENT_SLUG_LEN) -> str:
    s = raw.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "", s)
    if not s:
        s = "client"
    return s[:max_len]


def blueprint_folder_prefix(blueprint_id: str) -> str:
    return blueprint_id.replace("-", "_").lower()


def default_folder_name(blueprint_id: str, client_raw: str) -> str:
    return f"{blueprint_folder_prefix(blueprint_id)}_{normalize_client_slug(client_raw)}"


def is_explicit_path(arg: str) -> bool:
    s = arg.strip()
    if not s or s in (".", ".."):
        return True
    if "/" in s or "\\" in s:
        return True
    p = Path(s)
    if p.is_absolute():
        return True
    if len(s) > 1 and s[1] == ":" and s[0].isalpha():
        return True
    return False


def copy_tree_merge(src: Path, dst: Path) -> None:
    if not src.is_dir():
        sys.stderr.write(f"Missing directory: {src}\n")
        sys.exit(1)
    for path in src.rglob("*"):
        if path.is_dir():
            continue
        rel = path.relative_to(src)
        out = dst / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, out)


def merge_layers(repo: Path, registry: dict, blueprint_id: str, target: Path) -> None:
    meta = registry["blueprints"].get(blueprint_id)
    if not meta:
        sys.stderr.write(f'Unknown blueprint "{blueprint_id}". Use: list\n')
        sys.exit(1)
    overlays = meta.get("overlays") or []
    shared = repo / registry["sharedRoot"]
    copy_tree_merge(shared, target)
    for rel in overlays:
        copy_tree_merge(repo / rel, target)


def reset_directories(target: Path, names: list[str]) -> None:
    for name in names:
        d = target / name
        d.mkdir(parents=True, exist_ok=True)
        for child in d.iterdir():
            if child.is_file():
                child.unlink()
            else:
                shutil.rmtree(child)
        (d / ".gitkeep").write_text("", encoding="utf-8")


def read_workbench_blueprint_id(target: Path) -> str | None:
    p = target / WORKBENCH_FILENAME
    if not p.is_file():
        return None
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    bp = data.get("blueprint") or {}
    bid = bp.get("id")
    return str(bid) if bid else None


def write_workbench_with_repo(
    target: Path,
    repo: Path,
    registry: dict,
    blueprint_id: str,
    *,
    client_display: str | None,
    client_slug: str | None,
    directory_name: str,
) -> None:
    bp_meta = load_blueprint_metadata(repo, registry, blueprint_id)
    reg_entry = registry["blueprints"].get(blueprint_id) or {}
    doc: dict = {
        "schema_version": 1,
        "blueprint": {
            "id": blueprint_id,
            "version": str(bp_meta.get("version", "0")),
            "label": bp_meta.get("label") or reg_entry.get("label", ""),
            "role": bp_meta.get("role"),
        },
        "engagement": {
            "client_display_name": client_display,
            "client_slug": client_slug,
        },
        "paths": {"directory_name": directory_name},
        "registry": {"version": registry.get("version", 1)},
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "generator": {"tool": "tools/new_workspace.py", "kind": "create"},
    }
    (target / WORKBENCH_FILENAME).write_text(
        json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def update_workbench_after_sync(
    target: Path,
    repo: Path,
    registry: dict,
    blueprint_id: str,
) -> None:
    p = target / WORKBENCH_FILENAME
    if p.is_file():
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            data = {"schema_version": 1}
    else:
        data = {"schema_version": 1}
    bp_meta = load_blueprint_metadata(repo, registry, blueprint_id)
    data["last_synced_utc"] = datetime.now(timezone.utc).isoformat()
    data["last_sync_blueprint"] = {
        "id": blueprint_id,
        "version": str(bp_meta.get("version", "0")),
    }
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def cmd_list(repo: Path, registry: dict) -> None:
    print("Blueprints (id - label)\n")
    for bid, meta in registry["blueprints"].items():
        desc = meta.get("description") or ""
        suffix = f" - {desc}" if desc else ""
        print(f"  {bid}\n    {meta.get('label', '')}{suffix}\n")


def resolve_create_target(
    parent: Path,
    blueprint_id: str,
    name_or_path: str,
) -> tuple[Path, str | None, str | None, str]:
    """
    Returns (target_path, client_display, client_slug, directory_name_for_workbench).
    """
    if is_explicit_path(name_or_path):
        target = Path(name_or_path).expanduser()
        if not target.is_absolute():
            target = (parent / target).resolve()
        else:
            target = target.resolve()
        return target, None, None, target.name

    slug = normalize_client_slug(name_or_path)
    folder = default_folder_name(blueprint_id, name_or_path)
    target = (parent / folder).resolve()
    return target, name_or_path.strip(), slug, folder


def parse_create_positional(registry: dict, positional: list[str]) -> tuple[str, str]:
    bps = registry.get("blueprints") or {}
    if len(positional) == 1:
        if DEFAULT_BLUEPRINT_ID not in bps:
            sys.stderr.write(
                f'registry.json must define a "{DEFAULT_BLUEPRINT_ID}" blueprint for single-argument create.\n'
            )
            sys.exit(1)
        return DEFAULT_BLUEPRINT_ID, positional[0]
    if len(positional) == 2:
        bid, name = positional[0], positional[1]
        if bid not in bps:
            sys.stderr.write(f'Unknown blueprint "{bid}". Use: list\n')
            sys.exit(1)
        return bid, name
    sys.stderr.write(
        "create: expected one or two positional arguments, or use --name / --path:\n"
        f'  create "Client or path"                    # blueprint: {DEFAULT_BLUEPRINT_ID}\n'
        '  create presales "Client or path"\n'
        f'  create --name "Client" [--blueprint {DEFAULT_BLUEPRINT_ID}]\n'
        "  create --path ./folder [--blueprint presales]\n"
    )
    sys.exit(1)


def resolve_create_blueprint_and_target(registry: dict, args: argparse.Namespace) -> tuple[str, str]:
    """
    Returns (blueprint_id, name_or_path) for resolve_create_target.
    name_or_path is either a client label (--name) or a path string (--path or positional).
    """
    pos = list(args.positional)
    has_name = args.client_name is not None
    has_path = args.workspace_path is not None
    has_flags = has_name or has_path
    bp_opt = args.blueprint

    if has_flags and pos:
        sys.stderr.write(
            "create: do not mix --name/--path with positional arguments.\n"
            "Use either flags or positional form.\n"
        )
        sys.exit(1)
    if bp_opt is not None and pos:
        sys.stderr.write(
            "create: do not combine --blueprint with positional arguments.\n"
            'Use: create --blueprint ID --name "..."  or  create --blueprint ID --path PATH\n'
        )
        sys.exit(1)

    if has_flags:
        bid = bp_opt if bp_opt is not None else DEFAULT_BLUEPRINT_ID
        bps = registry.get("blueprints") or {}
        if bid not in bps:
            sys.stderr.write(f'Unknown blueprint "{bid}". Use: list\n')
            sys.exit(1)
        if bid == DEFAULT_BLUEPRINT_ID and DEFAULT_BLUEPRINT_ID not in bps:
            sys.stderr.write(
                f'registry.json must define a "{DEFAULT_BLUEPRINT_ID}" blueprint '
                "when --blueprint is omitted.\n"
            )
            sys.exit(1)
        if has_name:
            return bid, args.client_name
        return bid, args.workspace_path

    if pos:
        return parse_create_positional(registry, pos)

    sys.stderr.write(
        "create: missing target. Examples:\n"
        f'  create --name "Olive Grove"\n'
        "  create --blueprint=presales --name=olive-grove\n"
        "  create --path ./engagements/olive\n"
        f'  create "Acme"   # shorthand for default blueprint + name\n'
    )
    sys.exit(1)


def cmd_create(args: argparse.Namespace, repo: Path, registry: dict) -> None:
    blueprint_id, name_or_path = resolve_create_blueprint_and_target(registry, args)
    if args.parent is not None:
        parent = Path(args.parent).expanduser().resolve()
    else:
        parent = (repo / DEFAULT_PROJECTS_DIR).resolve()
    parent.mkdir(parents=True, exist_ok=True)
    target, client_display, client_slug, dir_name = resolve_create_target(
        parent, blueprint_id, name_or_path
    )
    if target.exists() and any(target.iterdir()):
        sys.stderr.write(
            f"Refusing to write into non-empty directory:\n  {target}\n"
            "Remove contents, choose another path, or use sync to refresh an existing workspace.\n"
        )
        sys.exit(1)
    target.mkdir(parents=True, exist_ok=True)
    merge_layers(repo, registry, blueprint_id, target)
    if not args.no_reset:
        reset_directories(target, registry.get("resetDirectories") or [])
    write_workbench_with_repo(
        target,
        repo,
        registry,
        blueprint_id,
        client_display=client_display,
        client_slug=client_slug,
        directory_name=dir_name,
    )
    if args.git:
        r = subprocess.run(["git", "init"], cwd=target)
        if r.returncode != 0:
            sys.exit(r.returncode)
    print(f"Created workspace:\n  {target}\nBlueprint: {blueprint_id}")
    if not args.no_reset:
        reset_list = ", ".join(registry.get("resetDirectories") or [])
        print(f"Reset to empty: {reset_list} (.gitkeep only in each).")
    print(f"Wrote {WORKBENCH_FILENAME} (use for sync without repeating blueprint id).")


def collect_layer_files(repo: Path, registry: dict, blueprint_id: str) -> list[tuple[Path, Path]]:
    pairs: list[tuple[Path, Path]] = []
    shared = repo / registry["sharedRoot"]
    for path in shared.rglob("*"):
        if path.is_file():
            pairs.append((path, path.relative_to(shared)))
    meta = registry["blueprints"].get(blueprint_id)
    if not meta:
        sys.stderr.write(f'Unknown blueprint "{blueprint_id}".\n')
        sys.exit(1)
    for rel in meta.get("overlays") or []:
        root = repo / rel
        for path in root.rglob("*"):
            if path.is_file():
                pairs.append((path, path.relative_to(root)))
    by_rel: dict[str, Path] = {}
    for abs_path, rel in pairs:
        by_rel[rel.as_posix()] = abs_path
    return [(by_rel[k], Path(k)) for k in sorted(by_rel.keys())]


def cmd_sync(args: argparse.Namespace, repo: Path, registry: dict) -> None:
    if args.arg2:
        blueprint_id = args.arg1
        target = Path(args.arg2).resolve()
    else:
        target = Path(args.arg1).resolve()
        blueprint_id = read_workbench_blueprint_id(target)
        if not blueprint_id:
            sys.stderr.write(
                f"No blueprint id in {target / WORKBENCH_FILENAME}.\n"
                "Use: sync <blueprint_id> <path>\n"
            )
            sys.exit(1)
    if not target.is_dir():
        sys.stderr.write(f"Not a directory: {target}\n")
        sys.exit(1)
    if not (target / ".agent-instructions.md").is_file():
        sys.stderr.write(
            f"Warning: {target / '.agent-instructions.md'} missing — sync may be wrong folder.\n"
        )

    if args.dry_run:
        print(f"Would update from blueprint '{blueprint_id}' (last overlay wins per path):\n")
        for _src, rel in collect_layer_files(repo, registry, blueprint_id):
            dest = target / rel
            tag = "exists" if dest.is_file() else "new"
            print(f"  [{tag}] {rel.as_posix()}")
        print("\nDry run only; no files written.")
        return

    merge_layers(repo, registry, blueprint_id, target)
    update_workbench_after_sync(target, repo, registry, blueprint_id)
    print(f"Synced blueprint '{blueprint_id}' into:\n  {target}")
    print("Engagement data under INPUTS, TASK-DEFINITIONS, WORK-IN-PROGRESS, DELIVERABLES was not cleared.")
    print("Matching paths from blueprints were overwritten.")
    print(f"Updated {WORKBENCH_FILENAME} (last_synced_utc).")


def main() -> None:
    script = Path(__file__)
    repo = repo_root(script)
    registry = load_registry(repo)

    parser = argparse.ArgumentParser(
        description="Context Workbench: create workspaces from blueprints or sync updates."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_list = sub.add_parser("list", help="List blueprint ids from registry.json")
    p_list.set_defaults(func=lambda a: cmd_list(repo, registry))

    p_create = sub.add_parser(
        "create",
        help=f'New workspace. Use --name/--path + optional --blueprint (default blueprint: {DEFAULT_BLUEPRINT_ID}), or positional form.',
    )
    p_create.add_argument(
        "--blueprint",
        "-b",
        default=None,
        metavar="ID",
        help=f"Blueprint id when using --name or --path (default: {DEFAULT_BLUEPRINT_ID} if omitted)",
    )
    mx = p_create.add_mutually_exclusive_group(required=False)
    mx.add_argument(
        "--name",
        "-n",
        dest="client_name",
        default=None,
        metavar="CLIENT",
        help="Client / engagement label; folder name is blueprint + slug of this text",
    )
    mx.add_argument(
        "--path",
        default=None,
        dest="workspace_path",
        metavar="PATH",
        help="Explicit workspace directory (relative paths use --parent unless absolute)",
    )
    p_create.add_argument(
        "positional",
        nargs="*",
        metavar="ARG",
        help=f"Alternative to --name/--path: one arg (uses {DEFAULT_BLUEPRINT_ID}) or two (BLUEPRINT then name/path)",
    )
    p_create.add_argument(
        "--parent",
        "-p",
        default=None,
        metavar="DIR",
        help=f"Parent for new workspaces (default: <repo>/{DEFAULT_PROJECTS_DIR})",
    )
    p_create.add_argument("--no-reset", action="store_true", help="Do not empty volatile dirs")
    p_create.add_argument("--git", action="store_true", help="Run git init in the new folder")
    p_create.set_defaults(func=lambda a: cmd_create(a, repo, registry))

    p_sync = sub.add_parser(
        "sync",
        help=f"Refresh workspace from blueprints; 1 arg = path (uses {WORKBENCH_FILENAME}), 2 args = blueprint + path",
    )
    p_sync.add_argument(
        "arg1",
        help=f"Workspace path, or blueprint id if arg2 is set",
    )
    p_sync.add_argument(
        "arg2",
        nargs="?",
        default=None,
        help="Workspace path (when arg1 is blueprint id)",
    )
    p_sync.add_argument("--dry-run", action="store_true", help="List files that would be written")
    p_sync.set_defaults(func=lambda a: cmd_sync(a, repo, registry))

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
