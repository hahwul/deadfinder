{
  description = "DeadFinder - Find dead-links (broken links) in web pages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ruby = pkgs.ruby_3_3;

        # Bundle all gem dependencies
        gems = pkgs.bundlerEnv {
          name = "deadfinder-gems";
          inherit ruby;
          gemdir = self;
          groups = [ "default" ];
        };

        # Main deadfinder package
        deadfinder = pkgs.stdenv.mkDerivation {
          pname = "deadfinder";
          version = "1.9.1";
          src = self;

          buildInputs = [ gems gems.wrappedRuby ];
          nativeBuildInputs = [ pkgs.makeWrapper ];

          dontBuild = true;

          installPhase = ''
            runHook preInstall
            
            mkdir -p $out/bin $out/lib
            cp -r lib/* $out/lib/
            
            # Create wrapper that uses bundled gems
            makeWrapper ${gems.wrappedRuby}/bin/ruby $out/bin/deadfinder \
              --add-flags "-I$out/lib ${self}/bin/deadfinder"
            
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Find dead-links (broken links) in web pages";
            longDescription = ''
              Dead link (broken link) means a link within a web page that cannot be connected.
              These links can have a negative impact to SEO and Security.
              This tool makes it easy to identify and modify.
            '';
            homepage = "https://github.com/hahwul/deadfinder";
            license = licenses.mit;
            maintainers = [ ];
            mainProgram = "deadfinder";
            platforms = platforms.unix;
          };
        };
      in
      {
        packages = {
          default = deadfinder;
        };

        # Development shell with all dependencies
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ruby
            bundler
            bundix
            zlib
            libyaml
            libffi
            pkg-config
            libxml2
            libxslt
            curl
          ];

          shellHook = ''
            export GEM_HOME=$PWD/.gem
            export GEM_PATH=$GEM_HOME
            export PATH=$GEM_HOME/bin:$PATH
            
            echo "🔍 DeadFinder development shell"
            echo ""
            echo "Quick start:"
            echo "  bundle install       - Install dependencies"
            echo "  bundle exec rspec    - Run tests"
            echo "  bundle exec rubocop  - Run linter"
            echo ""
            echo "To regenerate gemset.nix after updating dependencies:"
            echo "  bundix -l"
          '';
        };

        apps.default = {
          type = "app";
          program = "${deadfinder}/bin/deadfinder";
        };
      }
    );
}
