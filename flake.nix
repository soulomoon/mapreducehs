{
  description = "mapreduce";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/cfa78cb43389635df0a9086cb31b74d3c3693935";

  outputs = { self, nixpkgs, flake-utils }:

    flake-utils.lib.eachSystem [ "aarch64-darwin" ] (system:
      # flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in
      rec {
        packages = {
          mapreduce = pkgs.haskellPackages.callCabal2nix "mapreduce" ./. { };
        };
        apps = {
          local = {
            type = "app";
            program = "${packages.mapreduce}/bin/local";
          };
        };
        defaultPackage = packages.mapreduce;
        devShell =
          let haskellPackages = pkgs.haskellPackages;
          in haskellPackages.shellFor {
            packages = p: [ packages.mapreduce ];
            withHoogle = true;
            buildInputs = with haskellPackages; [
              haskell-language-server
              ghcid
              cabal-install
            ];
            # Change the prompt to show that you are in a devShell
            shellHook = "export PS1='\\e[1;34mdev > \\e[0m'";
          };
      });
}
