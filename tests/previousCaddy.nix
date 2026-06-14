{ pkgs }:
{
  version,
  srcHash,
  vendorHash,
  caddyVendorProxyHash,
}:
let
  decouple = import ../packages/decouple.nix { inherit pkgs; };
in
decouple {
  caddy = pkgs.caddy.overrideAttrs (_: {
    inherit version vendorHash;
    src = pkgs.fetchFromGitHub {
      owner = "caddyserver";
      repo = "caddy";
      tag = "v${version}";
      hash = srcHash;
    };
  });
  inherit caddyVendorProxyHash;
}
