# AGENTS.md

Minecraft modpack servers on NixOS: the `services.yanms` module, pack packages, and mod jars, consumed as a flake input (`overlays.default`, `nixosModules.default`).

## Layout

```text
flake.nix                    inputs, `packages`, `checks`, `overlays.default`, `nixosModules.{default,yanms}`, `lib.jvmFlags`
lib/import-packages.nix      callPackage for every `<name>.nix` in a folder (`_`-prefixed names skipped)
lib/jvm-flags.nix            JVM flag presets
packages/mcs-*.nix           one pack per file, built with `packages/_lib/mk-forge-server.nix`
packages/_files/             the packs' `start.sh` scripts
modules/yanms.nix            the module; `_`-prefixed files are its submodules
tests/module.nix             NixOS test with a fake server (`checks.<system>.module`)
sources/                     nvfetcher: `nvfetcher.toml` and the generated sources (packs, installers, mods)
.github/                     build on every push, weekly source and lock update, repo settings (`settings.yml`)
```

## Packs

- Packs that download while installing (`installer = "forge"` or `"serverstarter"`) are fixed-output derivations. Their output includes `start.sh` from `packages/_files/`, so changing either script changes every pack's hash. Keep the builder's commands stable too: the store path only depends on the name and `outputHash`, so a changed command breaks the next real rebuild, not the evaluation.
- A new pack or version: add the server zip to `sources/nvfetcher.toml` with `src.manual` and `fetch.url` (forgecdn), run `nix develop -c nvfetcher --keep-old -c sources/nvfetcher.toml -o sources`, add `packages/mcs-<name>.nix` with `outputHash = lib.fakeHash`, build it on Linux, and copy the hash from the error.
- Mod jars are nvfetcher entries with `passthru = { mod = "<loader>", mc-version = "...", name = "..." }`; they show up as `minecraftMods.<loader>.<mc-version>.<name>`.

## Module

- Overlay per instance: `state/` (upper) over `custom/` over `packs/<store name>` (the pack's folders and non-jar files, owned by the instance user) over the pack in the store. `mc-<name>-layers.service` (root) builds and mounts it; the server service is `PartOf` it, so restarting the layers restarts the server. A server can only rewrite a lower file it may write, so a file the server changes must not come from the store layer (root-owned, `0444`), and writes through a symlink into the store fail with EROFS. Only jars are left in the store layer.
- The console is a FIFO socket unit; the stop script and the backup hooks write to it. `mc-<name>-cmd --wait` reads the server's journal, so the backup hooks run as root (`+` in `ExecStartPre`/`ExecStopPost` of the restic unit).
- `config` keeps static top-level keys, with the per-instance parts merged below each of them (`systemd.services`, `users.users`, ...). A top-level `mkMerge` over instances recurses into `services.yanms` itself.
- `backup.restic` reuses nixpkgs' `services.restic.backups` options; options it can't take over (their defaults read the backup's own name) go in `managed` in `modules/_backup-restic.nix`.

## Test a change

- `nix build .#checks.aarch64-linux.module` (or `x86_64-linux`): boots a VM with a fake server and checks the layers, the console, a backup, a forced file after restart, and a graceful stop.
- A pack change: `nix build .#packages.aarch64-linux.<name>` (Linux).
- In a consumer, try a checkout before pushing: `--override-input yanms path:<this checkout>`.

## Commits

- Conventional Commits, scoped by area: `yanms` (the module), `packs`, `mods`, `ci`, `repo`, `deps`. For example `feat(yanms): ...`.
- Keep the commit body minimal: a few words at most, and none when the subject line already says it all.
