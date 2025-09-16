{ pkgs, system, zig, zlsVersion, zls-flake}:

let
  target = builtins.replaceStrings ["darwin"] ["macos"] system;
in

if zlsVersion == "master" then
  let
    zlsPackage = zls-flake.packages.${system}.zls.overrideAttrs {
      inherit zig;
    };
  in
    zlsPackage.overrideAttrs (oldAttrs: {
      buildPhase = ''
        export ZIG_GLOBAL_CACHE_DIR=$TEMP/.cache
        PACKAGE_DIR=${pkgs.callPackage "${zls-flake}/deps.nix" {}}
        zig build install \
          --system $PACKAGE_DIR \
          -Dtarget=${target} \
          -Doptimize=ReleaseSafe \
          -Dversion-string="$(zig version)" \
          --color off \
          --prefix $out
      '';
      checkPhase = ''
        zig build test \
          --system $PACKAGE_DIR \
          -Dtarget=${target} \
          -Dversion-string="$(zig version)" \
          --color off
      '';
    })
else
  pkgs.stdenv.mkDerivation rec {
    pname = "zls";
    version = zlsVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/zigtools/zls/releases/download/${version}/zls-${system}.tar.xz";
      sha256 = {
        "0.15.0" = {
          "x86_64-linux" = "1pih3bqb89mfbmf6h0vb243z8l83j2l7vz7k0wps1lipsqzzx2sh";
          "aarch64-linux" = "1m2pamnb95vz3wvjnb31h9jnxkn2wc3aazfq7d6a7mxv5lw9271d";
          "x86_64-macos" = "14rx2gp45wm5zsd66hl2wgxbp6ibxk1jh978zv3xqnpgpww1ihs6";
          "aarch64-macos" = "0apw0pxrkwafn9pqf5pwn33v6j9ckil5y1i402bnfzpnj0qs5ivn";
        };
        "0.14.0" = {
          "x86_64-linux" = "0q0kkilvv65xna6i93gis8wbirsv94k31g79nq29pp535d08s7v6";
          "aarch64-linux" = "1k4n24d5zasc2xlsvjpf73kw6lj6mdg3b2mdkqadnq9rmxwlcpyq";
          "x86_64-macos" = "1p0iymma1765jclf6wngq6fj14imawgs1d3h56scrvjxckj6kvms";
          "aarch64-macos" = "0kbc9l3rs6vg5nrhg9f02n18gkidl4sq0bamixkq6db0z7hjgdnz";
        };
      }.${version}.${pkgs.stdenv.hostPlatform.system} or (throw "unsupported ZLS version ${version} for system ${pkgs.stdenv.hostPlatform.system}");
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];
    buildInputs = [ zig ];
    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cd $out/bin
      tar -xf $src
      chmod +x zls
      wrapProgram $out/bin/zls --prefix PATH : ${zig}/bin
    '';

    phases = [ "installPhase" "fixupPhase" ];
}

