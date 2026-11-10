{
  mkForgeServer,
  sources,
  jdk8,
}:
mkForgeServer {
  pname = "sevtech-ages";
  inherit (sources.mcs-sevtech-ages) version src;

  jdk = jdk8;
  installer = "forge";
  startScript = "forge-jar";
  forgeInstaller = sources.forge-server-14-23-5-2860.src;
  stripSrg = false;
  cleanup = ["forge-*installer.jar" "*.log" "ServerStart.sh" "ServerStart.bat" "Install.sh" "Install.bat"];
  outputHash = "sha256-pg7Jtdfi+oNlgioAv1ZHOXqq0ePRv6erKV9kNIQArA0=";

  meta = {
    description = "SevTech: Ages is a massive modpack packed with content and progression";
    homepage = "https://www.curseforge.com/minecraft/modpacks/sevtech-ages";
  };
}
