# `nix-caddy-withplugins`

`caddy.withPlugins` without the hash invalidating every time Caddy gets updated.

## Usage

Using `nix-caddy-withplugins` is nearly identical to nixpkgs' `caddy` package.

```nix
caddy.withPlugins {
  plugins = [
    # module[@version][=replacement[@version]] (same as `xcaddy --with` syntax)
    "github.com/caddy-dns/cloudflare@v0.2.1"
    "github.com/caddy-dns/route53@v1.5.0"
    # require X, but fetch from a fork
    "github.com/caddy-dns/cloudflare@v0.2.1=github.com/myfork/cloudflare@v0.2.2"
  ];
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  # enabled by default, asserts each plugin is in the resulting binary
  doInstallCheck = true;
}
```

## Examples

### Flakes

```nix
{
  inputs.nix-caddy-withplugins.url = "github:MichailiK/nix-caddy-withplugins/nixos-unstable";

  outputs = { self, nixpkgs, nix-caddy-withplugins, ... }:
    let
      system = "x86_64-linux";
      caddy = nix-caddy-withplugins.packages.${system}.caddy;
    in {
      packages.${system}.myCaddy = caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-EXZTsf9KrIAi9gHsBHrYQ7oIQiYmLj6sYuQP5QihPcA=";
      };
    };
}
```
> [!IMPORTANT]
>
> Do not make this flake's nixpkgs follow yours. `nix-caddy-withplugins` must
> download Caddy's Go module (and dependencies) with a FOD using Go's toolkit.
> Changes to either Caddy or Go's tooling can change the FOD output and
> invalidate the FOD hash (stored in [./version.json](./version.json))

### Non-flakes

```nix
let nix-caddy-withplugins = import (fetchTarball "https://github.com/MichailiK/nix-caddy-withplugins/archive/nixos-unstable.tar.gz");
in nix-caddy-withplugins.packages.x86_64-linux.caddy.withPlugins {
  plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
  hash = "sha256-EXZTsf9KrIAi9gHsBHrYQ7oIQiYmLj6sYuQP5QihPcA=";
}
```

### Overlay

Add `nix-caddy-withplugins.overlays.default` to your `nixpkgs.overlays`
configuration. `pkgs.caddy.withPlugins { ... }` will use the decoupled plugin hash.

You should use the branch of `nix-caddy-withplugins` that matches your nixpkgs
channel (e.g. `nixos-unstable`, `nixos-26.05`)

## Finding your hash

Similarly to nixpkgs' Caddy, you can obtain the correct hash by leaving the
hash string empty or using `lib.fakeHash`. After the failed rebuild, insert
the expected hash.

## Implementation

This repo effectively re-implements `xcaddy` in Nix.

Additionally, Go modules get fetched in a somewhat unorthodox manner.
We are using 2 fixed output derivations that create
[`GOPROXY`](https://go.dev/ref/mod#goproxy-protocol)s:

1. "Base" modules FOD: The Caddy module (and its dependencies) get fetched from
   the network. The resulting `GOPROXY` cache will be outputted. The hash for
   this FOD is provided by this repo.
2. "Plugin" modules FOD: The Go cache of the previous FOD is used to fetch the
   Caddy module again, then, your plugins get fetched from the network. The Go
   cache gets compared to the previous cache, and any duplicates/delta will be
   deleted. The resulting `GOPROXY` cache will be outputted.

Effectively, this means that the second FOD only contains the Go
modules/dependencies of your plugins, so the same set of plugins will
result in the same FOD hash (most of the time, see Caveat section below).

Finally, both `GOPROXY` get combined into one, and Caddy gets built.

## Caveat

Under rare circumstances, due to Go's
[Minimal Version Selection](https://go.dev/ref/mod#minimal-version-selection),
the plugin modules FOD can unexpectedly change. This happens for
dependencies that are shared with Caddy & your plugins.

Example:

- Caddy depends on `github.com/libdns/libdns@v0.2.1`.
- One of your plugins (`caddy-dns/cloudflare`) needs `github.com/libdns/libdns@v0.2.2`.
- Since the plugin pins libdns higher, **v0.2.2 is added to your plugin modules**.
- Later, Caddy itself bumps to `libdns@v0.2.2`. Now Caddy already provides it,
  so it **drops out of your plugin modules FOD**, thus changing the plugins hash.
