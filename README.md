# Context Workbench

**Filesystem-native workspace for LLM-assisted work**—context, tasks, and outputs live in plain Markdown and folders you own. This kit gives you a **repeatable folder layout** (blueprints) and a small CLI to **create**, **sync**, and **list** engagement folders. It is a **structured collaboration pattern**, not a runtime or autonomous agent framework. It pairs well with editors and assistants that follow repository instructions (for example Cursor’s agent mode).

## Quick start

From the **repository root** (where **`registry.json`** lives):

The first **`create`** line below makes a **default, generic** workbench (good for most people). To use a different built-in style, copy the second **`create`** line and change **`technical-architect`** to another name from the comment at the end of that line.

```bash
python tools/workspace.py create "Acme Corporation"
python tools/workspace.py create --blueprint=technical-architect --name "Acme Corporation"  # other blueprints: default | presales | technical-architect
python tools/workspace.py sync ./WORKSPACES/default_acmecorpor
python tools/workspace.py list
```

Use the folder path **`create`** printed for **`sync`** if yours looks different. Open the new folder in your editor and follow **`.agent-instructions.md`**. **`list`** shows every blueprint name; **`create --help`** shows the full option list.

**Without Python:** use **Bash** or **PowerShell** in the next section. **Create-only with Node:** `node tools/workspace.mjs --list` and `node tools/workspace.mjs <blueprint-id> <target-dir>`.

## Shell and PowerShell

Same **create → sync → list** order. The shell tools use **positional** `create` (one argument = generic default; two arguments = blueprint id, then client name). For **`--blueprint` / `--name`** flags, use **`workspace.py`** (see quick start above).

### Bash (`tools/workspace.sh`) — Linux, macOS, Git Bash (Windows)

From the **repository root**:

```bash
chmod +x tools/workspace.sh    # Linux / Mac, first time only
./tools/workspace.sh create "Acme Corporation"
./tools/workspace.sh create presales "Acme Corporation"  # other blueprints: default | presales | technical-architect
./tools/workspace.sh sync ./WORKSPACES/default_acmecorpor
./tools/workspace.sh list
```

**Git Bash on Windows:** `cd` to the repo (paths look like `cd /c/Users/you/.../context-bench`). Then run `./tools/workspace.sh` the same way.

**jq:** Required for this script. On **macOS** and **Linux**, if `jq` is missing, the script **tries to install it** (Homebrew on Mac; `apt`, `dnf`, `yum`, `zypper`, `pacman`, or `apk` on Linux). You may be asked for your password (`sudo`). **Git Bash on Windows** does not auto-install `jq`; install it and add it to `PATH`, or use **PowerShell** below.

Optional: **`create --parent /path/to/folder`** (or **`-p`**) **`--no-reset`**, **`--git`**. **`sync --dry-run`** before a real sync.

### PowerShell (`tools/workspace.ps1`) — Windows

From the **repository root**:

```powershell
.\tools\workspace.ps1 create "Acme Corporation"
.\tools\workspace.ps1 create presales "Acme Corporation"  # other blueprints: default | presales | technical-architect
.\tools\workspace.ps1 sync .\WORKSPACES\default_acmecorpor
.\tools\workspace.ps1 list
```

Optional: **`create --parent`** path (or **`-p`**), **`--no-reset`**, **`--git`**. **`sync --dry-run`**.

---

## Why use it

| Goal               | How the workbench helps                                                        |
| :----------------- | :----------------------------------------------------------------------------- |
| **Explainability** | Tasks, references, and WIP are visible files—not buried in chat history.       |
| **Control**        | You define what “done” looks like in `TASK-DEFINITIONS/` and `DELIVERABLES/`.  |
| **Grounding**      | `REFERENCES/` and `INPUTS/` give the model stable sources to check against.    |
| **Traceability**   | Each active task can have a dedicated tracking file under `WORK-IN-PROGRESS/`. |

---

## Layout

### This repository (the kit)

| Path              | Purpose                                                                                                                                                                                                                        |
| :---------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`WORKSPACES/`** | Default parent for folders **`create`** makes. Use **`--parent`** to put them elsewhere.                                                                                                                                       |
| **`BLUEPRINTS/`** | Built-in workspace styles. Names are listed in **`registry.json`**. A single-name **`create`** uses the generic **default**; other styles need **`--blueprint`** (and usually **`--name`**) or the two-word **`create`** form. |
| **`tools/`**      | **`workspace.py`** (full CLI), **`workspace.ps1`**, **`workspace.sh`**, optional **`workspace.mjs`** (create only).                                                                                                            |

### Each engagement workspace (usually under `WORKSPACES/<name>/`)

| Folder                  | Purpose                                                           |
| :---------------------- | :---------------------------------------------------------------- |
| **`SYSTEM-PROMPTS/`**   | Personas and domain instructions (role, tone, strategy).          |
| **`REFERENCES/`**       | Truth documents: standards, checklists, constraints.              |
| **`INPUTS/`**           | Source material: emails, notes, exports, prior context.           |
| **`TASK-DEFINITIONS/`** | Focused tasks for the assistant to execute (Markdown).            |
| **`WORK-IN-PROGRESS/`** | Sandbox: progress logs, blockers, and user notes per task.        |
| **`DELIVERABLES/`**     | Final, polished outputs only—not drafts or open plans.            |
| **`HELPERS/`**          | Small scripts or utilities (e.g. decoding inputs, preprocessing). |

The behavioral contract for the assistant is **`.agent-instructions.md`** at the **workspace** root. **`WORKBENCH.json`** records which blueprint created that folder (for **`sync`**).

---

## Workflow (summary)

1. **Define tasks** in `TASK-DEFINITIONS/` as small, explicit Markdown specs.
2. **Provide context** in `INPUTS/` and optional **`INPUTS/input-map.md`** (or the table in `.agent-instructions.md`) so large folders are not read blindly.
3. **Set the persona** by pointing the session at the right file under `SYSTEM-PROMPTS/`.
4. **Run work** with your assistant; expect updates under `WORK-IN-PROGRESS/` per task.
5. **Check references** before treating output as complete.
6. **Ship** finished work to `DELIVERABLES/`.

Details are in `.agent-instructions.md`.

---

## More options

- **Other ways to create:** you can add **`--name`** and **`--blueprint`** (blueprint names match **`registry.json`**). Skip **`--blueprint`** for the same generic default as `create "Client name"`. Do not mix **`--name`** or **`--path`** with the two-word positional style in the same command.
- **`sync`:** `python tools/workspace.py sync <path> --dry-run` to preview. Two-argument legacy form: `sync <blueprint-id> <path>`.
- **`registry.json`** lives at the **repository root** next to **`BLUEPRINTS/`**. Blueprint authoring and **`WORKBENCH.json`** fields: **`BLUEPRINTS/README.md`**.

---

## From a folder you already have

1. **Open** the folder in your editor so `.agent-instructions.md` is at the root of that workspace.
2. **Add** at least one task under `TASK-DEFINITIONS/` and any needed files under `INPUTS/` and `REFERENCES/`.
3. **Tell** your assistant to follow `.agent-instructions.md` and the active system prompt.
4. **Review** `WORK-IN-PROGRESS/` as the source of truth for what changed and what is blocked.

---

## Customization

- **Rename folders** only if you also update `.agent-instructions.md` and any tooling that depends on paths.
- **Add** domain-specific prompts under `SYSTEM-PROMPTS/` and keep one “active” prompt obvious.
- **Prefer** Markdown tables for tracking inside WIP and task files where the instructions call for them.

---

## Reusable workspace packs

Each engagement should be a **directory produced by `create`** (or a zip of that output) so prompts and protocol stay centralized while **inputs, tasks, WIP, and deliverables** stay local.

---

## License

Add a `LICENSE` file when you publish this repository; none is bundled here by default.
