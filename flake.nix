{
  description = "DeadFinder — find dead (broken) links in web pages, URL lists, and sitemaps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        deadfinder = pkgs.crystal.buildCrystalPackage rec {
          pname = "deadfinder";
          version = "2.0.0";

          src = ./.;

          # Generate with: crystal2nix > shards.nix
          shardsFile = ./shards.nix;

          crystalBinaries.deadfinder = {
            src = "src/cli_main.cr";
            options = [ "--release" "--no-debug" ];
          };

          nativeBuildInputs = with pkgs; [ crystal shards cmake pkg-config ];
          buildInputs = [ ];

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Find dead (broken) links in web pages, URL lists, and sitemaps";
            homepage = "https://github.com/hahwul/deadfinder";
            license = licenses.mit;
            maintainers = [ "hahwul" ];
            mainProgram = "deadfinder";
          };
        };
      in
      {
        packages.default = deadfinder;
        packages.deadfinder = deadfinder;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ deadfinder ];
          nativeBuildInputs = with pkgs; [ crystal shards crystal2nix cmake pkg-config just ];
          shellHook = ''
            echo "deadfinder development environment (Nix)"
            [ -d lib ] || shards install
          '';
        };
      });
}
