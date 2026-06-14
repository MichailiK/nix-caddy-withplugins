{ pkgs }:
let
  inherit (pkgs.lib) fakeHash;

  decouple = import ../packages/decouple.nix { inherit pkgs; };
  mkPrevious = import ../tests/previousCaddy.nix { inherit pkgs; };
  sample = import ../tests/pluginSample.nix;

  mkProbes =
    caddy:
    let
      withSample = caddy.withPlugins {
        plugins = [ sample.spec ];
        hash = fakeHash;
      };
    in
    {
      inherit (caddy) version src goModules;
      inherit (withSample) caddyProxy pluginProxy;
    };
in
{
  latestVersion = pkgs.caddy.version;

  probe =
    {
      prevVersion,
      prevSrcHash ? fakeHash,
      prevCaddyVendorProxyHash ? fakeHash,
      latestCaddyVendorProxyHash ? fakeHash,
    }:
    {
      latest = mkProbes (decouple {
        caddy = pkgs.caddy;
        caddyVendorProxyHash = latestCaddyVendorProxyHash;
      });

      previous = mkProbes (mkPrevious {
        version = prevVersion;
        srcHash = prevSrcHash;
        vendorHash = fakeHash;
        caddyVendorProxyHash = prevCaddyVendorProxyHash;
      });
    };
}
