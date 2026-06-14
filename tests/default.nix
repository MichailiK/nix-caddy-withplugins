# Checks for the latest and previous caddy versions, ensuring:
# - pluginHash_<version>: plugin hash hasn't changed
# - pluginActive_<version>: Ensures that sample plugin is present & active in
#   the Caddy binary.
{ pkgs }:

let
  inherit (pkgs) lib;

  caddies = import ./caddies.nix { inherit pkgs; };
  pluginHashes = builtins.fromJSON (builtins.readFile ./pluginSampleHashes.json);
  sample = import ./pluginSample.nix;

  suffix = v: lib.replaceStrings [ "." ] [ "_" ] v;

  mkChecks =
    caddy:
    let
      version = caddy.version;
      caddyWith = caddy.withPlugins {
        plugins = [ sample.spec ];
        hash = pluginHashes.${version};
      };
    in
    [
      {
        name = "pluginHash_${suffix version}";
        value = caddyWith;
      }
      {
        name = "pluginActive_${suffix version}";
        value = pkgs.runCommand "caddy-${version}-plugin-active" { } ''
          echo "checking '${sample.moduleId}' is registered in caddy ${version}..."
          modules=$(${caddyWith}/bin/caddy list-modules)
          if ! grep -qF '${sample.moduleId}' <<<"$modules"; then
            echo "FAIL: '${sample.moduleId}' missing from 'caddy list-modules':" >&2
            echo "$modules" >&2
            exit 1
          fi
          echo "ok: plugin module registered" > "$out"
        '';
      }
    ];
in
lib.listToAttrs (lib.concatMap mkChecks caddies.all)
