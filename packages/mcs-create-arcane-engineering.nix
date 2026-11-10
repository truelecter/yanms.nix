{
  mkForgeServer,
  sources,
  jdk17,
}:
mkForgeServer {
  pname = "create-arcane-engineering";
  inherit (sources.mcs-create-arcane-engineering) version src;

  jdk = jdk17;
  installer = "forge";
  startScript = "unix-args";
  forgeInstaller = sources.forge-server-40-2-9.src;
  cleanup = ["*.log" "run.bat"];
  outputHash = "sha256-w0PWwoY/f9ujlWP5Vyc0iG9TmmYQEztbEc3GHwK7UA0=";

  meta = {
    description = "Embark on an enchanting journey with Create Arcane Engineering, a meticulously crafted collection of both popular and custom mods";
    homepage = "https://www.curseforge.com/minecraft/modpacks/create-arcane-engineering";
  };
}
