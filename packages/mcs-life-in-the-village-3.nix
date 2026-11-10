{
  mkForgeServer,
  sources,
  jdk17,
}:
mkForgeServer {
  pname = "life-in-the-village-3";
  inherit (sources.mcs-life-in-the-village-3) version src;

  jdk = jdk17;
  installer = "prebuilt";
  startScript = "unix-args";
  prebuiltDir = "LITV*";

  meta = {
    description = "This pack is based around town-building mod - Minecolonies and it can be casual or challenging as you want it to be";
    homepage = "https://www.curseforge.com/minecraft/modpacks/life-in-the-village-3";
  };
}
