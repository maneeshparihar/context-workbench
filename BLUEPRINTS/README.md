# Blueprints

Blueprints are **reusable workspace recipes** for Context Workbench. Each blueprint is:

1. **`BLUEPRINTS/_shared`** — canonical layout: `.agent-instructions.md`, `.gitignore`, `README.md`, `REFERENCES/`, `HELPERS/`, and placeholder dirs for engagement data. **No** system prompts here; the **`default`** overlay supplies `generic-workbench-prompt.md`, and other blueprints supply their own prompts only.
2. **Zero or more overlays** — folders merged on top of `_shared` (typically extra files under `SYSTEM-PROMPTS/` or `REFERENCES/`).

Implementations with the **same** commands: **`tools/new_workspace.py`** (Python), **`tools/new-workspace.ps1`** (PowerShell, no extra deps), **`tools/new-workspace.sh`** (Bash + **jq**). Change behavior in **Python** first, then port to the shells if you want them to stay in lockstep.

**`tools/new-workspace.mjs`** (Node) is optional—**create** only, for environments without Python.

### `_shared` and **`default`**

Every workspace starts from **`BLUEPRINTS/_shared`**. The **`default`** blueprint adds **`BLUEPRINTS/default/`**, including **`SYSTEM-PROMPTS/generic-workbench-prompt.md`** (the only blueprint that uses that file). If you run **`create` with one argument**, the tool uses blueprint **`default`** automatically.

**`_shared/metadata.json`** is a small stub; the effective blueprint’s **`metadata.json`** overwrites it in the new workspace root.

Other blueprints (e.g. **`presales`**) are **`_shared` + their overlay**—same idea, different prompts.

---

## Where configuration lives

| File | Location | Role |
| :--- | :--- | :--- |
| **`registry.json`** | **Repository root** (same level as `BLUEPRINTS/`, not inside `tools/`) | Lists blueprint ids, overlay paths, and `resetDirectories`. Shared by scripts and humans. |
| **`metadata.json`** | **`BLUEPRINTS/_shared/metadata.json`** (stub), then each overlay (e.g. `BLUEPRINTS/presales/metadata.json`) | Stub first; the overlay’s **`metadata.json`** overwrites it in the **workspace root** so the folder documents the effective blueprint. |
| **`WORKBENCH.json`** | Root of each **spawned** engagement folder | Records which blueprint and version created the folder, client slug, timestamps; **`sync`** can read `blueprint.id` from here so you only pass the path. |

---

### Create (fresh client folder)

From the repo root:

```bash
python tools/new_workspace.py create "Acme Corporation"
```

One argument → blueprint **`default`** → **`PROJECTS/default_acmecorpor/`** (same slug rules: lowercase alnum, max 10).

Named blueprint (two positional arguments):

```bash
python tools/new_workspace.py create presales "Acme Corporation"
# → PROJECTS/presales_acmecorpor/
```

Explicit flags (recommended for scripts; **omit `--blueprint` to use `default`**):

```bash
python tools/new_workspace.py create --name "Acme Corporation"
python tools/new_workspace.py create --blueprint=presales --name=olive-grove
python tools/new_workspace.py create -b presales -n "Olive Grove" --parent ./engagements
```

Do not combine `--name` / `--path` / `--blueprint` with the old positional form in one command.

By default, the parent directory is **`PROJECTS/`** under the **context-bench** repo (created if missing). Override with **`--parent`**.

Custom folder name (path as the **only** argument uses **`default`** blueprint):

```bash
python tools/new_workspace.py create ./custom-name    # → PROJECTS/custom-name/
python tools/new_workspace.py create presales ./custom-name
```

That copies `_shared`, applies overlays in order (later paths **override** earlier ones), writes **`WORKBENCH.json`**, then **empties** `resetDirectories` from `registry.json` (default: `INPUTS`, `TASK-DEFINITIONS`, `WORK-IN-PROGRESS`, `DELIVERABLES`) to `.gitkeep` only.

---

### Sync (pull latest blueprint into an existing workspace)

```bash
python tools/new_workspace.py sync ./engagements/presales_acmecorpor --dry-run
python tools/new_workspace.py sync ./engagements/presales_acmecorpor
```

If **`WORKBENCH.json`** is present, the blueprint id is taken from it. Override the two-argument form when needed:

```bash
python tools/new_workspace.py sync presales ./some/path
```

**Sync** re-merges `_shared` + overlays: matching paths are **overwritten**; files that exist only in the engagement folder are **left alone**; volatile dirs are **not** cleared. **`WORKBENCH.json`** is updated with `last_synced_utc` and `last_sync_blueprint`. Use **`--dry-run`** to preview.

---

## Add a new blueprint

1. Create `BLUEPRINTS/<your-id>/` and mirror paths you want to override or extend (e.g. `SYSTEM-PROMPTS/my-role.md`, `REFERENCES/company-standards.md`).
2. Add **`metadata.json`** in that folder (`schema_version`, `blueprint_id`, `version`, `label`, `role`, optional `defaults.system_prompts`).
3. Add an entry to **`registry.json`** at the **repo root** with an `overlays` array pointing at your folder (can be empty if you only want `_shared`, rarely needed).

```json
"your-id": {
  "label": "Human-readable name",
  "description": "Optional.",
  "overlays": ["BLUEPRINTS/your-id"]
}
```

4. Run `python tools/new_workspace.py list` or `node tools/new-workspace.mjs --list` to confirm it appears.

---

## Shared maintenance

When you change workflow rules, edit **`BLUEPRINTS/_shared/.agent-instructions.md`** once. Optionally sync the same file to the repository root if you keep a working copy there for dogfooding.

---

## Optional “more” (future-friendly)

- **Version pins:** bump `"version"` in each blueprint’s **`metadata.json`** when prompts change materially; **`WORKBENCH.json`** stores what was applied at create/sync time.
- **Remote packs:** extend the script to `git clone --depth 1` a blueprint URL into a temp dir, then copy (private registry).
- **Post-install hooks:** after reset, copy `INPUTS/input-map.template.md` → `INPUTS/input-map.md` for teams that always want a map file.
