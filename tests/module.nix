# Runs the module with a fake server that answers console commands the way Minecraft does:
# the overlay layers, customization, the console FIFO, the restic backup hooks, a graceful stop.
{
  pkgs,
  module,
}: let
  base = "/srv/minecraft-servers/fake";
  server = "${base}/server";

  fakeServer = pkgs.runCommand "fake-minecraft-server" {} ''
    mkdir -p $out/config $out/mods
    echo original > $out/config/pack.conf
    echo jar > $out/mods/remove-me.jar
    echo kept > $out/mods/kept.jar
    cat > $out/start.sh <<'EOF'
    #!/bin/sh
    echo "fake server starting: $JVM_ARGS $SERVER_ARGS"
    mkdir -p world
    echo changed-by-server >> config/pack.conf
    echo 'Done (1.0s)! For help, type "help"'
    while read -r line; do
      case "$line" in
        "save-all flush") date > world/level.dat; echo "Saved the game" ;;
        save-off) echo "Automatic saving is now disabled" ;;
        save-on) echo "Automatic saving is now enabled" ;;
        stop) echo "Stopping the server"; exit 0 ;;
        *) echo "Unknown command: $line" ;;
      esac
    done
    EOF
    chmod +x $out/start.sh
  '';
in
  pkgs.testers.runNixOSTest {
    name = "yanms";

    nodes.machine = {pkgs, ...}: {
      imports = [module];

      environment.systemPackages = [pkgs.restic];
      # The local restic repository, written by the instance user.
      systemd.tmpfiles.rules = ["d /var/backup 0750 mc-fake minecraft-servers - -"];

      services.yanms = {
        eula = true;
        dataDir = "/srv/minecraft-servers";
        backup.restic = {
          repositoryPrefix = "/var/backup";
          passwordFile = "${pkgs.writeText "restic-password" "password"}";
          initialize = true;
        };

        instances.fake = {
          enable = true;
          serverPackage = fakeServer;
          jvmPackage = pkgs.coreutils;
          jvmMaxAllocation = "512M";
          environmentFile = pkgs.writeText "fake-env" "SECRET=secret-value";

          serverProperties = {
            server-port = 25565;
            motd = "fake @SECRET@";
          };

          customization = {
            create = {
              "config/declared.conf".text = "declared @SECRET@";
              "mods/linked.jar".source = pkgs.writeText "linked.jar" "jar";
            };
            remove = ["mods/remove-me.jar"];
          };

          backup.restic.enable = true;
        };
      };
    };

    testScript = ''
      machine.wait_for_unit("mc-fake.service")
      machine.wait_until_succeeds("journalctl -u mc-fake.service | grep -F 'Done (1.0s)'")

      with subtest("layers"):
          machine.succeed("findmnt -t overlay ${server}")
          machine.succeed("grep -Fx 'declared secret-value' ${server}/config/declared.conf")
          machine.succeed("grep -F 'motd=fake secret-value' ${server}/server.properties")
          machine.succeed("grep -Fx 'enable-rcon=false' ${server}/server.properties")
          machine.fail("grep -F rcon.password ${server}/server.properties")
          machine.succeed("test -L ${server}/mods/linked.jar")
          machine.fail("test -e ${server}/mods/remove-me.jar")
          # The server rewrote a file of the package: copied up into the state.
          machine.succeed("grep -F changed-by-server ${base}/state/config/pack.conf")
          machine.succeed("grep -Fx original ${base}/packs/*-fake-minecraft-server/config/pack.conf")
          # Jars come from the store, the rest of the package is copied.
          machine.succeed("grep -Fx kept ${server}/mods/kept.jar")
          machine.fail("test -e ${base}/packs/*-fake-minecraft-server/mods/kept.jar")
          machine.succeed("test -d ${base}/packs/*-fake-minecraft-server/mods")
          machine.succeed("test -x ${base}/packs/*-fake-minecraft-server/start.sh")
          machine.succeed("stat -c %U ${base}/state/config/pack.conf | grep -Fx mc-fake")

      with subtest("hardening"):
          machine.succeed("systemctl show mc-fake.service -p MemoryMax | grep -Fx MemoryMax=1610612736")
          machine.succeed("systemctl show mc-fake.service -p ProtectSystem | grep -Fx ProtectSystem=strict")

      with subtest("console"):
          machine.succeed("mc-fake-cmd --wait 'Unknown command: hello there' hello there")
          machine.fail("mc-fake-cmd --wait 'never printed' --timeout 3 hello")

      with subtest("backup"):
          machine.succeed("systemctl start restic-backups-mc-fake.service")
          server_log = machine.succeed("journalctl -u mc-fake.service -o cat")
          assert "Automatic saving is now disabled" in server_log
          assert "Saved the game" in server_log
          assert "Automatic saving is now enabled" in server_log
          machine.succeed("restic -r /var/backup/fake --password-file ${pkgs.writeText "restic-password" "password"} ls latest | grep -F world/level.dat")

      with subtest("forced files come back, state stays, state owner is fixed"):
          machine.succeed("echo edited > ${server}/config/declared.conf")
          # As after a restore from another host.
          machine.succeed("chown -R root:root ${base}/state/world")
          machine.succeed("chmod a-w ${base}/state/config/pack.conf")
          machine.succeed("systemctl restart mc-fake-layers.service")
          machine.wait_for_unit("mc-fake.service")
          machine.wait_until_succeeds("journalctl -u mc-fake.service | grep -c -F 'Done (1.0s)' | grep -Fx 2")
          machine.succeed("grep -Fx 'declared secret-value' ${server}/config/declared.conf")
          machine.succeed("test -e ${server}/world/level.dat")
          machine.succeed("stat -c %U ${base}/state/world/level.dat | grep -Fx mc-fake")
          machine.succeed("stat -c %A ${base}/state/config/pack.conf | grep -F -- -rw-")

      with subtest("graceful stop"):
          machine.succeed("systemctl stop mc-fake.service")
          machine.succeed("journalctl -u mc-fake.service | grep -F 'Stopping the server'")
          machine.fail("test -p /run/yanms/fake.stdin")
          machine.succeed("systemctl show mc-fake.service -p Result | grep -Fx Result=success")
    '';
  }
