# Context Workbench

**Filesystem-native workspace for LLM-assisted work**—context, tasks, and outputs live in plain Markdown and folders you own, not only in a scrolling chat window. You can **inspect work in progress**, **read task definitions**, and **verify** that prompts, references, and deliverables stay aligned.

This is a **structured collaboration pattern** (a workbench layout plus agent rules), not a runtime or autonomous agent framework. It pairs well with editors and assistants that can follow repository instructions (for example Cursor’s agent mode and similar tools).

**Tooling:** You can run the same **`list` / `create` / `sync`** flow three ways: **`tools/new_workspace.py`** (Python 3 — easiest to extend), **`tools/new-workspace.ps1`** (native PowerShell 5.1+), or **`tools/new-workspace.sh`** (native Bash; needs **`jq`** on `PATH`). **`tools/new-workspace.mjs`** is optional, create-only, if you avoid both Python and shell logic.

---

## Why use it

| Goal | How the workbench helps |
| :--- | :--- |
| **Explainability** | Tasks, references, and WIP are visible files—not buried in chat history. |
| **Control** | You define what “done” looks like in `TASK-DEFINITIONS/` and `DELIVERABLES/`. |
| **Grounding** | `REFERENCES/` and `INPUTS/` give the model stable sources to check against. |
| **Traceability** | Each active task can have a dedicated tracking file under `WORK-IN-PROGRESS/`. |

---

## Layout

### This repository (the kit)

| Path | Purpose |
| :--- | :--- |
| **`PROJECTS/`** | Default parent for **engagement workspaces** from `python tools/new_workspace.py create …`—one subfolder per client or initiative (full workbench copy). Use **`--parent`** to put new workspaces somewhere else. |
| **`BLUEPRINTS/`** | **`_shared`** (common base) plus overlays. The **`default`** blueprint is `_shared` + a generic prompt; use **`create "Client"`** with no blueprint name to get it. Other overlays: **`presales`**, **`technical-architect`**, etc. Root **`metadata.json`** in a workspace comes from the chosen blueprint (overwriting the `_shared` stub). |
| **`tools/`** | `new_workspace.py` (primary CLI), `new-workspace.sh`, `new-workspace.ps1` (wrappers), optional `new-workspace.mjs`. |

### Each engagement workspace (usually under `PROJECTS/<name>/`)

| Folder | Purpose |
| :--- | :--- |
| **`SYSTEM-PROMPTS/`** | Personas and domain instructions (role, tone, strategy). |
| **`REFERENCES/`** | Truth documents: standards, checklists, constraints. Work should be validated against these. |
| **`INPUTS/`** | Source material: emails, notes, exports, prior context. |
| **`TASK-DEFINITIONS/`** | Focused tasks for the assistant to execute (Markdown). |
| **`WORK-IN-PROGRESS/`** | Sandbox: progress logs, blockers, and **user notes** per task. |
| **`DELIVERABLES/`** | Final, polished outputs only—not drafts or open plans. |
| **`HELPERS/`** | Small scripts or utilities (e.g. decoding inputs, preprocessing). |

The behavioral contract for the assistant is defined in **`.agent-instructions.md`** at the **workspace** root. **`WORKBENCH.json`** records which blueprint created that workspace (for `sync`).

---

## Workflow (summary)

1. **Define tasks** in `TASK-DEFINITIONS/` as small, explicit Markdown specs.
2. **Provide context** in `INPUTS/` and optional **`INPUTS/input-map.md`** (or the inline table inside `.agent-instructions.md`) so large folders are not read blindly.
3. **Set the persona** by pointing the session at the right file under `SYSTEM-PROMPTS/`.
4. **Run work** with your assistant; for each task, expect updates under `WORK-IN-PROGRESS/` (progress, problems, user notes).
5. **Check references** before treating output as complete; align tone and content with `REFERENCES/` and the active system prompt.
6. **Ship** finished work to `DELIVERABLES/` as consolidated status or final artifacts—not as WIP.

Details and edge cases (input-map priority, token-sensitive scanning, final report rules) are specified in `.agent-instructions.md`.

---

## Quick start

### From this repo (blueprints)

From the **repository root** (where `registry.json` lives):

```bash
# Pick one implementation (same arguments):
python tools/new_workspace.py list
./tools/new-workspace.sh list                    # Bash + jq; chmod +x on Unix
./tools/new-workspace.ps1 list                   # Windows PowerShell (native JSON; no jq)

./tools/new-workspace.ps1 create "Acme Corporation"
./tools/new-workspace.sh create "Acme Corporation"

python tools/new_workspace.py create "Acme Corporation"
# → PROJECTS/default_acmecorpor/  (default blueprint: _shared + BLUEPRINTS/default)

python tools/new_workspace.py create --name "Acme Corporation"
python tools/new_workspace.py create --blueprint=presales --name=olive-grove
# Omit --blueprint → uses blueprint "default". Do not mix flags with positional args.

python tools/new_workspace.py create presales "Acme Corporation"
# → PROJECTS/presales_acmecorpor/

python tools/new_workspace.py sync ./PROJECTS/default_acmecorpor --dry-run
python tools/new_workspace.py create presales "Other" --parent ./engagements   # override parent
python tools/new_workspace.py sync presales ./some/custom/path   # optional: blueprint + path

# Optional: create only, no Python — node tools/new-workspace.mjs --list
```

**Create** copies **`BLUEPRINTS/_shared`**, merges the blueprint overlay (for example `BLUEPRINTS/presales`), writes **`WORKBENCH.json`** (blueprint id/version, client slug), then **clears** `INPUTS/`, `TASK-DEFINITIONS/`, `WORK-IN-PROGRESS/`, and `DELIVERABLES/` so each engagement starts clean. **`sync`** with one argument reads the blueprint id from **`WORKBENCH.json`**; it reapplies layers so prompts and `.agent-instructions.md` stay up to date without deleting engagement data.

Use **`--no-reset`** on `create` to keep seeded files in volatile folders; **`--git`** runs `git init` in the new folder. The Node script supports the same create flow with **`--no-reset`** and **`--git`** if you use it.

**`registry.json`** lives at the **repository root** (next to `BLUEPRINTS/`), not under `tools/` — it is the catalog for the whole workbench kit. See **`BLUEPRINTS/README.md`** for blueprints, **`metadata.json`**, and **`WORKBENCH.json`**.

### From a folder you already have

1. **Open** the folder in your editor so `.agent-instructions.md` is at the root of that workspace.
2. **Add** at least one task under `TASK-DEFINITIONS/` and any needed files under `INPUTS/` and `REFERENCES/`.
3. **Tell** your assistant to follow `.agent-instructions.md` and the active system prompt.
4. **Review** `WORK-IN-PROGRESS/` as the source of truth for what changed and what is blocked.

---

## Customization

- **Rename folders** only if you also update `.agent-instructions.md` and any tooling that depends on paths.
- **Add** domain-specific prompts under `SYSTEM-PROMPTS/` and keep one “active” prompt obvious (filename or short note in the task file).
- **Prefer** Markdown tables for tracking inside WIP and task files where the instructions call for them.

---

## Reusable workspace packs

Multiple **blueprints** live under `BLUEPRINTS/` and are registered in `registry.json`. Each engagement should be a **new directory** produced by **`python tools/new_workspace.py create …`** (or a zip of that output) so prompts and protocol stay centralized while **inputs, tasks, WIP, and deliverables** stay local and disposable.

---

## License

Add a `LICENSE` file when you publish this repository; none is bundled here by default.
