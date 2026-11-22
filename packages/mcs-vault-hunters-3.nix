{
  mkForgeServer,
  sources,
  jdk17,
}:
mkForgeServer {
  pname = "vault-hunters-3";
  inherit (sources.mcs-vault-hunters-3) version src;

  jdk = jdk17;
  installer = "forge";
  forgeInstaller = sources.forge-server-40-2-9.src;
  cleanup = ["*.log" "vh-setup.bat" "run.bat"];
  outputHash = "sha256-Lu1bnPAskOIDnZ0z6SYb88KCtBoEeiJktV4+TqXArx8=";

  meta = {
    description = "Vault Hunters is an RPG based modpack focusing around the mysteries and dangers of a dimension called The Vault";
    homepage = "https://www.curseforge.com/minecraft/modpacks/vault-hunters-1-18-2";
  };
}
