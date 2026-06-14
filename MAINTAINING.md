# Maintaining

Notes for maintaining `nix-caddy-withplugins`.

## Updating Caddy

Caddy updates are automated daily by the
[`update.yml`](.github/workflows/update.yml) Workflow, on the `nixos-unstable`
and the latest `nixos-XX.YY` branches.

To manually update Caddy:

1. `nix flake update`
2. Run `nix develop --command ./update/update.py` to recompute this repo's Caddy
   version and FOD hashes.

The update script will output `Update completed` if there was an update.
Otherwise it will output `Up to date` if there is no update.

> If the update script reports that
> `Update completed: caddy {version} unchanged, but FOD hashes have changed`,
> it means that, while there is no update for Caddy, Go tooling has likely been
> updated and that has caused (likely `go mod`) to produce different outputs.
> Such a change should be PR'd as well.

## Branch model

Branches mirror nixpkgs' channels:

- `nixos-unstable` - default branch
- `nixos-XX.YY` - stable nixpkgs branch

The primary difference between the branches is the nixpkgs input used in the flake:

`flake.nix`
```nix
inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # or nixos-XX.YY for stable branches
```

Any non-bump related changes to `nixos-unstable` should be backported to the
latest stable branch.

Similarly to nixpkgs, only `nixos-unstable` & the latest stable branch is
supported. Support for older branches gets dropped.

### Branch-offs

nixpkgs usually branches off a new stable release twice a year. When it does,
`nix-caddy-withplugins` should follow along by branching off `nixos-unstable`
as well:

1. Create a new `nixos-XX.YY` branch from `nixos-unstable`
2. Update `inputs.nixpkgs.url` in `flake.nix` to point to the new branch:

   ```nix
   inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-XX.YY";
   ```

3. Follow [Updating Caddy](#updating-caddy)
  - `nix flake update`
  - `nix develop --command ./update/update.py`
4. Push the new stable branch
5. Update the [`update.yml`](.github/workflows/update.yml) workflow to
   change the `branch:` list, replacing the old stable branch with the new one:

   ```yaml
   branch:
     - nixos-unstable
     - nixos-26.05 # was nixos-25.11
   ```
