{
  description = "A flake with a dev shell containing hello package (with unfree packages allowed)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-scrcpy.url = "github:NixOS/nixpkgs/55aa9762d0518417c21df6df53cedd9dcdbe53c7";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./modules/hello.nix
        ./modules/android.nix
      ];
      systems = [ "x86_64-linux" ];

      perSystem =
        {
          pkgs,
          system,
          config,
          ...
        }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            config.android_sdk.accept_license = true;
          };

          devShells.ai = pkgs.mkShell {
            packages = [
              inputs.llm-agents.packages.${system}.claude-code
              inputs.llm-agents.packages.${system}.codex
              pkgs.scrcpy
            ];

            shellHook = ''
              export DIRENV_LOG_FORMAT=""
              export QT_QPA_PLATFORM=${if pkgs.stdenv.isLinux then "xcb" else ""}
              echo "ai shell"
            '';
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = [
              config.devShells.hello
              config.devShells.android
            ];
            packages = [ inputs.llm-agents.packages.${system}.claude-code ];
            shellHook = ''
              export DIRENV_LOG_FORMAT=""
            '';
          };

        };
    };
}
