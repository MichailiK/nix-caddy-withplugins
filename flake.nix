{
  description = "`caddy.withPlugins` without the hash invalidating every time Caddy gets updated.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f {
            pkgs = nixpkgs.legacyPackages.${system};
            inherit system;
          }
        );

      caddyFor = pkgs: import ./packages/caddy.nix { inherit pkgs; };
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        let
          caddy = caddyFor pkgs;
        in
        {
          inherit caddy;
          default = caddy;
        }
      );

      overlays.default = final: prev: {
        caddy = import ./packages/caddy.nix {
          pkgs = final;
          inherit (prev) caddy;
        };
      };

      checks = forAllSystems ({ pkgs, ... }: import ./tests { inherit pkgs; });

      # Consumed by ./update/update.py.
      _update = forAllSystems ({ pkgs, ... }: import ./update { inherit pkgs; });

      devShells = forAllSystems (
        { pkgs, ... }:
        {
          # dev shell for ./update/update.py
          default = pkgs.mkShellNoCC {
            packages = [ pkgs.python3 ];
          };
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt);
    };
}
