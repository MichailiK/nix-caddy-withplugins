{
  pkgs,
  caddy ? pkgs.caddy,
}:
let
  version = builtins.fromJSON (builtins.readFile ../version.json);
  decouple = import ./decouple.nix { inherit pkgs; };

  versionMatches = caddy.version == version.version;
in
pkgs.lib.warnIf (!versionMatches)
  "nix-caddy-withplugins: Expected caddy version ${version.version} but received ${caddy.version}. `caddy.withPlugins` will fail with a hash mismatch. If you are using flakes, make sure to not override this flake's nixpkgs (remove `inputs.nix-caddy-withplugins.inputs.nixpkgs.follows = \"...\";`)"
  (decouple {
    inherit caddy;
    inherit (version) caddyVendorProxyHash;
  })
