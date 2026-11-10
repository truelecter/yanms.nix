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
  startScript = "unix-args";
  forgeInstaller = sources.forge-server-40-2-9.src;
  cleanup = ["*.log" "run.bat"];
  outputHash = "sha256-daLgV+ck7+/m4igNakC8Dfycbq5e0RmxvJHeqg6dZ3w=";

  meta = {
    description = "DawnCraft - An Adventure RPG Modpack";
    homepage = "https://www.curseforge.com/minecraft/modpacks/dawn-craft";
  };
}
