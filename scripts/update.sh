#!/usr/bin/env bash
# Recompute this flake's hashes with the current Caddy the nixpkgs input now
# provides. Run this after a `nix flake update`.
#
# Two modes, picked automatically:
# - bump: nixpkgs' caddy version got bumped. The vendor proxy hash for the new
#   Caddy version gets computed, and the previous version is stored for testing.
# - refresh: Caddy did not get bumped, but Go-derived hashes
#   (base proxy and sample plugin hash) got recomputed, likely because of a bump
#   in the Go toolchain
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO"

SYSTEM=${SYSTEM:-$(nix eval --impure --raw --expr builtins.currentSystem)}
FAKE="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" # lib.fakeHash

note() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
emit() { if [[ -n ${GITHUB_OUTPUT:-} ]]; then echo "$1=$2" >>"$GITHUB_OUTPUT"; fi; }

# jq_edit FILE <jq-args...>: edits FILE in place
jq_edit() {
  local file=$1
  shift
  local tmp
  tmp=$(mktemp)
  jq "$@" "$file" >"$tmp"
  mv "$tmp" "$file"
}

# update_attr <attrPath>: Returns Nix expression for evaluating an attribute of
# this flake's `_update` output.
update_attr() { echo "(builtins.getFlake \"path:$REPO\")._update.$SYSTEM.$1"; }

# update_eval <expr>: Evaluate a string-valued `_update` attribute (e.g. a version).
update_eval() { nix eval --impure --raw --expr "$(update_attr "$1")"; }

# update_fod <attrPath>: Obtain the real SRI of a FOD in `_update` by
# building the expression with a fake hash.
update_fod() {
  local out
  if out=$(nix build --impure --no-link --expr "$(update_attr "$1")" 2>&1); then
    echo "update_fod: expected a hash mismatch but the build succeeded for: $1" >&2
    return 1
  fi
  grep -oP 'got:\s+\K\S+' <<<"$out" | tail -n1
}

# Detect mode
ACTUAL=$(update_eval latest.version)
RECORDED=$(jq -r '.version' version.json)
note "nixpkgs has caddy $ACTUAL, version.json has caddy $RECORDED"

if [[ $ACTUAL == "$RECORDED" ]]; then
  MODE=refresh
  note "mode: refresh"
else
  MODE=bump
  note "mode: bump ($RECORDED -> $ACTUAL)"
fi

if [[ $MODE == bump ]]; then
  # Temporarily use fake hashes
  jq_edit version.json --arg v "$ACTUAL" --arg f "$FAKE" \
    '{ version: $v, caddyVendorProxyHash: $f }'
  jq_edit tests/previous.json --arg v "$RECORDED" --arg f "$FAKE" \
    '{ version: $v, srcHash: $f, vendorHash: $f, caddyVendorProxyHash: $f }'

  note "computing srcHash for the demoted release $RECORDED"
  jq_edit tests/previous.json --arg h "$(update_fod previous.src)" '.srcHash = $h'
else # mode = refresh
  # Temporarily use fake hashes
  jq_edit version.json --arg f "$FAKE" '.caddyVendorProxyHash = $f'
  jq_edit tests/previous.json --arg f "$FAKE" \
    '.vendorHash = $f | .caddyVendorProxyHash = $f'
fi

PREV=$(jq -r '.version' tests/previous.json)

note "computing previous $PREV vendorHash"
jq_edit tests/previous.json --arg h "$(update_fod previous.goModules)" '.vendorHash = $h'

note "computing latest $ACTUAL vendorProxy hash"
jq_edit version.json --arg h "$(update_fod latest.caddyProxy)" '.caddyVendorProxyHash = $h'

note "computing previous $PREV vendorProxy hash"
jq_edit tests/previous.json --arg h "$(update_fod previous.caddyProxy)" '.caddyVendorProxyHash = $h'

note "computing sample plugin hashes"
latestPluginHash=$(update_fod latest.pluginProxy)
prevPluginHash=$(update_fod previous.pluginProxy)

jq -n --arg lv "$ACTUAL" --arg ld "$latestPluginHash" --arg pv "$PREV" --arg pd "$prevPluginHash" \
  '{($lv): $ld, ($pv): $pd}' >tests/pluginSampleHashes.json

# Outputs + MVS notice
emit mode "$MODE"
emit version "$ACTUAL"
emit previous "$PREV"

if [[ $latestPluginHash != "$prevPluginHash" ]]; then
  note "NOTE: The sample plugin hash changed in this bump."
  note "Prev: $PREV ($prevPluginHash)"
  note "New : $ACTUAL ($latestPluginHash)"
  emit plugin_hash_shift true
else
  emit plugin_hash_shift false
fi

note "Update completed."
