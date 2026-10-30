{
  description = "Pinned sccache REAPI development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              cargo-deny
              cargo-nextest
              clang
              clippy
              cmake
              git
              grpcurl
              hyperfine
              jq
              llvmPackages.lld
              ninja
              openssl
              pkg-config
              protobuf
              ripgrep
              rust-analyzer
              rustc
              rustfmt
              zstd
            ] ++ lib.optionals stdenv.isLinux [ perf ];

            RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;
            PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";

            shellHook = ''
              echo "sccache REAPI development shell"
              if [ -n "''${REAPI_ENDPOINT:-}" ]; then
                echo "REAPI endpoint: $REAPI_ENDPOINT"
              fi
            '';
          };
        });
    };
}
