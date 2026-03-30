{ ... }: {
  perSystem = { pkgs, ... }: {
    devShells.hello = pkgs.mkShell {
      packages = [ pkgs.hello ];
      shellHook = ''
        export HELLO_MODULE="active"
      '';
    };
  };
}
