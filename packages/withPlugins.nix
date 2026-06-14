/*
  `caddy.withPlugins`

  Builds a custom Caddy with plugins, whose FODs for plugins have been decoupled
  from Caddy itself.

  Like xcaddy, a main.go gets generated that imports the plugins and
  `go build`s it.

  Dependency fetching is split into two FODs that generate Go module proxy trees:
  - caddyProxy, which only contains caddy & its dependencies. its FOD hash is
    derived from ../version.json.
  - pluginProxy, which contains plugins (with their dependencies), MINUS
    caddyProxy's dependencies. its FOD hash is provided by the user.

  Both are then assembled into a single module proxy, from which Caddy gets built.
*/
{
  lib,
  stdenv,
  runCommand,
  cacert,
  git,
  rsync,
  caddy,

  # Hash of caddyProxy
  caddyVendorProxyHash,
  go ? caddy.go,
}:

let
  caddyModule = "github.com/caddyserver/caddy/v2";
in

{
  plugins,

  # Hash of pluginProxy, provided by users
  hash ? lib.fakeHash,

  doInstallCheck ? true,
}:

let
  # Parse a plugin spec `module[@version][=replacement[@version]]`.
  # A replacement keeps the blank import of `module` but sources it from
  # `replacement`.
  parsePlugin =
    spec:
    let
      eq = lib.splitString "=" spec;
      modVer = lib.head eq;
      replaceStr = lib.concatStringsSep "=" (lib.tail eq);
      hasReplace = lib.length eq > 1;

      splitVersion =
        s:
        let
          parts = lib.splitString "@" s;
        in
        {
          path = lib.head parts;
          version = lib.last parts;
          hasVersion = lib.length parts > 1;
        };

      mod = splitVersion modVer;
      repl = splitVersion replaceStr;
    in
    {
      inherit spec hasReplace;
      inherit (mod) path version hasVersion;
      replPath = repl.path;
      replVersion = repl.version;
      replHasVersion = repl.hasVersion;
    };

  parsed = map parsePlugin plugins;
  pluginPaths = map (p: p.path) parsed;

  # Modules must have names
  emptyModule = lib.filter (p: p.path == "") parsed;
  # Modules must have a version
  unpinned = lib.filter (p: !(if p.hasReplace then p.replHasVersion else p.hasVersion)) parsed;

  # `go mod edit` args
  requireArgs = lib.concatMapStringsSep " " (
    p: lib.optionalString p.hasVersion "-require=${p.path}@${p.version}"
  ) parsed;
  replaceArgs = lib.concatMapStringsSep " " (
    p: lib.optionalString p.hasReplace "-replace=${p.path}=${p.replPath}@${p.replVersion}"
  ) parsed;

  # taken from Caddy's cmd/caddy/main.go
  mkMainGo = pluginPaths: ''
    package main

    import (
      _ "time/tzdata"

      caddycmd "${caddyModule}/cmd"

      // plug in Caddy modules here
      _ "${caddyModule}/modules/standard"${lib.concatMapStrings (p: "\n      _ \"${p}\"") pluginPaths}
    )

    func main() {
      caddycmd.Main()
    }
  '';

  # FOD that builds a Go module proxy (cache/download tree) of a wrapper
  # module. A base module proxy can be specified, which will be used
  # to fetch deps (then fallback to network.) Any deps found in the base
  # will be removed from the output. In this case, it means that only the Caddy
  # plugin modules (and their deps) are output, hence producing a stable hash
  # (assuming no MVS.)
  mkProxy =
    {
      pname,
      mainGoText,
      requireArgs ? "",
      replaceArgs ? "",
      base ? null,
      hash,
    }:
    stdenv.mkDerivation {
      inherit pname;
      inherit (caddy) version;

      nativeBuildInputs = [
        go
        cacert
        git
        rsync
      ];
      dontUnpack = true;

      buildPhase = ''
        runHook preBuild

        export HOME=$TMPDIR
        export GOPATH=$TMPDIR/go
        export GOCACHE=$TMPDIR/go-cache
        export GOMODCACHE=$TMPDIR/go/pkg/mod
        export GOTOOLCHAIN=local
        export GOPROXY=${lib.optionalString (base != null) "file://${base},"}https://proxy.golang.org,direct
        export GIT_SSL_CAINFO=$NIX_SSL_CERT_FILE

        mkdir -p build && cd build
        printf '%s' "$mainGoText" > main.go
        go mod init caddy

        go mod edit -replace=${caddyModule}=${caddy.src}
        go mod edit -require=${caddyModule}@v${caddy.version} ${requireArgs} ${replaceArgs}

        go mod tidy
        go mod download

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        rm -rf $GOMODCACHE/cache/download/sumdb

        mkdir -p $out
        ${
          if base == null then
            ''
              cp -a $GOMODCACHE/cache/download/. $out/
            ''
          else
            # Only keep modules that the base proxy doesn't have.
            ''
              rsync -rlc --prune-empty-dirs \
                --compare-dest=${base}/ \
                $GOMODCACHE/cache/download/ $out/
            ''
        }

        # `rsync --compare-dest` recreates the source's directories, even
        # for dirs that exclude every file. `--prune-empty-dirs` does NOT catch
        # them, rsync judges emptiness on the source, before exclusion.
        # Empty directories are deleted to prevent hash changes.
        find $out -mindepth 1 -depth -type d -empty -delete

        runHook postInstall
      '';

      env = { inherit mainGoText; };

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = hash;
    };

  caddyProxy = mkProxy {
    pname = "caddy-base-proxy";
    mainGoText = mkMainGo [ ];
    hash = caddyVendorProxyHash;
  };

  mainGo = mkMainGo pluginPaths;
  pluginProxy = mkProxy {
    pname = "caddy-plugins-proxy";
    mainGoText = mainGo;
    inherit requireArgs replaceArgs;
    base = caddyProxy;
    inherit hash;
  };

  assembledSrc =
    runCommand "caddy-with-plugins-src"
      {
        nativeBuildInputs = [ go ];
        env = { inherit mainGo; };
      }
      ''
        export HOME=$TMPDIR
        export GOPATH=$TMPDIR/go
        export GOCACHE=$TMPDIR/go-cache
        export GOMODCACHE=$TMPDIR/go/pkg/mod
        export GOTOOLCHAIN=local

        mkdir -p proxy
        cp -r --no-preserve=mode,ownership ${caddyProxy}/.   proxy/
        cp -r --no-preserve=mode,ownership ${pluginProxy}/.  proxy/
        chmod -R u+w proxy

        export GOPROXY=file://$PWD/proxy
        export GOFLAGS=-mod=mod
        export GOSUMDB=off

        mkdir -p $out && cd $out
        printf '%s' "$mainGo" > main.go

        cp -r --no-preserve=mode,ownership ${caddy.src} caddy
        go mod init caddy
        go mod edit -replace=${caddyModule}=./caddy
        go mod edit -require=${caddyModule}@v${caddy.version} ${requireArgs} ${replaceArgs}

        go mod tidy
        go mod vendor
      '';
in

assert lib.assertMsg (
  emptyModule == [ ]
) "caddy.withPlugins: every plugin spec must name a module (\"github.com/owner/repo@v1.2.3\")";
assert lib.assertMsg (unpinned == [ ])
  "caddy.withPlugins: every plugin needs an explicit version (\"github.com/owner/repo@v1.2.3\" or \"github.com/owner/repo=github.com/fork/repo@v1.2.3\")";

caddy.overrideAttrs (
  finalAttrs: prevAttrs: {
    src = assembledSrc;
    vendorHash = null;
    proxyVendor = false;
    subPackages = [ "." ];

    inherit doInstallCheck;

    installCheckPhase = ''
      runHook preInstallCheck

      declare -A modules
      while read -r kind module version _; do
        case "$kind" in
          'dep' | '=>') modules[$module]=$version ;;
        esac
      done < <($out/bin/caddy build-info)

      rc=0
      ${lib.concatMapStrings (
        p:
        if p.hasReplace then
          ''
            if [[ -z "''${modules[${p.replPath}]:-}" ]]; then
              echo "Error: plugin \"${p.spec}\": replacement \"${p.replPath}\" not found in caddy build-info" >&2
              rc=1
            elif [[ "''${modules[${p.replPath}]}" != "${p.replVersion}" ]]; then
              echo "Error: plugin \"${p.spec}\": replacement at wrong version: got ''${modules[${p.replPath}]}, expected ${p.replVersion}" >&2
              rc=1
            fi
          ''
        else
          ''
            if [[ -z "''${modules[${p.path}]:-}" ]]; then
              echo "Error: plugin \"${p.spec}\" not found in caddy build-info" >&2
              rc=1
            elif [[ "''${modules[${p.path}]}" != "${p.version}" ]]; then
              echo "Error: plugin \"${p.spec}\" present at wrong version: got ''${modules[${p.path}]}, expected ${p.version}" >&2
              rc=1
            fi
          ''
      ) parsed}

      [[ $rc -ne 0 ]] && { echo '(set `caddy.withPlugins { doInstallCheck = false; }` to ignore)' >&2; exit 1; }

      runHook postInstallCheck
    '';

    # Expose the intermediate FODs so tooling (update/update.py) can realise them in
    # isolation to read back their fixed-output hashes, and so they are easy to
    # inspect when debugging the subtraction.
    passthru = (prevAttrs.passthru or { }) // {
      inherit caddyProxy pluginProxy assembledSrc;
    };
  }
)
