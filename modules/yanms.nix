# services.yanms: Minecraft servers on an overlay of the read-only server package.
#
# Per instance `<name>` (unit and user `mc-<name>`):
#   mc-<name>-layers.service  root oneshot: copies the package (once per store path), rebuilds the
#                             `custom` layer, drops forced paths from the state, mounts the overlay
#                             state (upper) : custom : package copy  on `server/`
#   mc-<name>.socket          the console, a FIFO at /run/yanms/<name>.stdin
#   mc-<name>.service         the server, stdin from the FIFO, stopped with `stop`
#   mc-<name>-cmd             sends a console command, optionally waits for its log line
#   restic-backups-mc-<name>  with save-off / save-all flush / save-on around the backup
#
# The console design follows Infinidoge/nix-minecraft's systemd-socket mode (MIT).
{
  pkgs,
  lib,
  config,
  options,
  ...
}: let
  cfg = config.services.yanms;
  inherit (lib) mkOption types;

  mkInstanceName = name: "mc-${name}";
  group = "minecraft-servers";
  fifoOf = name: "/run/yanms/${name}.stdin";

  # server.properties
  encodeValue = value:
    if builtins.isBool value
    then lib.boolToString value
    else if builtins.isString value
    then lib.escape [":" "=" "'"] value
    else toString value;
  dotNames = ["query-port" "rcon-password" "rcon-port"];
  propertyName = name:
    if lib.elem name dotNames
    then lib.replaceStrings ["-"] ["."] name
    else name;
  serverPropertiesFile = name: props: let
    all = lib.filterAttrs (_: v: v != null) ((removeAttrs props ["extra-options"]) // props.extra-options);
  in
    pkgs.writeText "${name}-server.properties" (
      lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "${propertyName n}=${encodeValue v}") all) + "\n"
    );

  eulaFile = pkgs.writeText "eula.txt" ''
    # eula.txt managed by services.yanms
    eula=true
  '';

  # Replaces @NAME@ with $NAME from the environment, in place (from nix-minecraft's `files`).
  substituteEnv = pkgs.writeShellScript "yanms-substitute-env" ''
    ${pkgs.gawk}/bin/awk '{
      out = ""
      while (match($0, /@[A-Za-z_][A-Za-z0-9_]*@/)) {
        name = substr($0, RSTART + 1, RLENGTH - 2)
        out = out substr($0, 1, RSTART - 1) ((name in ENVIRON) ? ENVIRON[name] : substr($0, RSTART, RLENGTH))
        $0 = substr($0, RSTART + RLENGTH)
      }
      print out $0
    }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  '';

  mkCmd = name: let
    unit = "${mkInstanceName name}.service";
    fifo = fifoOf name;
  in
    pkgs.writeShellApplication {
      name = "${mkInstanceName name}-cmd";
      runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.systemd];
      text = ''
        usage() {
          echo "usage: ${mkInstanceName name}-cmd [--wait REGEX] [--timeout SECONDS] COMMAND..." >&2
          echo "Sends COMMAND to the server console; --wait waits for a matching log line (needs journal access)." >&2
          exit 2
        }

        wait_for=""
        timeout=60
        while [ $# -gt 0 ]; do
          case "$1" in
            --wait) wait_for="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            -h|--help) usage ;;
            --) shift; break ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] || usage

        if [ ! -p ${fifo} ]; then
          echo "${unit} is not running" >&2
          exit 1
        fi

        if [ -n "$wait_for" ]; then
          cursor=$(journalctl -q -u ${unit} -n 1 --show-cursor -o cat | sed -n 's/^-- cursor: //p')
        fi

        printf '%s\n' "$*" > ${fifo}

        if [ -n "$wait_for" ]; then
          deadline=$(( $(date +%s) + timeout ))
          until journalctl -q -u ${unit} ''${cursor:+--after-cursor "$cursor"} -o cat | grep -qE -- "$wait_for"; do
            if [ "$(date +%s)" -ge "$deadline" ]; then
              echo "no log line matching '$wait_for' within ''${timeout}s" >&2
              exit 1
            fi
            sleep 1
          done
        fi
      '';
    };

  mkInstance = name: icfg: let
    user = mkInstanceName name;
    unit = mkInstanceName name;
    p = icfg.dirnames;
    fifo = fifoOf name;
    cmd = "${mkCmd name}/bin/${user}-cmd";
    pack = "${p.packs}/${builtins.baseNameOf icfg.serverPackage}";

    entries = lib.attrValues (lib.filterAttrs (_: v: v.enable) icfg.customization.create);
    generated = [
      {
        target = "server.properties";
        source = serverPropertiesFile user icfg.serverProperties;
        mode = "copy";
        force = true;
        substitute = true;
      }
      {
        target = "eula.txt";
        source = eulaFile;
        mode = "copy";
        force = true;
        substitute = false;
      }
    ];
    allEntries = map (e: e // {substitute = e.text != null;}) entries ++ generated;
    resetPaths =
      icfg.customization.resetPaths
      ++ icfg.customization.remove
      ++ map (e: e.target) (lib.filter (e: e.force) allEntries);

    q = lib.escapeShellArg;

    placeEntry = e: let
      to = q "${p.custom}/${e.target}";
      from = q "${e.source}";
    in
      ''
        mkdir -p "$(dirname ${to})"
      ''
      + (
        if e.mode == "copy"
        then ''
          cp -r --no-preserve=mode,ownership ${from} ${to}
          ${lib.optionalString e.substitute "${substituteEnv} ${to}"}
        ''
        else ''
          if [ -d ${from} ]; then
            mkdir -p ${to}
            ${pkgs.outils}/bin/lndir -silent ${from} ${to}
          else
            ln -s ${from} ${to}
          fi
        ''
      );

    layers = pkgs.writeShellScript "${user}-layers" ''
      set -euo pipefail
      PATH=${lib.makeBinPath [pkgs.coreutils pkgs.findutils pkgs.util-linux]}

      if mountpoint -q ${q p.server}; then
        umount ${q p.server}
      fi

      # Old layout (bindfs over overlays/overlay), from before the custom layer.
      if [ -d ${q "${p.base}/overlays"} ] && ! findmnt -rno TARGET | grep -q '^${p.base}/\(overlays\|workdir\)'; then
        rm -rf ${q "${p.base}/overlays"}
        rmdir ${q "${p.base}/workdir"} 2>/dev/null || true
      fi

      # A restored or moved state keeps the old host's owner: give it to this instance's user.
      if [ "$(stat -c %U ${q p.state})" != ${user} ]; then
        chown -R ${user}:${group} ${q p.state}
      fi

      # The package, copied once per store path: the store's files are root-owned and read-only,
      # and the server rewrites some of them (configs), which needs a writable lower file.
      if [ ! -e ${q "${pack}.complete"} ]; then
        rm -rf ${q pack}
        cp -a ${q icfg.serverPackage} ${q pack}
        chown -R ${user}:${group} ${q pack}
        chmod -R u+w ${q pack}
        touch ${q "${pack}.complete"}
      fi
      find ${q p.packs} -mindepth 1 -maxdepth 1 ! -name ${q (builtins.baseNameOf pack)} ! -name ${q "${builtins.baseNameOf pack}.complete"} -exec rm -rf {} +

      # The custom layer.
      rm -rf ${q p.custom}
      mkdir -p ${q p.custom}
      ${lib.concatMapStrings placeEntry allEntries}
      ${lib.concatMapStrings (path: ''
          rm -rf ${q "${p.custom}/${path}"}
          mkdir -p "$(dirname ${q "${p.custom}/${path}"})"
          mknod ${q "${p.custom}/${path}"} c 0 0
        '')
        icfg.customization.remove}
      chown -R -h ${user}:${group} ${q p.custom}

      # The server's versions of forced and reset paths.
      ${lib.concatMapStrings (path: ''
          rm -rf ${q "${p.state}/${path}"}
        '')
        resetPaths}

      mount -t overlay overlay \
        -o ${q "lowerdir=${p.custom}:${pack},upperdir=${p.state},workdir=${p.work}"} \
        ${q p.server}
    '';

    stop = pkgs.writeShellScript "${user}-stop" ''
      if [ -p ${fifo} ]; then
        echo stop > ${fifo}
        while kill -0 "$1" 2>/dev/null; do
          sleep 0.5
        done
      fi
    '';

    backupPrepare = pkgs.writeShellScript "${user}-backup-prepare" ''
      if [ -p ${fifo} ]; then
        ${cmd} save-off
        ${cmd} --wait 'Saved the game' --timeout 300 save-all flush
      fi
    '';

    backupCleanup = pkgs.writeShellScript "${user}-backup-cleanup" ''
      if [ -p ${fifo} ]; then
        ${cmd} save-on
      fi
    '';

    backupName = "restic-backups-${user}";
  in {
    packages = [(mkCmd name)];

    users.${user} = {
      isSystemUser = true;
      inherit group;
      home = p.base;
      createHome = true;
      homeMode = "750";
      extraGroups = icfg.user.extraGroups ++ cfg.users.extraGroups;
    };

    tmpfiles = [
      "d '${p.state}' 0750 ${user} ${group} - -"
      "d '${p.work}' 0700 root root - -"
      "d '${p.packs}' 0750 ${user} ${group} - -"
      "d '${p.server}' 0750 ${user} ${group} - -"
    ];

    services."${unit}-layers" = {
      description = "Minecraft server ${name}: layers";
      after = ["systemd-tmpfiles-setup.service" "local-fs.target"];
      unitConfig.RequiresMountsFor = [p.base];
      serviceConfig =
        {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = layers;
          ExecStop = "${pkgs.util-linux}/bin/umount ${q p.server}";
        }
        // lib.optionalAttrs (icfg.environmentFile != null) {
          EnvironmentFile = icfg.environmentFile;
        };
    };

    sockets.${unit} = {
      description = "Minecraft server ${name}: console";
      bindsTo = ["${unit}.service"];
      socketConfig = {
        ListenFIFO = fifo;
        SocketUser = user;
        SocketGroup = group;
        SocketMode = "0660";
        RemoveOnStop = true;
        FlushPending = true;
      };
    };

    services.${unit} = {
      description = "Minecraft server ${name}";
      wantedBy = ["multi-user.target"];
      requires = ["${unit}-layers.service" "${unit}.socket"];
      after = ["network.target" "${unit}-layers.service" "${unit}.socket"];
      partOf = ["${unit}-layers.service"];

      path = [icfg.jvmPackage pkgs.bash];

      environment = {
        JVM_ARGS = icfg.jvmOptString;
        SERVER_ARGS = icfg.serverOpts;
      };

      serviceConfig =
        {
          Type = "simple";
          ExecStart = "${p.server}/start.sh";
          ExecStop = "${stop} $MAINPID";
          TimeoutStopSec = "2min";
          Restart = "always";
          User = user;
          Group = group;
          WorkingDirectory = p.server;
          StandardInput = "socket";
          StandardOutput = "journal";
          StandardError = "journal";

          # Hardening, the list from nix-minecraft plus a read-only system.
          ProtectSystem = "strict";
          ReadWritePaths = [p.base];
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = [""];
          DeviceAllow = [""];
          LockPersonality = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          UMask = "0027";
        }
        // lib.optionalAttrs (icfg.memoryMax != null) {
          MemoryMax = icfg.memoryMax;
        }
        // lib.optionalAttrs (icfg.environmentFile != null) {
          EnvironmentFile = icfg.environmentFile;
        };
    };

    backups = lib.optionalAttrs icfg.backup.restic.enable {
      ${user} = removeAttrs icfg.backup.restic ["enable" "_module"] // {inherit user;};
    };

    # As root: --wait reads the server's journal.
    backupServices = lib.optionalAttrs icfg.backup.restic.enable {
      ${backupName}.serviceConfig = {
        ExecStartPre = lib.mkBefore ["+${backupPrepare}"];
        ExecStopPost = ["+${backupCleanup}"];
      };
    };
  };

  enabledInstances = lib.filterAttrs (_: x: x.enable) cfg.instances;
  ports = lib.concatLists (lib.mapAttrsToList (_: v: let
    sp = v.serverProperties;
  in
    [sp.server-port]
    ++ lib.optional sp.enable-rcon sp.rcon-port
    ++ lib.optional sp.enable-query sp.query-port)
  enabledInstances);
in {
  options.services.yanms = {
    eula = mkOption {
      type = types.bool;
      default = false;
      description = "Whether you accept the Minecraft EULA (https://aka.ms/MinecraftEULA).";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/minecraft-servers";
      example = "/srv/minecraft-servers";
      description = "Folder with one folder per instance (state, pack copy, overlay).";
    };

    users.extraGroups = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra groups for every instance user (for example one that can read backup secrets).";
    };

    backup.restic = {
      repositoryPrefix = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "rclone:mega:/mc-backups";
        description = "Default `repository` of an instance: `<prefix>/<instance name>`.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default `passwordFile` of an instance.";
      };

      environmentFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default `environmentFile` of an instance.";
      };

      initialize = mkOption {
        type = types.bool;
        default = false;
        description = "Default `initialize` of an instance.";
      };

      pruneOpts = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["--keep-daily 3" "--keep-weekly 1"];
        description = "Default `pruneOpts` of an instance.";
      };

      timerConfig = mkOption {
        type = types.nullOr (types.attrsOf types.unspecified);
        default = null;
        description = "Default `timerConfig` of an instance; null keeps restic's default (daily).";
      };
    };

    instances = mkOption {
      type = types.attrsOf (types.submodule (import ./_instance.nix {
        inherit pkgs;
        globalOptions = options;
        globalConfig = config;
      }));
      default = {};
      description = "Minecraft server instances.";
    };
  };

  # Static top-level keys: the per-instance parts are merged below each of them, never above
  # `services.yanms`, which they are computed from.
  config = let
    instances = lib.mapAttrsToList mkInstance enabledInstances;
    merge = f: lib.mkMerge (map f instances);
  in
    lib.mkIf (enabledInstances != {}) {
      assertions = [
        {
          assertion = cfg.eula;
          message = "services.yanms: you must accept the Minecraft EULA (services.yanms.eula) to run any server.";
        }
        {
          assertion = lib.unique ports == ports;
          message = "services.yanms: the server, RCON and query ports of the instances overlap: ${toString ports}.";
        }
      ];

      users.groups.${group} = {};

      networking.firewall = {
        allowedTCPPorts = lib.concatLists (lib.mapAttrsToList (_: v:
          [v.serverProperties.server-port]
          ++ lib.optional (v.serverProperties.enable-rcon && v.openRcon) v.serverProperties.rcon-port)
        enabledInstances);
        allowedUDPPorts = lib.concatLists (lib.mapAttrsToList (_: v:
          lib.optional v.serverProperties.enable-query v.serverProperties.query-port)
        enabledInstances);
      };

      environment.systemPackages = lib.concatMap (i: i.packages) instances;
      users.users = merge (i: i.users);
      systemd.tmpfiles.rules = lib.concatMap (i: i.tmpfiles) instances;
      systemd.services = merge (i: i.services // i.backupServices);
      systemd.sockets = merge (i: i.sockets);
      services.restic.backups = merge (i: i.backups);
    };
}
