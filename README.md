# yanms.nix

Yet another NixOS Minecraft server module: modpack servers (Forge, from CurseForge server zips) run on an overlay of the read-only pack, with a console FIFO for commands and restic backups that pause saving around the snapshot.

## Use it

```nix
{
  inputs.yanms = {
    url = "github:truelecter/yanms.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # In a NixOS configuration: the module plus the overlay.
  # imports = [inputs.yanms.nixosModules.default];
}
```

```nix
{config, inputs, pkgs, ...}: {
  services.yanms = {
    eula = true;

    backup.restic = {
      repositoryPrefix = "rclone:mega:/mc-backups"; # repository <prefix>/<instance>
      passwordFile = config.sops.secrets.restic-password.path;
      initialize = true;
      pruneOpts = ["--keep-daily 3" "--keep-weekly 1"];
    };

    instances.e9e = {
      enable = true;
      serverPackage = pkgs.mcs-enigmatica-9-expert;
      jvmPackage = pkgs.temurin-bin-17;
      jvmMaxAllocation = "8G";
      jvmOpts = inputs.yanms.lib.jvmFlags.zgc;

      serverProperties = {
        server-port = 25568;
        difficulty = 3;
      };

      bluemap = {
        enable = true;
        package = pkgs.minecraftMods.forge."1.19.1".bluemap;
        port = 8112;
      };

      backup.restic.enable = true;
    };
  };
}
```

`nixosModules.default` imports the module and applies `overlays.default`; `nixosModules.yanms` is the module alone.

## How an instance runs

Each instance `<name>` gets the user `mc-<name>` and the folder `<dataDir>/<name>` (`services.yanms.dataDir`, default `/var/lib/minecraft-servers`). A state restored from another host is given to `mc-<name>` at start.

| Path      | What it is                                                                                     |
| --------- | ---------------------------------------------------------------------------------------------- |
| `state/`  | The overlay's upper layer: the world and everything else the server writes. This is backed up. |
| `custom/` | Middle layer, rebuilt at every start: `customization`, `server.properties`, `eula.txt`         |
| `packs/`  | The writable part of `serverPackage`: its folders and every file but the jars, owned by `mc-<name>`, made once per store path |
| `server/` | The merged overlay, the server's working directory                                             |

The pack stays a fixed-output derivation in the store, so changing a customization never rebuilds or re-uploads it, and the store copy is the overlay's lowest layer. The store's files are root-owned and read-only, and servers rewrite some of them (configs), so everything but the jars is copied to `packs/` once per version; the jars, most of a pack's size, stay in the store.

Units:

- `mc-<name>-layers.service` (root) copies the pack, rebuilds `custom/`, drops forced paths from `state/`, and mounts the overlay. Restarting it restarts the server.
- `mc-<name>.socket` is the console, a FIFO at `/run/yanms/<name>.stdin`. `mc-<name>.service` reads it as stdin; stopping sends `stop` and waits for the server to exit.
- `mc-<name>-cmd [--wait REGEX] [--timeout SECONDS] COMMAND...` sends a console command. `--wait` waits for a matching line in the server's journal, so it needs root or the `systemd-journal` group.
- `restic-backups-mc-<name>` runs `save-off` and `save-all flush` (waiting for "Saved the game") before the snapshot and `save-on` after it.

`customization.create` entries are copies (for `text`, writable, `@NAME@` replaced from the instance's `environmentFile`) or symlinks into the store (for jars). With `force` (the default) the server's own version is dropped from the state at every start, so the declared file wins. `customization.remove` hides package files, and `customization.resetPaths` drops paths from the state at start, for example `config` after a pack update.

RCON is off by default. If you turn it on, set `rcon-password = "@RCON_PASSWORD@"` and put the password in the `environmentFile`, so it stays out of the store.

## Packages

| Package                         | Pack                                                    |
| ------------------------------- | ------------------------------------------------------- |
| `mcs-create-arcane-engineering` | Create: Arcane Engineering 0.1.9.3 (Forge 1.18.2)       |
| `mcs-dawncraft`                 | DawnCraft 1.28_f2 (Forge 1.18.2)                        |
| `mcs-enigmatica-6-expert`       | Enigmatica 6 Expert 1.8.0 (Forge 1.16.5, ServerStarter) |
| `mcs-enigmatica-9-expert`       | Enigmatica 9 Expert 1.25.0 (Forge 1.19.2, ServerStarter) |
| `mcs-life-in-the-village-3`     | Life in the Village 3 2.8 (Forge 1.19.2, prebuilt)      |
| `mcs-sevtech-ages`              | SevTech: Ages 3.2.3 (Forge 1.12.2)                      |
| `mcs-vault-hunters-3`           | Vault Hunters 3rd Edition 3.18.3.1 (Forge 1.18.2)       |

The overlay also adds `mkForgeServer`, which builds a pack from its server zip with the Forge installer, ServerStarter, or as a prebuilt server (see `packages/_lib/mk-forge-server.nix`), and `minecraftMods.<loader>.<mc-version>.<name>`, single mod jars such as `minecraftMods.forge."1.19.1".bluemap`.

`lib.jvmFlags` has JVM flag presets: `tuning`, `zgc` (Java 17), `zgcGenerational` (Java 21).

## Credits

The console FIFO, the stop sequence, the hardening list and the `@NAME@` substitution follow [Infinidoge/nix-minecraft](https://github.com/Infinidoge/nix-minecraft) (MIT).

## License

MIT, see `COPYING`.
