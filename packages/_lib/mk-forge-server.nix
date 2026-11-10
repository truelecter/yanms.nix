# Builds a Forge modpack server from its server zip.
#
# installer:
#   "forge"         run the Forge installer (`forgeInstaller`) over the unpacked zip
#   "serverstarter" run EnigmaticaModpacks' ServerStarter, which downloads the pack's mods itself
#   "prebuilt"      the zip already holds an installed server in one folder (`prebuiltDir`)
#
# "forge" and "serverstarter" download during the build, so they are fixed-output derivations:
# set `outputHash` (build once with `lib.fakeHash` to get it). The output also holds `start.sh`
# ("unix-args" for Forge 1.17 and later, "forge-jar" before); it is part of every pack's hash, so
# changing either script means new hashes for all packs.
{
  lib,
  stdenvNoCC,
  unzip,
  strip-nondeterminism,
  sources,
}: {
  pname,
  version,
  src,
  jdk,
  installer,
  startScript,
  forgeInstaller ? null,
  serverStarter ? sources.server-starter.src,
  # Unzip without the archive's folders (`unzip -j`).
  flatten ? false,
  # Folder in the zip that holds the server, for "prebuilt".
  prebuiltDir ? null,
  # Files the installer leaves behind, removed from the output.
  cleanup ? [],
  # Make Forge's remapped server jar reproducible (1.17 and later).
  stripSrg ? true,
  outputHash ? null,
  meta ? {},
}:
assert lib.assertOneOf "installer" installer ["forge" "serverstarter" "prebuilt"];
assert lib.assertOneOf "startScript" startScript ["unix-args" "forge-jar"];
assert installer == "forge" -> forgeInstaller != null;
assert installer == "prebuilt" -> prebuiltDir != null;
assert installer != "prebuilt" -> outputHash != null; let
  start =
    {
      unix-args = ./../_files/start-forge-1.18.sh;
      forge-jar = ./../_files/start-forge-before-1.18.sh;
    }
    .${
      startScript
    };

  install =
    {
      forge = "java -jar ${forgeInstaller} --installServer $out";
      serverstarter = "java -jar ${serverStarter} install";
    }
    .${
      installer
    } or null;
in
  stdenvNoCC.mkDerivation ({
      inherit pname version src meta;

      nativeBuildInputs = [jdk unzip strip-nondeterminism];

      dontConfigure = true;
      dontBuild = true;
    }
    // (
      if installer == "prebuilt"
      then {
        dontPatch = true;

        installPhase = ''
          cd ..
          mv ${prebuiltDir} $out
          cp ${start} $out/start.sh
          chmod +x $out/start.sh
        '';
      }
      else {
        unpackPhase = ''
          mkdir -p $out
          unzip ${lib.optionalString flatten "-j "}$src -d $out
        '';

        installPhase = ''
          cd $out

          cp ${start} start.sh
          chmod +x start.sh

          ${install}
        '';

        fixupPhase = ''
          rm ${lib.concatStringsSep " " cleanup}
          ${lib.optionalString stripSrg "strip-nondeterminism libraries/net/minecraft/server/*/server*-srg.jar"}
        '';

        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        inherit outputHash;
      }
    ))
