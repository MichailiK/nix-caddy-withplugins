# Exposes latest caddy & previous caddy version
{ pkgs }:
let
  latest = import ../packages/caddy.nix { inherit pkgs; };
  decouple = import ../packages/decouple.nix { inherit pkgs; };
  prevVersion = builtins.fromJSON (builtins.readFile ./previousVersion.json);

  previous = decouple {
    caddy = pkgs.caddy.overrideAttrs (_: {
      inherit (prevVersion) version vendorHash;
      src = pkgs.fetchFromGitHub {
        owner = "caddyserver";
        repo = "caddy";
        tag = "v${prevVersion.version}";
        hash = prevVersion.srcHash;
      };
    });
    inherit (prevVersion) caddyVendorProxyHash;
  };
in
{
  inherit latest previous;
  all = [
    latest
    previous
  ];
}
