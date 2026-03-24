# Context Workbench

**Filesystem-native workspace for LLM-assisted work**—context, tasks, and outputs live in plain Markdown and folders you own, not only in a scrolling chat window. You can **inspect work in progress**, **read task definitions**, and **verify** that prompts, references, and deliverables stay aligned.

This is a **structured collaboration pattern** (a workbench layout plus agent rules), not a runtime or autonomous agent framework. It pairs well with editors and assistants that can follow repository instructions (for example Cursor’s agent mode and similar tools).

---

## Why use it

| Goal | How the workbench helps |
| :--- | :--- |
| **Explainability** | Tasks, references, and WIP are visible files—not buried in chat history. |
| **Control** | You define what “done” looks like in `TASK-DEFINITIONS/` and `DELIVERABLES/`. |
| **Grounding** | `REFERENCES/` and `INPUTS/` give the model stable sources to check against. |
| **Traceability** | Each active task can have a dedicated tracking file under `WORK-IN-PROGRESS/`. |

---

## Repository layout

| Folder | Purpose |
| :--- | :--- |
| **`SYSTEM-PROMPTS/`** | Personas and domain instructions (role, tone, strategy). |
| **`REFERENCES/`** | Truth documents: standards, checklists, constraints. Work should be validated against these. |
| **`INPUTS/`** | Source material: emails, notes, exports, prior context. |
| **`TASK-DEFINITIONS/`** | Focused tasks for the assistant to execute (Markdown). |
| **`WORK-IN-PROGRESS/`** | Sandbox: progress logs, blockers, and **user notes** per task. |
| **`DELIVERABLES/`** | Final, polished outputs only—not drafts or open plans. |
| **`HELPERS/`** | Small scripts or utilities (e.g. decoding inputs, preprocessing). |

The behavioral contract for the assistant is defined in **`.agent-instructions.md`** at the workspace root. Keep that file in any copy of this layout so tools pick up the same rules.

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

1. **Open** this folder as the project root in your editor so `.agent-instructions.md` is honored.
2. **Add** tasks under `TASK-DEFINITIONS/` and source material under `INPUTS/` and `REFERENCES/`.
3. **Tell** your assistant to follow `.agent-instructions.md` and the active system prompt under `SYSTEM-PROMPTS/`.
4. **Review** `WORK-IN-PROGRESS/` as the source of truth for what changed and what is blocked.

---

## Customization

- **Rename folders** only if you also update `.agent-instructions.md` and any tooling that depends on paths.
- **Add** domain-specific prompts under `SYSTEM-PROMPTS/` and keep one “active” prompt obvious (filename or short note in the task file).
- **Prefer** Markdown tables for tracking inside WIP and task files where the instructions call for them.

---

## License

Add a `LICENSE` file when you publish this workspace; none is bundled here by default.
