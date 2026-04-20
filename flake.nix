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

        # lexbor.cr's postinstall hook clones the upstream lexbor C library
        # from GitHub at a pinned commit (lib/lexbor/src/ext/revision) and
        # builds it via cmake. The Nix sandbox blocks network access, so
        # pre-fetch the source as a fixed-output derivation and drop it
        # into place during preBuild — then cmake runs normally.
        lexborCSrc = pkgs.fetchgit {
          url = "https://github.com/lexbor/lexbor.git";
          rev = "971faf11a5f45433b9193a143e2897d8c0fd5611";
          sha256 = "0v3ka5dhgz2jkmigdjcjm3vmxlc9yv4hks6pz13xzgagxxfwlw7s";
        };

        deadfinder = pkgs.crystal.buildCrystalPackage rec {
          pname = "deadfinder";
          version = "2.0.0";

          src = ./.;

          # Generate with: crystal2nix > shards.nix
          shardsFile = ./shards.nix;

          nativeBuildInputs = with pkgs; [ crystal shards cmake pkg-config ];
          buildInputs = [ ];

          # lexbor.cr's postinstall hook (build_ext.cr) clones the lexbor C
          # library at a pinned commit and builds it via cmake. The Nix
          # sandbox blocks network, so we (a) replace the read-only shard
          # symlink with a writable copy, (b) drop in the pre-fetched C
          # source, and (c) run cmake directly here — bypassing build_ext.cr.
          preBuild = ''
            cp -RL lib/lexbor lib/lexbor.rw
            chmod -R u+w lib/lexbor.rw
            rm lib/lexbor
            mv lib/lexbor.rw lib/lexbor

            cp -r ${lexborCSrc} lib/lexbor/src/ext/lexbor-c
            chmod -R u+w lib/lexbor/src/ext/lexbor-c

            mkdir -p lib/lexbor/src/ext/lexbor-c/build
            ( cd lib/lexbor/src/ext/lexbor-c/build \
              && cmake .. \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DLEXBOR_BUILD_TESTS_CPP=OFF \
                  -DLEXBOR_INSTALL_HEADERS=OFF \
                  -DLEXBOR_BUILD_SHARED=ON \
                  -G "Unix Makefiles" \
              && cmake --build . --config Release -j $NIX_BUILD_CORES )
          '';

          buildPhase = ''
            runHook preBuild
            shards build --release --no-debug
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp bin/deadfinder $out/bin/deadfinder
            runHook postInstall
          '';

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
