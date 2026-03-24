#!/usr/bin/env bash
#
# Context Workbench — native shell implementation (no Python).
# Requires: bash 4+, jq, standard Unix tools (find, cp, date).
#
# Usage:
#   ./tools/new-workspace.sh list
#   ./tools/new-workspace.sh create "Acme Corporation"
#   ./tools/new-workspace.sh create presales "Acme Corporation"
#   ./tools/new-workspace.sh create --parent /tmp/foo "Acme"
#   ./tools/new-workspace.sh sync ./PROJECTS/default_acme
#   ./tools/new-workspace.sh sync presales ./path/to/ws
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="$REPO/registry.json"
WORKBENCH_NAME="WORKBENCH.json"
MAX_SLUG_LEN=10
DEFAULT_PROJECTS="PROJECTS"
DEFAULT_BP="default"

die() { echo "context-bench: $*" >&2; exit 1; }

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required (install: brew install jq / apt install jq)"
}

to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Alnum-only slug, max length (matches new_workspace.py)
normalize_slug() {
  local s
  s=$(to_lower "$1")
  s=$(printf '%s' "$s" | tr -cd 'a-z0-9')
  [[ -z "$s" ]] && s="client"
  printf '%s' "$s" | awk -v n="$MAX_SLUG_LEN" '{print substr($0,1,n)}'
}

bp_prefix() {
  to_lower "$1" | tr '-' '_'
}

default_folder_name() {
  local bid="$1" raw="$2"
  printf '%s_%s' "$(bp_prefix "$bid")" "$(normalize_slug "$raw")"
}

is_explicit_path() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  [[ -z "$s" || "$s" == "." || "$s" == ".." ]] && return 0
  [[ "$s" == *"/"* || "$s" == *"\\"* ]] && return 0
  [[ "$s" == /* ]] && return 0
  [[ ${#s} -gt 1 && "${s:1:1}" == ":" && "${s:0:1}" =~ [[:alpha:]] ]] && return 0
  return 1
}

load_registry() {
  [[ -f "$REGISTRY" ]] || die "missing $REGISTRY"
  need_jq
}

copy_tree_merge() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || die "missing directory: $src"
  find "$src" -type f -print0 | while IFS= read -r -d '' f; do
    local rel="${f#"$src"/}"
    mkdir -p "$dst/$(dirname "$rel")"
    cp -p "$f" "$dst/$rel"
  done
}

merge_layers() {
  local bid="$1" target="$2"
  jq -e --arg b "$bid" '.blueprints | has($b)' "$REGISTRY" >/dev/null || die "unknown blueprint \"$bid\". Use: list"
  local shared_rel
  shared_rel=$(jq -r '.sharedRoot' "$REGISTRY")
  local shared="$REPO/$shared_rel"
  copy_tree_merge "$shared" "$target"
  local ov
  while IFS= read -r ov; do
    [[ -z "$ov" ]] && continue
    copy_tree_merge "$REPO/$ov" "$target"
  done < <(jq -r --arg b "$bid" '.blueprints[$b].overlays[]? // empty' "$REGISTRY")
}

reset_directories() {
  local target="$1"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local d="$target/$name"
    mkdir -p "$d"
    find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    : >"$d/.gitkeep"
  done < <(jq -r '.resetDirectories[]?' "$REGISTRY")
}

meta_dir_for_blueprint() {
  local bid="$1"
  local first
  first=$(jq -r --arg b "$bid" '.blueprints[$b].overlays[0]? // empty' "$REGISTRY")
  if [[ -n "$first" ]]; then
    printf '%s' "$REPO/$first"
  else
    printf '%s' "$REPO/$(jq -r '.sharedRoot' "$REGISTRY")"
  fi
}

write_workbench() {
  local target="$1" bid="$2" client_display="$3" client_slug="$4" dir_name="$5"
  local mdir meta
  mdir=$(meta_dir_for_blueprint "$bid")
  meta="$mdir/metadata.json"
  local bpver bplabel bprole reglabel regver
  bpver="0"
  bplabel=""
  bprole="null"
  if [[ -f "$meta" ]]; then
    bpver=$(jq -r '.version // "0"' "$meta")
    bplabel=$(jq -r '.label // ""' "$meta")
    bprole=$(jq -c '.role // null' "$meta")
  fi
  reglabel=$(jq -r --arg b "$bid" '.blueprints[$b].label // ""' "$REGISTRY")
  [[ -z "$bplabel" ]] && bplabel="$reglabel"
  regver=$(jq -c '.version // 1' "$REGISTRY" | tr -d '\n')
  local created
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ -n "${client_display:-}" ]]; then
    jq -n \
      --arg id "$bid" \
      --arg ver "$bpver" \
      --arg label "$bplabel" \
      --argjson role "$bprole" \
      --arg cd "$client_display" \
      --arg cs "$client_slug" \
      --arg dn "$dir_name" \
      --argjson rv "$regver" \
      --arg ts "$created" \
      '{
        schema_version: 1,
        blueprint: { id: $id, version: $ver, label: $label, role: $role },
        engagement: { client_display_name: $cd, client_slug: $cs },
        paths: { directory_name: $dn },
        registry: { version: $rv },
        created_utc: $ts,
        generator: { tool: "tools/new-workspace.sh", kind: "create" }
      }' >"$target/$WORKBENCH_NAME"
  else
    jq -n \
      --arg id "$bid" \
      --arg ver "$bpver" \
      --arg label "$bplabel" \
      --argjson role "$bprole" \
      --arg dn "$dir_name" \
      --argjson rv "$regver" \
      --arg ts "$created" \
      '{
        schema_version: 1,
        blueprint: { id: $id, version: $ver, label: $label, role: $role },
        engagement: { client_display_name: null, client_slug: null },
        paths: { directory_name: $dn },
        registry: { version: $rv },
        created_utc: $ts,
        generator: { tool: "tools/new-workspace.sh", kind: "create" }
      }' >"$target/$WORKBENCH_NAME"
  fi
}

read_workbench_bp() {
  local target="$1"
  local f="$target/$WORKBENCH_NAME"
  local id
  [[ -f "$f" ]] || return 1
  id=$(jq -r '.blueprint.id // empty' "$f" 2>/dev/null)
  [[ -n "$id" ]] || return 1
  printf '%s' "$id"
}

update_workbench_sync() {
  local target="$1" bid="$2"
  local f="$target/$WORKBENCH_NAME"
  local mdir meta bpver
  mdir=$(meta_dir_for_blueprint "$bid")
  meta="$mdir/metadata.json"
  bpver="0"
  [[ -f "$meta" ]] && bpver=$(jq -r '.version // "0"' "$meta")
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [[ -f "$f" ]]; then
    jq --arg ts "$ts" --arg id "$bid" --arg ver "$bpver" \
      '.last_synced_utc = $ts | .last_sync_blueprint = {id: $id, version: $ver}' "$f" >"${f}.tmp" && mv "${f}.tmp" "$f"
  else
    jq -n \
      --arg ts "$ts" --arg id "$bid" --arg ver "$bpver" \
      '{schema_version: 1, last_synced_utc: $ts, last_sync_blueprint: {id: $id, version: $ver}}' >"$f"
  fi
}

cmd_list() {
  load_registry
  echo "Blueprints (id - label)"
  echo ""
  jq -r '.blueprints | keys[]' "$REGISTRY" | while read -r bid; do
    local label desc
    label=$(jq -r --arg b "$bid" '.blueprints[$b].label // ""' "$REGISTRY")
    desc=$(jq -r --arg b "$bid" '.blueprints[$b].description // ""' "$REGISTRY")
    suf=""
    [[ -n "$desc" ]] && suf=" - $desc"
    echo "  $bid"
    echo "    $label$suf"
    echo ""
  done
}

resolve_target() {
  local parent="$1" bid="$2" name_or_path="$3"
  if is_explicit_path "$name_or_path"; then
    local p="$name_or_path"
    if [[ "$p" != /* ]]; then
      p="$parent/$p"
    fi
    mkdir -p "$(dirname "$p")"
    printf '%s' "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
    return 2
  fi
  printf '%s' "$parent/$(default_folder_name "$bid" "$name_or_path")"
  return 0
}

cmd_create() {
  load_registry
  local parent
  if [[ -n "${CREATE_PARENT_RAW:-}" ]]; then
    local raw="${CREATE_PARENT_RAW/#\~/$HOME}"
    if [[ "$raw" == /* ]]; then
      parent="$(cd "$raw" && pwd)" || die "bad --parent: $raw"
    else
      parent="$(cd "$REPO" && cd "$raw" && pwd)" || die "bad --parent: $raw"
    fi
  else
    mkdir -p "$REPO/$DEFAULT_PROJECTS"
    parent="$(cd "$REPO/$DEFAULT_PROJECTS" && pwd)"
  fi

  local pos=("$@")
  local bid name
  if [[ ${#pos[@]} -eq 1 ]]; then
    jq -e --arg d "$DEFAULT_BP" '.blueprints | has($d)' "$REGISTRY" >/dev/null || die "registry must define \"$DEFAULT_BP\" for single-argument create"
    bid="$DEFAULT_BP"
    name="${pos[0]}"
  elif [[ ${#pos[@]} -eq 2 ]]; then
    bid="${pos[0]}"
    name="${pos[1]}"
    jq -e --arg b "$bid" '.blueprints | has($b)' "$REGISTRY" >/dev/null || die "unknown blueprint \"$bid\". Use: list"
  else
    die "create: expected 1 or 2 arguments after options:
  create \"Client or path\"
  create presales \"Client or path\""
  fi

  mkdir -p "$parent"
  parent="$(cd "$parent" && pwd)"

  local target client_display client_slug dir_name
  if is_explicit_path "$name"; then
    target=$(resolve_target "$parent" "$bid" "$name")
    local _rc=$?
    client_display=""
    client_slug=""
    dir_name="$(basename "$target")"
  else
    target="$parent/$(default_folder_name "$bid" "$name")"
    client_display="${name#"${name%%[![:space:]]*}"}"
    client_display="${client_display%"${client_display##*[![:space:]]}"}"
    client_slug="$(normalize_slug "$name")"
    dir_name="$(default_folder_name "$bid" "$name")"
  fi

  if [[ -d "$target" ]] && [[ -n "$(find "$target" -mindepth 1 -print -quit)" ]]; then
    die "refusing to write into non-empty directory:\n  $target"
  fi
  mkdir -p "$target"
  merge_layers "$bid" "$target"
  if [[ "${CREATE_NO_RESET:-0}" != "1" ]]; then
    reset_directories "$target"
  fi
  if [[ -n "$client_display" ]]; then
    write_workbench "$target" "$bid" "$client_display" "$client_slug" "$dir_name"
  else
    write_workbench "$target" "$bid" "" "" "$dir_name"
  fi
  if [[ "${CREATE_GIT:-0}" == "1" ]]; then
    (cd "$target" && git init) || die "git init failed"
  fi
  echo "Created workspace:"
  echo "  $target"
  echo "Blueprint: $bid"
  if [[ "${CREATE_NO_RESET:-0}" != "1" ]]; then
    echo "Reset to empty: $(jq -r '.resetDirectories | join(", ")' "$REGISTRY") (.gitkeep only in each)."
  fi
  echo "Wrote $WORKBENCH_NAME (use for sync without repeating blueprint id)."
}

cmd_sync() {
  load_registry
  local dry="${SYNC_DRY:-0}"
  local a1="$1" a2="${2:-}"
  local bid target
  if [[ -n "$a2" ]]; then
    bid="$a1"
    target="$(cd "$(dirname "$a2")" && pwd)/$(basename "$a2")"
  else
    target="$(cd "$(dirname "$a1")" && pwd)/$(basename "$a1")"
    bid=$(read_workbench_bp "$target") || true
    [[ -n "$bid" ]] || die "no blueprint id in $target/$WORKBENCH_NAME. Use: sync BLUEPRINT PATH"
  fi
  [[ -d "$target" ]] || die "not a directory: $target"
  [[ -f "$target/.agent-instructions.md" ]] || echo "Warning: $target/.agent-instructions.md missing — sync may be wrong folder." >&2
  jq -e --arg b "$bid" '.blueprints | has($b)' "$REGISTRY" >/dev/null || die "unknown blueprint \"$bid\""

  if [[ "$dry" == "1" ]]; then
    echo "Would update from blueprint '$bid' (last overlay wins per path):"
    echo ""
    local shared_rel="$REPO/$(jq -r '.sharedRoot' "$REGISTRY")"
    declare -A last
    local f rel
    while IFS= read -r -d '' f; do
      rel="${f#"$shared_rel"/}"
      last["$rel"]="$shared_rel/$rel"
    done < <(find "$shared_rel" -type f -print0 2>/dev/null || true)
    local ov root
    while IFS= read -r ov; do
      [[ -z "$ov" ]] && continue
      root="$REPO/$ov"
      while IFS= read -r -d '' f; do
        rel="${f#"$root"/}"
        last["$rel"]="$root/$rel"
      done < <(find "$root" -type f -print0 2>/dev/null || true)
    done < <(jq -r --arg b "$bid" '.blueprints[$b].overlays[]? // empty' "$REGISTRY")
    local k
    for k in $(printf '%s\n' "${!last[@]}" | sort); do
      local tag="new"
      [[ -f "$target/$k" ]] && tag="exists"
      echo "  [$tag] $k"
    done
    echo ""
    echo "Dry run only; no files written."
    return 0
  fi

  merge_layers "$bid" "$target"
  update_workbench_sync "$target" "$bid"
  echo "Synced blueprint '$bid' into:"
  echo "  $target"
  echo "Engagement data under INPUTS, TASK-DEFINITIONS, WORK-IN-PROGRESS, DELIVERABLES was not cleared."
  echo "Matching paths from blueprints were overwritten."
  echo "Updated $WORKBENCH_NAME (last_synced_utc)."
}

# --- main ---
CREATE_PARENT_RAW=""
CREATE_NO_RESET=0
CREATE_GIT=0
SYNC_DRY=0

cmd="${1:-}"
[[ -z "$cmd" ]] && die "usage: $0 list | create ... | sync ..."

if [[ "$cmd" == "list" ]]; then
  cmd_list
  exit 0
fi

if [[ "$cmd" == "create" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parent|-p)
        CREATE_PARENT_RAW="${2:-}"
        shift 2 || die "create: --parent needs a value"
        ;;
      --no-reset) CREATE_NO_RESET=1; shift ;;
      --git) CREATE_GIT=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  cmd_create "$@"
  exit 0
fi

if [[ "$cmd" == "sync" ]]; then
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) SYNC_DRY=1; shift ;;
      *) break ;;
    esac
  done
  [[ $# -ge 1 ]] || die "sync: need PATH or BLUEPRINT PATH"
  cmd_sync "$@"
  exit 0
fi

die "unknown command \"$cmd\". Use: list | create | sync"
