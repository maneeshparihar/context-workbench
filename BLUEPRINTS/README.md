# Blueprints

Blueprints are **reusable workspace recipes** for Context Workbench. Each blueprint is:

1. **`BLUEPRINTS/_shared`** — canonical layout: `.agent-instructions.md`, `.gitignore`, `README.md`, `REFERENCES/`, `HELPERS/`, and placeholder dirs for engagement data. **No** system prompts here; the **`default`** overlay supplies `generic-workbench-prompt.md`, and other blueprints supply their own prompts only.
2. **Zero or more overlays** — folders merged on top of `_shared` (typically extra files under `SYSTEM-PROMPTS/` or `REFERENCES/`).

**CLI:** **`tools/workspace.py`** (Python — extend here first), **`tools/workspace.ps1`**, **`tools/workspace.sh`** (same subcommands; Bash needs **jq**). **`tools/workspace.mjs`** is optional and **create-only** (Node).

### `_shared` and **`default`**

Every workspace starts from **`BLUEPRINTS/_shared`**. The **`default`** blueprint adds **`BLUEPRINTS/default/`**, including **`SYSTEM-PROMPTS/generic-workbench-prompt.md`**. A one-argument **`create`** uses blueprint **`default`** automatically.

**`_shared/metadata.json`** is a small stub; the effective blueprint’s **`metadata.json`** overwrites it in the new workspace root.

Other blueprints (see **`registry.json`**) are **`_shared` + their overlay**—same idea, different prompts.

---

## Where configuration lives

| File | Location | Role |
| :--- | :--- | :--- |
| **`registry.json`** | **Repository root** (same level as `BLUEPRINTS/`, not inside `tools/`) | Lists blueprint ids, overlay paths, and `resetDirectories`. |
| **`metadata.json`** | **`BLUEPRINTS/_shared/metadata.json`** (stub), then each overlay | Stub first; the overlay’s **`metadata.json`** overwrites it in the **workspace root**. |
| **`WORKBENCH.json`** | Root of each **spawned** engagement folder | Records blueprint id/version, client slug, timestamps; **`sync`** can read `blueprint.id` from here. |

---

## Create, sync, and list (reference)

From the repo root, the same patterns as the main **`README.md`**:

```bash
python tools/workspace.py create "Acme Corporation"
python tools/workspace.py create --blueprint=technical-architect --name "Acme Corporation"  # run `python tools/workspace.py list` for all ids
python tools/workspace.py sync ./WORKSPACES/technical-architect_acmecorpor
python tools/workspace.py list
```

Override the parent directory with **`--parent`** on **`create`**. Use **`sync … --dry-run`** to preview. With flags, use **`--name`** (or **`--path`**) and optional **`--blueprint`**; do not mix that with positional **`create`** in one command.

**Create** merges **`_shared`** and overlays, writes **`WORKBENCH.json`**, then empties **`resetDirectories`** from **`registry.json`** (default: `INPUTS`, `TASK-DEFINITIONS`, `WORK-IN-PROGRESS`, `DELIVERABLES`) to `.gitkeep` only. **Sync** re-merges blueprint files; it does **not** wipe engagement data.

Shell and Node tools follow the same create rules where implemented; **`workspace.mjs`** does not implement **`sync`**.

---

## Add a new blueprint

1. Create `BLUEPRINTS/<your-id>/` and add files to override or extend (e.g. `SYSTEM-PROMPTS/my-role.md`).
2. Add **`metadata.json`** (`schema_version`, `blueprint_id`, `version`, `label`, `role`, optional `defaults.system_prompts`).
3. Add an entry to **`registry.json`** with an `overlays` array pointing at your folder.

```json
"your-id": {
  "label": "Human-readable name",
  "description": "Optional.",
  "overlays": ["BLUEPRINTS/your-id"]
}
```

4. Run `python tools/workspace.py list` or `node tools/workspace.mjs --list` to confirm it appears.

---

## Shared maintenance

When you change workflow rules, edit **`BLUEPRINTS/_shared/.agent-instructions.md`** once. Optionally sync the same file to the repository root if you keep a working copy there for dogfooding.

---

## Optional “more” (future-friendly)

- **Version pins:** bump `"version"` in each blueprint’s **`metadata.json`** when prompts change materially; **`WORKBENCH.json`** stores what was applied at create/sync time.
- **Remote packs:** extend the script to `git clone --depth 1` a blueprint URL into a temp dir, then copy (private registry).
- **Post-install hooks:** after reset, copy `INPUTS/input-map.template.md` → `INPUTS/input-map.md` for teams that always want a map file.
