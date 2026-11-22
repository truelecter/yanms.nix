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
  flatten = true;
  cleanup = ["installer.jar.log" "modpack-download.zip"];
  outputHash = "sha256-euQvqd2h+Bm1Gi8wm1xNRDRv/mDcPfpX71cUeJftQ/I=";

  meta = {
    description = "Enigmatica 9 Expert is a quest-guided progression modpack for Minecraft 1.19.2";
    homepage = "https://www.curseforge.com/minecraft/modpacks/enigmatica9expert";
  };
}
