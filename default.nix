let
  compilerVersion = "ghc8107";
  compilerSet = pkgs.haskell.packages."${compilerVersion}";

  githubTarball = owner: repo: 
    builtins.fetchGit {
      url = "https://github.com/${owner}/${repo}.git";
      rev = "db726c35225dbcfda496e9ea314e26052a7f075e";
      allRefs = true;
    };
  pkgs = import (githubTarball "NixOS" "nixpkgs") { inherit config; };
  gitIgnore = pkgs.nix-gitignore.gitignoreSourcePure;
  
  config = {
    packageOverrides = super: let self = super.pkgs; in rec {
      haskell = super.haskell // {
        packageOverrides = self: super: {
          haskell-nix = super.callCabal2nix "mapreduce" (gitIgnore [./.gitignore] ./.) {};
        };
      };
    };
  };
  
in {
  inherit pkgs;
  shell = compilerSet.shellFor {
    packages = p: [];
    # packages = p: [];
    buildInputs = with pkgs; [
      zlib
      compilerSet.cabal-install
      compilerSet.ghc
      compilerSet.haskell-language-server
      # compilerSet.implicit-hie
    ];
    LIBRARY_PATH = "${pkgs.zlib}/lib";
  };
}