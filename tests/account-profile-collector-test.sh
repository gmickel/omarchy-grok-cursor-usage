#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/profile" "$tmp/bin"

cat >"$tmp/bin/omarchy-agent-usage-claude" <<'EOF'
#!/usr/bin/env bash
jq -n --arg dir "$CLAUDE_CONFIG_DIR" '{id:"claude",name:"Claude Code",ready:true,configSeen:$dir,limits:[]}'
EOF
chmod +x "$tmp/bin/omarchy-agent-usage-claude"

cat >"$tmp/accounts.json" <<EOF
{"accounts":{"claude-test":{"provider":"claude","name":"Claude test","configDir":"$tmp/profile","collector":"$tmp/bin/omarchy-agent-usage-claude"}}}
EOF

ln -s "$root/collectors/account-profile-collector.py" "$tmp/omarchy-agent-usage-claude-test"
result=$(OMARCHY_AGENT_ACCOUNTS_FILE="$tmp/accounts.json" "$tmp/omarchy-agent-usage-claude-test")
jq -e --arg dir "$tmp/profile" '
  .id == "claude-test" and .name == "Claude test"
  and .providerFamily == "claude" and .configSeen == $dir
' <<<"$result" >/dev/null

echo "account profile collector: pass"
