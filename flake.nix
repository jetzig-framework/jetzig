{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-utils.follows = "flake-utils";
    };
    zls-flake.url = "github:zigtools/zls/0.15.1";
    zls-flake.inputs = {
      nixpkgs.follows = "nixpkgs";
      zig-overlay.follows = "zig-overlay";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, zls-flake }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        zigVersion = "0.15.2";

        pkgs = nixpkgs.legacyPackages.${system};
        zig = zig-overlay.packages.${system}.${zigVersion};
        zls = zls-flake.packages.${system}.zls;

        valkeyConf = pkgs.writeTextFile {
          name = "valkey.conf";
          text = ''
            port 6379
            dbfilename dump.rdb
            daemonize yes
            save 900 1
            save 300 10
            save 60 10000
            stop-writes-on-bgsave-error no
          '';
        };

        databaseStart = pkgs.writeShellApplication {
          name = "test-db-start";
          runtimeInputs =
            [ pkgs.postgresql pkgs.valkey pkgs.coreutils pkgs.gum ];
          text = ''
            mkdir -p "$TMPDIR/postgres" "$TMPDIR/valkey"
            gum spin \
              --spinner dot \
              --title "Setting up postgres" \
              -- initdb \
              -D "$TMPDIR/postgres" \
              --auth-local=trust \
              --auth-host=trust \
              --username=postgres
            pg_ctl \
              -D "$TMPDIR/postgres" \
              -l "$TMPDIR/postgres/logfile" \
              -o "-c port=5432 -c unix_socket_directories=$TMPDIR" \
              start
            gum log --time=TimeOnly --prefix=JETZIG-DEV-ENV "Postgres started"
            valkey-server ${valkeyConf} \
              --dir "$TMPDIR/valkey" \
              --logfile "$TMPDIR/valkey/valkey.log" \
              --pidfile "$TMPDIR/valkey/valkey.pid"
            gum log --time=TimeOnly --prefix=JETZIG-DEV-ENV "Valkey started"
          '';
        };

        devHelp = pkgs.writeShellApplication {
          name = "dev-help";
          runtimeInputs = [ pkgs.gum zig ];
          text = ''
            gum format -- \
              "# Jetzig Development Environment" \
              "" \
              "**zig version**: $(zig version)" \
              "**Temp Dir**: $TMPDIR" \
              "" \
              "**test-db-start**: Start PostgreSQL and Valkey for development" \
              "**test-db-stop**: Stop and clean up database servers" \
              "**dev-help**: Show this message again" \
          '';
        };

        databaseStop = pkgs.writeShellApplication {
          name = "test-db-stop";
          runtimeInputs = [ pkgs.postgresql pkgs.valkey pkgs.coreutils ];
          text = ''
            if pg_ctl -D "$TMPDIR/postgres" status > /dev/null 2>&1; then
              pg_ctl -D "$TMPDIR/postgres" stop
            fi
            if [ -f "$TMPDIR/valkey/valkey.pid" ]; then
              pid=$(cat "$TMPDIR/valkey/valkey.pid")
              if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
              fi
            fi
            rm -rf "$TMPDIR/postgres" "$TMPDIR/valkey"
          '';
        };

        dependencies = [ zig pkgs.openssl ];

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "jetzig";
          version = zigVersion;
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper pkgs.git ];
          buildInputs = dependencies;
          dontInstall = false;

          configurePhase = ''
            runHook preConfigure
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/.cache
            export ZIG_LOCAL_CACHE_DIR=$TMPDIR/.local-cache
            export PACKAGE_DIR=${pkgs.callPackage ./cli/deps.nix { }}
            mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            cd cli
            zig build install \
              --system $PACKAGE_DIR \
              --prefix $out \
              -Doptimize=ReleaseSafe \
              --cache-dir $ZIG_LOCAL_CACHE_DIR \
              --global-cache-dir $ZIG_GLOBAL_CACHE_DIR
            runHook postBuild
          '';

          postFixup = ''
            for bin in $out/bin/*; do
              wrapProgram $bin \
            	  --prefix PATH : ${pkgs.lib.makeBinPath dependencies} \
            	  --prefix LD_LIBRARY_PATH : ${
                 pkgs.lib.makeLibraryPath dependencies
               }
            done
          '';
        };

        devShells.default = pkgs.mkShell {
          name = "zig-${zigVersion}";
          buildInputs = [
            zig
            zls
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.gawk
            pkgs.findutils
            pkgs.gum
            pkgs.zon2nix
            pkgs.valkey
            pkgs.postgresql
            pkgs.openssl
            pkgs.pkg-config
            databaseStart
            databaseStop
            devHelp
          ];
          shellHook = ''
            dev-help
            cleanup_jetzig_test() {
              test-db-stop
            }
            trap cleanup_jetzig_test EXIT INT TERM
          '';
        };
      });
}
