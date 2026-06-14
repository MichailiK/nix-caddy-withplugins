#!/usr/bin/env python3
"""
Recompute this flake's FOD hashes for the Caddy the nixpkgs input now provides.

Run this after a `nix flake update`. Two modes, picked automatically:

- bump: nixpkgs' caddy version changed. The new version's proxy hash is
  computed and the previous version is demoted to the test fixture.
- refresh: the version is unchanged but Go-derived hashes moved (e.g. a Go
  toolchain bump), so they get recomputed.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
VERSION_JSON = REPO / "version.json"
TEST_CADDIES_JSON = REPO / "tests" / "testCaddies.json"

FAKE = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="  # lib.fakeHash
GOT_RE = re.compile(r"got:\s+(\S+)")


def note(msg: str) -> None:
    print(f"==> {msg}", file=sys.stderr, flush=True)


def emit(key: str, value: str) -> None:
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"{key}={value}\n")


def system() -> str:
    if s := os.environ.get("SYSTEM"):
        return s
    return subprocess.run(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


SYSTEM = system()


def update_expr(suffix: str) -> str:
    return f'(builtins.getFlake "path:{REPO}")._update.{SYSTEM}.{suffix}'


def latest_version() -> str:
    return subprocess.run(
        ["nix", "eval", "--impure", "--raw", "--expr", update_expr("latestVersion")],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def probe(attr: str, args: dict) -> str:
    "Build `_update.probe(args).<attr>` with a fake hash and return the real one."

    with tempfile.NamedTemporaryFile(
        "w", suffix=".json", prefix="caddy-update-", delete=False
    ) as f:
        json.dump(args, f)
        args_path = f.name

    try:
        expr = (
            f"({update_expr('probe')} "
            f"(builtins.fromJSON (builtins.readFile {json.dumps(args_path)}))).{attr}"
        )
        result = subprocess.run(
            ["nix", "build", "--impure", "--no-link", "--expr", expr],
            capture_output=True,
            text=True,
        )
    finally:
        os.unlink(args_path)

    if result.returncode == 0:
        raise RuntimeError(f"probe {attr}: expected a hash mismatch but the build succeeded")

    matches = GOT_RE.findall(result.stdout + result.stderr)
    if not matches:
        raise RuntimeError(
            f"probe {attr}: could not find a hash in nix output:\n{result.stderr}"
        )
    return matches[-1]


def write_json(path: Path, data: dict) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    tmp.replace(path)


def main() -> None:
    actual = latest_version()
    recorded = json.loads(VERSION_JSON.read_text())
    prev_fixture = json.loads(TEST_CADDIES_JSON.read_text())["previous"]
    note(f"nixpkgs has caddy {actual}, version.json has caddy {recorded['version']}")

    if actual == recorded["version"]:
        mode = "refresh"
        prev_version = prev_fixture["version"]
        # srcHash cannot change without the version changing, so reuse it.
        known_prev_src = prev_fixture["srcHash"]
        note("mode: refresh")
    else:
        mode = "bump"
        prev_version = recorded["version"]
        known_prev_src = None
        note(f"mode: bump ({prev_version} -> {actual})")

    def args(**extra) -> dict:
        return {"prevVersion": prev_version, **extra}

    with ThreadPoolExecutor(max_workers=6) as pool:
        note(f"probing latest {actual} caddyVendorProxyHash")
        f_latest_caddy = pool.submit(probe, "latest.caddyProxy", args())

        if mode == "bump":
            note(f"probing demoted {prev_version} srcHash")
            prev_src = pool.submit(probe, "previous.src", args()).result()
        else:
            prev_src = known_prev_src

        note(f"probing previous {prev_version} vendorHash")
        f_prev_vendor = pool.submit(probe, "previous.goModules", args(prevSrcHash=prev_src))
        note(f"probing previous {prev_version} caddyVendorProxyHash")
        f_prev_caddy = pool.submit(probe, "previous.caddyProxy", args(prevSrcHash=prev_src))

        def latest_plugin() -> str:
            h = f_latest_caddy.result()
            note(f"probing latest {actual} pluginSampleHash")
            return probe("latest.pluginProxy", args(latestCaddyVendorProxyHash=h))

        def prev_plugin() -> str:
            h = f_prev_caddy.result()
            note(f"probing previous {prev_version} pluginSampleHash")
            return probe(
                "previous.pluginProxy",
                args(prevSrcHash=prev_src, prevCaddyVendorProxyHash=h),
            )

        f_latest_plugin = pool.submit(latest_plugin)
        f_prev_plugin = pool.submit(prev_plugin)

        latest_caddy_hash = f_latest_caddy.result()
        latest_plugin_hash = f_latest_plugin.result()
        prev_vendor_hash = f_prev_vendor.result()
        prev_caddy_hash = f_prev_caddy.result()
        prev_plugin_hash = f_prev_plugin.result()

    write_json(
        VERSION_JSON,
        {"version": actual, "caddyVendorProxyHash": latest_caddy_hash},
    )
    write_json(
        TEST_CADDIES_JSON,
        {
            "latest": {"pluginSampleHash": latest_plugin_hash},
            "previous": {
                "version": prev_version,
                "srcHash": prev_src,
                "vendorHash": prev_vendor_hash,
                "caddyVendorProxyHash": prev_caddy_hash,
                "pluginSampleHash": prev_plugin_hash,
            },
        },
    )

    emit("mode", mode)
    emit("version", actual)
    emit("previous", prev_version)

    if latest_plugin_hash != prev_plugin_hash:
        note("NOTE: the sample plugin hash changed in this bump.")
        note(f"Prev: {prev_version} ({prev_plugin_hash})")
        note(f"New : {actual} ({latest_plugin_hash})")
        emit("plugin_hash_shift", "true")
    else:
        emit("plugin_hash_shift", "false")

    note("Update completed.")


if __name__ == "__main__":
    main()
