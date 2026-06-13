{ pkgs }:
{
  caddy,
  caddyVendorProxyHash,
}:
caddy.overrideAttrs (
  final: prev: {
    passthru = (prev.passthru or { }) // {
      withPlugins = pkgs.callPackage ./withPlugins.nix {
        caddy = final.finalPackage;
        inherit caddyVendorProxyHash;
      };
    };
  }
)
