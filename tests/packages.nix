{ pkgs }:
let
  caddies = import ./caddies.nix { inherit pkgs; };
  sample = import ./pluginSample.nix;

  mkTestCaddy =
    caddy:
    let
      withSample = caddy.withPlugins {
        plugins = [ sample.spec ];
        hash = pkgs.lib.fakeHash;
      };
    in
    {
      inherit (caddy) version src goModules;
      inherit (withSample) caddyProxy pluginProxy;
    };
in
{
  latest = mkTestCaddy caddies.latest;
  previous = mkTestCaddy caddies.previous;
}
