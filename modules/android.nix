{ inputs, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      lib,
      config,
      ...
    }:
    let
      repoJson = import ./android/repo-json.nix { inherit pkgs lib; };
      environmentBuilder = import ./android/mk-environment.nix {
        inherit
          inputs
          pkgs
          system
          lib
          ;
        inherit (repoJson) defaultRepoJson;
      };
      devShells = import ./android/dev-shells.nix {
        inherit config repoJson;
      };
    in
    {
      options.mkAndroidShell = lib.mkOption {
        type = lib.types.functionTo lib.types.package;
        default = args: (environmentBuilder.mkAndroidEnvironment args).shell;
        description = "Function to create a configured Android dev shell.";
      };

      config = {
        inherit devShells;
      };
    };
}
