{
  description = "Custom Caddy builds whose plugin hash is independent of the Caddy version";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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

      # Consumed by ./scripts/update.sh.
      _update = forAllSystems ({ pkgs, ... }: import ./tests/packages.nix { inherit pkgs; });

      devShells = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.mkShellNoCC {
            # scripts/update.sh drives everything through `nix` + `jq`.
            packages = [ pkgs.jq ];
          };
        }
      );

      formatter = forAllSystems ({ pkgs, ... }: pkgs.nixfmt);
    };
}
