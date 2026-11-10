{
  pkgs,
  globalOptions,
  globalConfig,
}: {
  name,
  lib,
  config,
  ...
}: let
  inherit (lib) types mkOption mkEnableOption;

  # "8G", "8192M", "512m" -> MiB; null for anything else.
  toMiB = size: let
    m = builtins.match "([0-9]+)([KkMmGgTt]?)" size;
    n = lib.toInt (builtins.elemAt m 0);
    unit = lib.toUpper (builtins.elemAt m 1);
  in
    if m == null
    then null
    else
      {
        "" = n / 1048576;
        K = n / 1024;
        M = n;
        G = n * 1024;
        T = n * 1048576;
      }
      .${
        unit
      };

  xmxMiB = toMiB config.jvmMaxAllocation;
in {
  options = {
    enable = mkEnableOption "the Minecraft server instance ${name}";

    serverPackage = mkOption {
      type = types.package;
      description = ''
        The installed server (for example a `mkForgeServer` pack). It is copied to the instance's
        folder once per store path, owned by the instance user, and used as the overlay's lowest
        layer; `start.sh` in it starts the server.
      '';
    };

    jvmPackage = mkOption {
      type = types.package;
      default = pkgs.jre8;
      defaultText = lib.literalExpression "pkgs.jre8";
      description = ''
        JVM that runs the server. Modded servers need `awt`, so not a `_headless` JRE.
      '';
    };

    jvmMaxAllocation = mkOption {
      type = types.str;
      default = "256M";
      description = "Maximum heap, `-Xmx`. You want to change this.";
    };

    jvmInitialAllocation = mkOption {
      type = types.str;
      default = "";
      description = "Initial heap, `-Xms`. Not set when empty.";
    };

    jvmOpts = mkOption {
      type = types.coercedTo (types.listOf types.str) (lib.concatStringsSep " ") types.str;
      default = "-XX:+UseG1GC -Dsun.rmi.dgc.server.gcInterval=2147483646 -XX:+UnlockExperimentalVMOptions -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M";
      example = lib.literalExpression "inputs.yanms.lib.jvmFlags.zgc";
      description = ''
        JVM flags, a string or a list. Leave `-Xms` and `-Xmx` out: see `jvmMaxAllocation` and
        `jvmInitialAllocation`. The flake's `lib.jvmFlags` has presets.
      '';
    };

    serverOpts = mkOption {
      type = types.str;
      default = "nogui";
      description = "Arguments for the server itself.";
    };

    jvmOptString = mkOption {
      type = types.str;
      readOnly = true;
      default = lib.concatStringsSep " " (lib.filter (s: s != "") [
        (lib.optionalString (config.jvmMaxAllocation != "") "-Xmx${config.jvmMaxAllocation}")
        (lib.optionalString (config.jvmInitialAllocation != "") "-Xms${config.jvmInitialAllocation}")
        config.jvmOpts
      ]);
      description = "The JVM arguments the server starts with (`$JVM_ARGS` in `start.sh`).";
    };

    memoryMax = mkOption {
      type = types.nullOr types.str;
      default =
        if xmxMiB == null
        then null
        else "${toString (xmxMiB + lib.max 1024 (xmxMiB / 2))}M";
      defaultText = lib.literalExpression "-Xmx plus half of it, at least 1 GiB more";
      description = ''
        systemd `MemoryMax` of the server: the heap plus room for the JVM's own memory
        (metaspace, code cache, direct buffers). Null for no limit.
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      description = ''
        Environment file (`EnvironmentFile` in systemd.exec(5)) for the server. Its variables also
        replace `@NAME@` in `server.properties` and in `customization.create` copies, so a secret
        such as `rcon-password = "@RCON_PASSWORD@"` stays out of the Nix store.
      '';
    };

    openRcon = mkOption {
      type = types.bool;
      default = false;
      description = "Open the RCON port in the firewall (only with `serverProperties.enable-rcon`).";
    };

    dirnames = mkOption {
      type = types.attrs;
      readOnly = true;
      internal = true;
      default = rec {
        base = "/var/lib/minecraft-servers/${name}";
        # Overlay upper layer: everything the server writes. Backed up.
        state = "${base}/state";
        # Overlay work directory.
        work = "${base}/work";
        # Middle layer, rebuilt at every start: `customization` and the generated files.
        custom = "${base}/custom";
        # Copies of `serverPackage`, one per store path, owned by the instance user.
        packs = "${base}/packs";
        # The merged overlay, the server's working directory.
        server = "${base}/server";
      };
      description = "The instance's folders.";
    };

    serverProperties = mkOption {
      type = types.submodule ./_server-properties.nix;
      default = {};
      description = ''
        `server.properties`, generated at every start. Names with dots (`rcon.password`) use dashes
        (`rcon-password`). The whitelist, ops and bans stay stateful: manage them in game.
      '';
    };

    backup.restic = mkOption {
      type = types.submodule (import ./_backup-restic.nix {
        inherit globalOptions globalConfig;
        instanceName = name;
        instanceConfig = config;
      });
      default = {};
      description = "Restic backups of the state, with `save-off` and `save-all flush` around them.";
    };

    user.extraGroups = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra groups for the instance user.";
    };

    bluemap = {
      enable = mkEnableOption "BlueMap (its mod jar, `core.conf` and `webserver.conf`)";

      package = mkOption {
        type = types.path;
        description = "The BlueMap mod jar for the pack's loader and Minecraft version.";
      };

      port = mkOption {
        type = types.port;
        description = "Port of BlueMap's web server, on 127.0.0.1.";
      };

      renderThreadCount = mkOption {
        type = types.ints.positive;
        default = 1;
        description = "BlueMap `render-thread-count`.";
      };
    };

    customization = {
      remove = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["mods/functionalstorage-1.18.2-1.1.3.jar"];
        description = ''
          Paths of the server package to hide (whiteouts in the middle layer). Wins over `create`
          for the same path.
        '';
      };

      create = mkOption {
        type = types.attrsOf (
          types.submodule (import ./_customization-file.nix {
            inherit pkgs;
            instanceName = name;
          })
        );
        default = {};
        description = "Files and folders placed over the server package.";
      };

      resetPaths = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["config"];
        description = ''
          Paths dropped from the state at every start, so the package's version shows again (for
          example `config` after a pack update).
        '';
      };
    };
  };

  config.customization.create = lib.mkIf config.bluemap.enable {
    "mods/bluemap.jar".source = config.bluemap.package;
    "config/bluemap/core.conf".text = ''
      accept-download: true
      data: "bluemap"
      render-thread-count: ${toString config.bluemap.renderThreadCount}
      scan-for-mod-resources: true
      metrics: true
    '';
    "config/bluemap/webserver.conf".text = ''
      enabled: true
      port: ${toString config.bluemap.port}
      ip: "127.0.0.1"
    '';
  };
}
