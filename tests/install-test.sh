#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
config="$tmp/config"
mkdir -p "$config/omarchy"
cat >"$config/omarchy/shell.json" <<'EOF'
{
  "bar": {
    "layout": {
      "left": [],
      "center": [],
      "right": [{"id": "omarchy.agents"}]
    }
  }
}
EOF

HOME="$tmp" USER="test-user" XDG_CONFIG_HOME="$config" "$root/install.sh" --apply-layout >/dev/null

agents="$config/omarchy/agents"
plugin="$config/omarchy/plugins/test-user.agents"
[[ -x $agents/account-profile-collector.py ]]
[[ -x $agents/run-usage-update ]]
[[ -f $agents/accounts.example.json ]]
[[ ! -e $agents/accounts.json ]]
jq -e '.schemaVersion == 1 and (.accounts | length) == 2' "$agents/accounts.example.json" >/dev/null
jq -e '.bar.layout.right[0].id == "test-user.agents"' "$config/omarchy/shell.json" >/dev/null
jq -e '.id == "test-user.agents"' "$plugin/manifest.json" >/dev/null

echo "install: pass"
