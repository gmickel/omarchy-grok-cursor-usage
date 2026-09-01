#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
agents="$tmp/config/omarchy/agents"
usage="$tmp/state/omarchy/agents/usage"
packaged="$tmp/omarchy/bin"
mkdir -p "$agents" "$usage" "$packaged" "$tmp/profiles/one" "$tmp/profiles/two"

install -m 0755 "$root/collectors/account-profile-collector.py" "$agents/account-profile-collector.py"
install -m 0755 "$root/collectors/run-usage-update" "$agents/run-usage-update"

cat >"$agents/omarchy-agent-usage-claude" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
print(json.dumps({
    "id": "claude",
    "name": "Claude",
    "ready": True,
    "profile": os.environ["CLAUDE_CONFIG_DIR"],
    "flags": sys.argv[1:],
    "limits": [],
}))
EOF
chmod +x "$agents/omarchy-agent-usage-claude"

cat >"$agents/omarchy-agent-usage-grok" <<'EOF'
#!/usr/bin/env python3
import json
print(json.dumps({"id":"grok","name":"Grok","ready":True,"limits":[]}))
EOF
chmod +x "$agents/omarchy-agent-usage-grok"

cat >"$agents/accounts.json" <<EOF
{
  "schemaVersion": 1,
  "accounts": {
    "claude-one": {"provider":"claude","name":"Claude one","configDir":"$tmp/profiles/one"},
    "claude-two": {"provider":"claude","name":"Claude two","configDir":"$tmp/profiles/two"}
  }
}
EOF

cat >"$packaged/omarchy-agent-usage-update" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PACKAGED_ARGS_FILE"
EOF
chmod +x "$packaged/omarchy-agent-usage-update"

run=(env HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" OMARCHY_PATH="$tmp/omarchy" PACKAGED_ARGS_FILE="$tmp/packaged.args" "$agents/run-usage-update")

printf '%s\n' '{"id":"claude","ready":true}' >"$usage/claude.json"
"${run[@]}" --limits-only
jq -e --arg profile "$tmp/profiles/one" '.id == "claude-one" and .profile == $profile and .flags == ["--limits-only"]' "$usage/claude-one.json" >/dev/null
jq -e --arg profile "$tmp/profiles/two" '.id == "claude-two" and .profile == $profile' "$usage/claude-two.json" >/dev/null
jq -e '.id == "grok"' "$usage/grok.json" >/dev/null
[[ ! -e $usage/claude.json ]]
grep -qx -- "--except" "$tmp/packaged.args"
grep -qx "claude" "$tmp/packaged.args"
grep -qx "claude-one" "$tmp/packaged.args"
grep -qx "claude-two" "$tmp/packaged.args"
grep -qx "grok" "$tmp/packaged.args"

mv "$usage/claude-one.json" "$tmp/claude-one.before"
mv "$usage/claude-two.json" "$tmp/claude-two.before"
"${run[@]}" claude-one
[[ -f $usage/claude-one.json ]]
[[ ! -f $usage/claude-two.json ]]

mv "$usage/claude-one.json" "$tmp/claude-one.selected"
"${run[@]}" claude
[[ -f $usage/claude-one.json ]]
[[ -f $usage/claude-two.json ]]
grep -qx "claude" "$tmp/packaged.args"

set +e
"${run[@]}" --forc >/dev/null 2>"$tmp/unknown.stderr"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -qx "run-usage-update: unknown option: --forc" "$tmp/unknown.stderr"

set +e
"${run[@]}" --except >/dev/null 2>"$tmp/except.stderr"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -qx "run-usage-update: --except needs an id" "$tmp/except.stderr"

echo "run usage update: pass"
