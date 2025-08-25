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
          name = "jetzig-dev";
          buildInputs = [
            zigpkg pkgs.valkey pkgs.postgresql pkgs.openssl pkgs.pkg-config
            (pkgs.stdenv.mkDerivation rec {
              pname = "zls";
              version = "0.15.0";
              src = pkgs.fetchurl {
                url = "https://github.com/zigtools/zls/releases/download/${version}/zls-${system}.tar.xz";
                sha256 = {
                  "x86_64-linux" = "1pih3bqb89mfbmf6h0vb243z8l83j2l7vz7k0wps1lipsqzzx2sh";
                  "aarch64-linux" = "1m2pamnb95vz3wvjnb31h9jnxkn2wc3aazfq7d6a7mxv5lw9271d";
                  "x86_64-macos" = "14rx2gp45wm5zsd66hl2wgxbp6ibxk1jh978zv3xqnpgpww1ihs6";
                  "aarch64-macos" = "0apw0pxrkwafn9pqf5pwn33v6j9ckil5y1i402bnfzpnj0qs5ivn";
                }.${pkgs.stdenv.hostPlatform.system} or (throw "unsupported system: ${pkgs.stdenv.hostPlatform.system}");
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
