# Maintaining

Notes for maintaining of `nix-caddy-withplugins`.

## Updating Caddy

This is automated daily by the [`update.yml`](.github/workflows/update.yml)
Workflow, on the `nixos-unstable` branch and the latest `nixos-XX.YY`
branch.

To update Caddy:

1. `nix flake update`
2. Run `nix develop --command ./update/update.py` to recoumpute this repo's Caddy
   version and FOD hashes.

If `version.json` changed, that means a new Caddy update is available. A PR
should be opened to bump Caddy.

> If only the hashes inside `tests/testCaddies.json` changes, it means that,
> while there is no update for Caddy, Go tooling has likely been updated
> and (likely `go mod`) has produced different outputs. Such a change
> should be PR'd as well.

## Branch model

Branches mirror nixpkgs' channels:

- `nixos-unstable` — the default branch.
- `nixos-XX.YY` — one per supported stable release

The primary difference between the brnaches is the nixpkgs input used in the flake:

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
