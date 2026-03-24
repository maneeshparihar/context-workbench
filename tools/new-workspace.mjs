#!/usr/bin/env node
/**
 * Spawn a fresh Context Workbench from registry.json blueprints.
 *
 * Usage:
 *   node tools/new-workspace.mjs --list
 *   node tools/new-workspace.mjs <blueprint-id> <target-directory> [--no-reset] [--git]
 *
 * Run from the context-bench repository root (directory that contains registry.json).
 */

import { spawnSync } from "child_process";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..");
const REGISTRY_PATH = path.join(REPO_ROOT, "registry.json");

function loadRegistry() {
  const raw = fs.readFileSync(REGISTRY_PATH, "utf8");
  return JSON.parse(raw);
}

function usage(msg) {
  if (msg) console.error(msg + "\n");
  console.error(`Usage:
  node tools/new-workspace.mjs --list
  node tools/new-workspace.mjs <blueprint-id> <target-directory> [--no-reset] [--git]

Options:
  --no-reset   Copy blueprint as-is (do not empty INPUTS, TASK-DEFINITIONS, WIP, DELIVERABLES).
  --git        Run "git init" in the target directory after copy.
`);
  process.exit(msg ? 1 : 0);
}

function copyTree(src, dest) {
  fs.cpSync(src, dest, { recursive: true, errorOnExist: false, force: true });
}

function resetDirectory(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
  for (const name of fs.readdirSync(dirPath)) {
    fs.rmSync(path.join(dirPath, name), { recursive: true, force: true });
  }
  fs.writeFileSync(path.join(dirPath, ".gitkeep"), "");
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv[0] === "-h" || argv[0] === "--help") usage();

  const registry = loadRegistry();
  const sharedRoot = path.join(REPO_ROOT, registry.sharedRoot);

  if (!fs.existsSync(sharedRoot)) {
    console.error(`Missing shared root: ${registry.sharedRoot}`);
    process.exit(1);
  }

  if (argv[0] === "--list") {
    console.log("Blueprints (id — label)\n");
    for (const [id, meta] of Object.entries(registry.blueprints)) {
      const desc = meta.description ? ` — ${meta.description}` : "";
      console.log(`  ${id}\n    ${meta.label}${desc}\n`);
    }
    process.exit(0);
  }

  const blueprintId = argv[0];
  const targetArg = argv[1];
  if (!targetArg) usage("Error: missing target directory.");

  const noReset = argv.includes("--no-reset");
  const initGit = argv.includes("--git");

  const blueprint = registry.blueprints[blueprintId];
  if (!blueprint) {
    console.error(`Unknown blueprint "${blueprintId}". Use --list.`);
    process.exit(1);
  }

  const target = path.resolve(process.cwd(), targetArg);
  if (fs.existsSync(target) && fs.readdirSync(target).length > 0) {
    console.error(
      `Refusing to write into non-empty directory:\n  ${target}\n` +
        "Choose an empty path or remove contents first."
    );
    process.exit(1);
  }

  fs.mkdirSync(target, { recursive: true });
  copyTree(sharedRoot, target);

  const overlays = blueprint.overlays || [];
  for (const rel of overlays) {
    const abs = path.join(REPO_ROOT, rel);
    if (!fs.existsSync(abs)) {
      console.error(`Overlay path missing: ${rel}`);
      process.exit(1);
    }
    copyTree(abs, target);
  }

  if (!noReset) {
    for (const dir of registry.resetDirectories) {
      resetDirectory(path.join(target, dir));
    }
  }

  if (initGit) {
    const r = spawnSync("git", ["init"], {
      cwd: target,
      stdio: "inherit",
      shell: process.platform === "win32",
    });
    if (r.error && r.error.code === "ENOENT") {
      console.error("git not found on PATH; skip or install Git.");
      process.exit(1);
    }
    if (r.status !== 0 && r.status !== null) process.exit(r.status);
  }

  console.log(`Created workspace:\n  ${target}\nBlueprint: ${blueprintId} (${blueprint.label})`);
  if (!noReset) {
    console.log(
      `Reset to empty: ${registry.resetDirectories.join(", ")} (each contains .gitkeep only).`
    );
  }
}

main();
