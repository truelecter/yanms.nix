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
  startScript = "unix-args";
  forgeInstaller = sources.forge-server-40-2-9.src;
  cleanup = ["*.log" "vh-setup.bat" "run.bat"];
  outputHash = "sha256-rd5NgWB0hwVfFAyMVqa89aP9gKYeyK7oM+mAqEw5u4U=";

  meta = {
    description = "Vault Hunters is an RPG based modpack focusing around the mysteries and dangers of a dimension called The Vault";
    homepage = "https://www.curseforge.com/minecraft/modpacks/vault-hunters-1-18-2";
  };
}
