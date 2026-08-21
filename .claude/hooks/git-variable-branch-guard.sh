#!/bin/bash
# PreToolUse guard for Bash: auto-allow git branch/checkout/add/commit/push
# writes, unsandboxed, but only when the branch involved is variable/* (the
# variable-deriver agent's naming convention). Everything else falls through
# to the normal permission + sandbox flow untouched.
set -euo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")

[[ "$cmd" == git\ * ]] || exit 0

emit_allow() {
  jq --argjson orig "$input" -n '
    (($orig.tool_input // {}) + {dangerouslyDisableSandbox: true}) as $ui |
    {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "git write on variable/* branch",
        updatedInput: $ui
      }
    }'
  exit 0
}

current_branch() {
  git branch --show-current 2>/dev/null || true
}

# git checkout/switch, with or without -b/-c (create or move to existing branch)
if [[ "$cmd" =~ ^git\ (checkout|switch)\ (-[bc]\ )?([^[:space:]]+) ]]; then
  branch="${BASH_REMATCH[3]}"
  [[ "$branch" == variable/* ]] && emit_allow
  exit 0
fi

# git branch <name>  (branch creation without checkout)
if [[ "$cmd" =~ ^git\ branch\ ([^[:space:]-][^[:space:]]*)[[:space:]]*$ ]]; then
  branch="${BASH_REMATCH[1]}"
  [[ "$branch" == variable/* ]] && emit_allow
  exit 0
fi

# git push [-u] origin <branch>[...]
if [[ "$cmd" =~ ^git\ push(\ -u)?\ origin\ ([^[:space:]:]+) ]]; then
  branch="${BASH_REMATCH[2]}"
  [[ "$branch" == variable/* ]] && emit_allow
  exit 0
fi

# tree-mutating commands with no branch in the command itself: gate on HEAD
if [[ "$cmd" =~ ^git\ (add|commit|rm|mv)([[:space:]]|$) ]]; then
  branch=$(current_branch)
  [[ "$branch" == variable/* ]] && emit_allow
  exit 0
fi

exit 0
