{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-utils.follows = "flake-utils";
    };
    zls-flake.url = "github:zigtools/zls";
    zls-flake.inputs = {
      nixpkgs.follows = "nixpkgs";
      zig-overlay.follows = "zig-overlay";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, zls-flake }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        zigVersion = "0.14.1";
        zlsVersion = "0.14.0";

        pkgs = nixpkgs.legacyPackages.${system};
        zlsBuilder = import ./zls.nix;
        zig = zig-overlay.packages.${system}.${zigVersion};
        zls = zlsBuilder {
          inherit pkgs system zig zls-flake;
          zlsVersion = zlsVersion;
        };

        testSetup = pkgs.writeShellScriptBin "test-setup" ''
          JETZIG_TEST_DIR="$TMPDIR/jetzig-env"
          POSTGRES_DIR="$JETZIG_TEST_DIR/postgres-db"
          VALKEY_DIR="$JETZIG_TEST_DIR/valkey-db"
          mkdir -p "$POSTGRES_DIR"
          mkdir -p "$VALKEY_DIR"
          gum spin --spinner dot --title "Setting up postgres" -- initdb \
            -D "$POSTGRES_DIR" \
            --auth-local=trust \
            --auth-host=trust \
            --username=postgres
          echo "port = 5432" >> "$POSTGRES_DIR/postgresql.conf"
          echo "unix_socket_directories = '$PWD'" >> "$POSTGRES_DIR/postgresql.conf"
          pg_ctl \
            -D "$POSTGRES_DIR" \
            -l "$POSTGRES_DIR/logfile" \
            start
          gum log --time=TimeOnly --prefix=JETZIG-ENV "Postgres started"
          cat > "$VALKEY_DIR/valkey.conf" << EOF
port 6379
dir $VALKEY_DIR
dbfilename dump.rdb
logfile $VALKEY_DIR/valkey.log
daemonize yes
pidfile $FALKEY_DIR/valkey.pid
save 900 1
save 300 10
save 60 10000
EOF
          valkey-server \
            "$VALKEY_DIR/valkey.conf"
          gum log --time=TimeOnly --prefix=JETZIG-ENV "Valkey started"
        '';

        testTeardown = pkgs.writeShellScriptBin "test-teardown" ''
          JETZIG_TEST_DIR="$TMPDIR/jetzig-env"
          POSTGRES_DIR="$JETZIG_TEST_DIR/postgres-db"
          VALKEY_DIR="$JETZIG_TEST_DIR/valkey-db"
          if pg_ctl -D "$POSTGRES_DIR" status > /dev/null 2>&1; then
            pg_ctl -D "$POSTGRES_DIR" stop
          fi
          if [ -d "$POSTGRES_DIR" ]; then
            rm -rf "$POSTGRES_DIR"
          fi
          if [ -f "$VALKEY_DIR/valkey.pid" ]; then
            kill "$(cat "$VALKEY_DIR/valkey.pid")"
          fi
          if [ -d "$VALKEY_DIR" ]; then
            rm -rf "$VALKEY_DIR"
          fi
        '';

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "jetzig";
          version = zigVersion;
          src = ./.;
          buildInputs = [ zig ];
          dontInstall = true;
          configurePhase = ''
            runHook preConfigure
            export ZIG_GLOBAL_CACHE_DIR=$TEMP/.cache
            export ZIG_LOCAL_CACHE_DIR=$TEMP/.local-cache
            export PACKAGE_DIR=${pkgs.callPackage ./cli/deps.nix {}}
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
        };

        devShells.default = pkgs.mkShell {
          name = "zig-0.14.1";
          buildInputs = [
            zig
            zls
            pkgs.gum
            pkgs.zon2nix
            pkgs.valkey
            pkgs.postgresql
            pkgs.openssl
            pkgs.pkg-config
            testSetup
            testTeardown
          ];
          shellHook = ''
            JETZIG_TEST_DIR="$TMPDIR/jetzig-env"
            mkdir -p "$JETZIG_TEST_DIR"
            gum format -- \
              "# JETZIG DEV ENV" \
              "Commands:" \
              "- test-setup: Starts postgres and valkey for jetzig tests" \
              "- test-teardown: Stops postgres and valkey and cleans up created dirs"
            cleanup_jetzig_test() {
              test-teardown
              rm -rf "$TMPDIR/jetzig-env"
            }
            trap cleanup_jetzig_test EXIT
          '';
        };
      });
}
