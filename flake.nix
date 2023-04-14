{
  description = "mapreduce";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  # inputs.nixpkgs.url = "github:NixOS/nixpkgs/cfa78cb43389635df0a9086cb31b74d3c3693935";
  # use unstable
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixt = {
    url = "github:nix-community/nixt";
  };

  outputs = { self, nixpkgs, flake-utils,nixt }:

    flake-utils.lib.eachSystem [ "aarch64-darwin" ] (system:
      # flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; 
          haskellPackages = pkgs.haskell.packages.ghc924;
          # haskellPackages = pkgs.haskell.packages.ghc942;
          # haskellPackages = pkgs.haskellPackages;
      in rec {
        packages = {
          mapreduce = haskellPackages.callCabal2nix "mapreduce" ./. { };
        };
        apps = {
            local = {
              type = "app";
              program = "${packages.mapreduce}/bin/local";
            };
            server = {
              type = "app";
              program = "${packages.mapreduce}/bin/server";
            };
            worker = {
              type = "app";
              program = "${packages.mapreduce}/bin/worker";
            };
          };
        packages.default = packages.mapreduce;
        devShells.default =
          haskellPackages.shellFor {
            packages = p: [ packages.mapreduce ];
            withHoogle = true;
            buildInputs = with haskellPackages; [
              haskell-language-server
              ghcid
              cabal-install
              cabal2nix
            ];
            # Change the prompt to show that you are in a devShell
            shellHook = "export PS1='\\e[1;34mdev > \\e[0m'";
          };
      });
}
