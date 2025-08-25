{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";
    
  };

  outputs = { self, nixpkgs, flake-utils, zig }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zigpkg = zig.packages.${system}."0.15.1";
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "jetzig";
          version = "0.15.1";
          src = ./.;
          nativeBuildInputs = [ zigpkg ];
          buildPhase = ''
            cd cli
            zig build --prefix $out
          '';
          installPhase = "true";
        };
        devShells.default = pkgs.mkShell {
          name = "jetzig-dev-env";
          buildInputs = [
            zigpkg pkgs.valkey pkgs.postgresql
            (pkgs.stdenv.mkDerivation rec {
              pname = "zls";
              version = "0.15.0";
              src = pkgs.fetchurl {
                url = "https://github.com/zigtools/zls/releases/download/${version}/zls-${system}.tar.xz";
                sha256 = "1pih3bqb89mfbmf6h0vb243z8l83j2l7vz7k0wps1lipsqzzx2sh";
              };
              nativeBuildInputs = [ pkgs.makeWrapper ];
              dontUnpack = true;
              installPhase = ''
                mkdir -p $out/bin
                cd $out/bin
                tar -xf $src
                chmod +x zls
                wrapProgram $out/bin/zls --prefix PATH : ${zigpkg}/bin
              '';
            })
          ];
        };
      });
}
