# `backup.restic` of an instance: nixpkgs' `services.restic.backups.<name>` options, minus the
# ones the module sets (user, the prepare and cleanup commands), with defaults from
# `services.yanms.backup.restic`.
{
  globalOptions,
  globalConfig,
  instanceName,
  instanceConfig,
}: {lib, ...}: let
  inherit (lib) mkOption mkEnableOption mkDefault mkIf types;
  defaults = globalConfig.services.yanms.backup.restic;

  # runCheck: its default reads the backup's own name, which only nixpkgs' submodule has.
  managed = ["_module" "backupPrepareCommand" "backupCleanupCommand" "user" "paths" "runCheck"];
  resticOptions = lib.filterAttrs (n: _: !(lib.elem n managed)) (globalOptions.services.restic.backups.type.getSubOptions []);

  fromDefault = name: mkIf (defaults.${name} != null) (mkDefault defaults.${name});
in {
  options =
    resticOptions
    // {
      enable = mkEnableOption "restic backups of the server state";

      paths = mkOption {
        type = types.listOf types.str;
        default = [instanceConfig.dirnames.state];
        defaultText = lib.literalExpression "[dirnames.state]";
        description = "Paths to back up. Defaults to the server state (the overlay's upper layer).";
      };
    };

  config = {
    repository = mkIf (defaults.repositoryPrefix != null) (mkDefault "${defaults.repositoryPrefix}/${instanceName}");
    passwordFile = fromDefault "passwordFile";
    environmentFile = fromDefault "environmentFile";
    initialize = mkDefault defaults.initialize;
    pruneOpts = mkDefault defaults.pruneOpts;
    timerConfig = fromDefault "timerConfig";
  };
}
