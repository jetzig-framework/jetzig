{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zls-flake.url = "github:zigtools/zls";
    zls-flake.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, zls-flake }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        defaultVersionConfig = zigVersions."master";
        defaultZigVersion = "master";
        zigVersions = {
          "v15" = {
            zls = "0.15.0";
            zig = "0.15.1";
            jetzig = {
              rev = "main";
            };
          };
          "v14" = {
            zls = "0.14.0";
            zig = "0.14.1";
            jetzig = {
              rev = "2c52792217b9441ed5e91d67e7ec5a8959285307";
            };
          };
          "master" = {
            zig = "master";
            zls = "master";
            jetzig = {
              ref = "main";
            };
          };
        };

        zlsBuilder = import ./zls.nix;

        makeDevShell = friendlyName: versionConfig:
          let
            zig = zig-overlay.packages.${system}.${versionConfig.zig};
            zlsVersion = versionConfig.zls;
            zls = zlsBuilder {
              inherit pkgs system zig zlsVersion zls-flake;
            };
          in
            pkgs.mkShell {
              name = "zig-${friendlyName}";
              buildInputs = [
                zig
                zls
                pkgs.zon2nix
                pkgs.valkey
                pkgs.postgresql
                pkgs.openssl
                pkgs.pkg-config
              ];
            };
        makePackage = friendlyName: versionConfig:
          let
            zig = zig-overlay.packages.${system}.${versionConfig.zig};
            jetzigSrc = if versionConfig.jetzig ? ref then
              if versionConfig.jetzig ? rev then
                builtins.fetchGit {
                  url = "https://github.com/jetzig-framework/jetzig";
                  ref = versionConfig.jetzig.ref;
                  rev = versionConfig.jetzig.rev;
                }
              else
                builtins.fetchGit {
                  url = "https://github.com/jetzig-framework/jetzig";
                  ref = versionConfig.jetzig.ref;
                }
            else
              builtins.fetchGit {
                url = "https://github.com/jetzig-framework/jetzig";
                rev = versionConfig.jetzig.rev;
              };
          in
            pkgs.stdenv.mkDerivation {
              pname = "jetzig";
              version = versionConfig.zig;
              src = jetzigSrc;
              buildInputs = [ zig ];
              dontInstall = true;
              configurePhase = ''
                export ZIG_GLOBAL_CACHE_DIR=$TEMP/.cache
              '';
              buildPhase = ''
                cd cli
                PACKAGE_DIR=${pkgs.callPackage ./cli/deps.nix {}}

                zig build install\
                  --system $PACKAGE_DIR
                  --prefix $out \
                  -Doptimize=ReleaseSafe
                  --cache-dir $ZIG_LOCAL_CACHE_DIR \
                  --global-cache-dir $ZIG_GLOBAL_CACHE_DIR
              '';
            };

        allPackages = builtins.mapAttrs makePackage zigVersions;
        allDevShells = builtins.mapAttrs makeDevShell zigVersions;

      in {
        packages = allPackages // {
          default = pkgs.stdenv.mkDerivation {
            pname = "jetzig";
            version = defaultVersionConfig.zig;
            src = ./.;
            buildInputs = [
              zig-overlay.packages.${system}.${defaultVersionConfig.zig}
            ];
            buildPhase = ''
              runHook preBuild
              cd cli
              zig build \
                --prefix $out \
                --cache-dir $ZIG_LOCAL_CACHE_DIR \
                --global-cache-dir $ZIG_GLOBAL_CACHE_DIR
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              runHook postInstall
            '';
          };
        };

        devShells = allDevShells // {
          default = makeDevShell "default" defaultVersionConfig;
        };
      });
}
