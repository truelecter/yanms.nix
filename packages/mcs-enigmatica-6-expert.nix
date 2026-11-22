{
  mkForgeServer,
  sources,
  jdk8,
}:
mkForgeServer {
  pname = "enigmatica-6-expert";
  inherit (sources.mcs-enigmatica-6-expert) version src;

  jdk = jdk8;
  installer = "serverstarter";
  cleanup = ["installer.jar.log" "modpack-download.zip"];
  outputHash = "sha256-Ee5onUlPdnYWkFkO3G77qZYH+gSwUmW+vAGNWiRf6iU=";

  meta = {
    description = "Enigmatica 6 Expert is a quest-guided progression modpack for Minecraft 1.16.5";
    homepage = "https://www.curseforge.com/minecraft/modpacks/enigmatica6expert";
  };
}
