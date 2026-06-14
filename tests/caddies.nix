# Exposes latest caddy & previous caddy version
{ pkgs }:
let
  latest = import ../packages/caddy.nix { inherit pkgs; };
  mkPrevious = import ./previousCaddy.nix { inherit pkgs; };
  fixtures = builtins.fromJSON (builtins.readFile ./testCaddies.json);

  previous = mkPrevious {
    inherit (fixtures.previous)
      version
      srcHash
      vendorHash
      caddyVendorProxyHash
      ;
  };
in
{
  inherit latest previous;
}
