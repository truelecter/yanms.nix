{
  mkForgeServer,
  sources,
  jdk17,
}:
mkForgeServer {
  pname = "enigmatica-9-expert";
  inherit (sources.mcs-enigmatica-9-expert) version src;

  jdk = jdk17;
  installer = "serverstarter";
  startScript = "unix-args";
  flatten = true;
  cleanup = ["installer.jar.log" "modpack-download.zip"];
  outputHash = "sha256-sjD5dNEHUNii4uyiHG17K0iMs2khYOcSd+6pcPWqhNY=";

  meta = {
    description = "Enigmatica 9 Expert is a quest-guided progression modpack for Minecraft 1.19.2";
    homepage = "https://www.curseforge.com/minecraft/modpacks/enigmatica9expert";
  };
}
