{
  mkForgeServer,
  sources,
  jdk17,
}:
mkForgeServer {
  pname = "dawncraft";
  inherit (sources.mcs-dawncraft) version src;

  jdk = jdk17;
  installer = "forge";
  forgeInstaller = sources.forge-server-40-2-9.src;
  cleanup = ["*.log" "run.bat"];
  outputHash = "sha256-/exhV+tCFTfZGkwY0Pia1B6m7SdV+MKVGOrAQ6cazuA=";

  meta = {
    description = "DawnCraft - An Adventure RPG Modpack";
    homepage = "https://www.curseforge.com/minecraft/modpacks/dawn-craft";
  };
}
