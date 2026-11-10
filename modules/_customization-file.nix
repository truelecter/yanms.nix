# One entry of `customization.create`: a file or folder placed over the server package.
{
  instanceName,
  pkgs,
}: {
  name,
  config,
  options,
  lib,
  ...
}: let
  inherit (lib) mkOption types mkDefault mkIf mkDerivedConfig;
in {
  options = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to place this entry.";
    };

    target = mkOption {
      type = types.str;
      description = "Path inside the server folder. Defaults to the attribute name.";
    };

    text = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = ''
        Text of the file. `@NAME@` is replaced with `NAME` from the instance's `environmentFile`
        at start, so secrets stay out of the Nix store.
      '';
    };

    source = mkOption {
      type = types.path;
      description = "Path of the source file or folder.";
    };

    mode = mkOption {
      type = types.enum ["copy" "symlink"];
      description = ''
        `copy` puts a writable copy in place, which the server can rewrite (configs). `symlink`
        links into the Nix store, read-only, for files nothing writes (mod jars); a folder is
        linked file by file. Defaults to `copy` for `text`, `symlink` otherwise.
      '';
    };

    force = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Drop the server's own version of this path from the state at every start, so the declared
        one wins. Without it, the first change the server makes to the file persists.
      '';
    };
  };

  config = {
    target = mkDefault name;
    mode = mkDefault (
      if config.text != null
      then "copy"
      else "symlink"
    );
    source = mkIf (config.text != null) (
      mkDerivedConfig options.text (pkgs.writeText "${instanceName}-${builtins.baseNameOf name}")
    );
  };
}
