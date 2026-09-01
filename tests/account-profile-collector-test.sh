#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/config/omarchy/agents" "$tmp/profiles/one" "$tmp/profiles/two" "$tmp/profiles/codex" "$tmp/bin"

cat >"$tmp/bin/omarchy-agent-usage-claude" <<'EOF'
#!/usr/bin/env bash
echo "collector warning" >&2
[[ ${1:-} != --fail ]] || exit 7
jq -n \
  --arg dir "$CLAUDE_CONFIG_DIR" \
  --arg cache "$XDG_CACHE_HOME" \
  --arg first "${1:-}" \
  '{id:"claude",name:"Claude Code",ready:true,configSeen:$dir,cacheSeen:$cache,firstArg:$first,limits:[]}'
EOF
chmod +x "$tmp/bin/omarchy-agent-usage-claude"

cat >"$tmp/config/omarchy/agents/omarchy-agent-usage-codex" <<'EOF'
#!/usr/bin/env bash
jq -n --arg dir "$CODEX_HOME" '{id:"codex",name:"Codex",ready:true,configSeen:$dir,limits:[]}'
EOF
chmod +x "$tmp/config/omarchy/agents/omarchy-agent-usage-codex"

cat >"$tmp/config/omarchy/agents/accounts.json" <<'EOF'
{
  "schemaVersion": 1,
  "accounts": {
    "claude-one": {
      "provider": "claude",
      "name": "Claude one",
      "configDir": "../../../profiles/one",
      "collector": "../../../bin/omarchy-agent-usage-claude"
    },
    "claude-two": {
      "provider": "claude",
      "name": "Claude two",
      "configDir": "../../../profiles/two",
      "collector": "../../../bin/omarchy-agent-usage-claude"
    },
    "codex-default": {
      "provider": "codex",
      "configDir": "../../../profiles/codex"
    }
  }
}
EOF

collector="$root/collectors/account-profile-collector.py"
common_env=(HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" XDG_CACHE_HOME="$tmp/cache")

listing=$(env "${common_env[@]}" python3 "$collector" --list)
jq -e '
  length == 3
  and .[0] == {id:"claude-one",provider:"claude"}
  and .[1] == {id:"claude-two",provider:"claude"}
  and .[2] == {id:"codex-default",provider:"codex"}
' <<<"$listing" >/dev/null

one=$(env "${common_env[@]}" python3 "$collector" --account claude-one --limits-only 2>"$tmp/one.stderr")
two=$(env "${common_env[@]}" python3 "$collector" --account claude-two 2>"$tmp/two.stderr")
codex=$(env "${common_env[@]}" python3 "$collector" --account codex-default)
jq -e --arg dir "$tmp/profiles/one" --arg cache "$tmp/cache/omarchy/agent-profile-cache/claude-one" '
  .id == "claude-one" and .name == "Claude one"
  and .providerFamily == "claude" and .configSeen == $dir
  and .cacheSeen == $cache and .firstArg == "--limits-only"
' <<<"$one" >/dev/null
jq -e --arg dir "$tmp/profiles/two" --arg cache "$tmp/cache/omarchy/agent-profile-cache/claude-two" '
  .id == "claude-two" and .name == "Claude two"
  and .providerFamily == "claude" and .configSeen == $dir
  and .cacheSeen == $cache
' <<<"$two" >/dev/null
grep -qx "collector warning" "$tmp/one.stderr"
grep -qx "collector warning" "$tmp/two.stderr"
jq -e --arg dir "$tmp/profiles/codex" '
  .id == "codex-default" and .name == "codex-default"
  and .providerFamily == "codex" and .configSeen == $dir
' <<<"$codex" >/dev/null

set +e
env "${common_env[@]}" python3 "$collector" --account claude-one --fail >/dev/null 2>"$tmp/fail.stderr"
rc=$?
set -e
[[ $rc -eq 7 ]]
grep -qx "collector warning" "$tmp/fail.stderr"

cat >"$tmp/bad.json" <<'EOF'
{"schemaVersion":1,"accounts":{"broken":"not an object"}}
EOF
set +e
OMARCHY_AGENT_ACCOUNTS_FILE="$tmp/bad.json" python3 "$collector" --list >/dev/null 2>"$tmp/bad.stderr"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -q "account 'broken' must be a JSON object" "$tmp/bad.stderr"
! grep -q "Traceback" "$tmp/bad.stderr"

cat >"$tmp/bad-id.json" <<'EOF'
{"schemaVersion":1,"accounts":{".hidden":{"provider":"claude","configDir":"/tmp"}}}
EOF
set +e
OMARCHY_AGENT_ACCOUNTS_FILE="$tmp/bad-id.json" python3 "$collector" --list >/dev/null 2>"$tmp/bad-id.stderr"
rc=$?
set -e
[[ $rc -eq 2 ]]
grep -q "invalid account id '.hidden'" "$tmp/bad-id.stderr"

echo "account profile collector: pass"
