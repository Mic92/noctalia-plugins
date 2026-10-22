{
  description = "noctalia-shell plugins";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      # NixOS module for the nostr-chat plugin's daemon + systemd user unit.
      #
      #   inputs.noctalia-plugins.url = "github:Mic92/noctalia-plugins";
      #   imports = [ inputs.noctalia-plugins.nixosModules.nostr-chat ];
      #   services.nostr-chat = { peerPubkey = "…"; relays = [ … ]; };
      #
      nixosModules.nostr-chat = ./nostr-chat/module.nix;
      nixosModules.default = self.nixosModules.nostr-chat;

      # Standalone daemon package, in case you want to run it without NixOS.
      packages = forAllSystems (system: {
        nostr-chatd = nixpkgs.legacyPackages.${system}.callPackage ./nostr-chat/daemon { };
        # SSH_ASKPASS stub that proxies prompts to the running noctalia shell.
        # Point your agent's SSH_ASKPASS at lib.getExe of this.
        noctalia-ssh-askpass = nixpkgs.legacyPackages.${system}.callPackage ./ssh-askpass/stub { };
        default = self.packages.${system}.nostr-chatd;
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Plugin API type definitions at plugin_api 34 (noctalia 5.3.0);
          # official-plugins main tracks noctalia's dev branch.
          apiDefinitions = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/noctalia-dev/official-plugins/734850fd1ee3badc2a18a515df31f36267852e46/noctalia.d.luau";
            hash = "sha256-3I/njZGMguFnuKiH+UvMO7srOTc7P9A2zqzzqFJJh2o=";
          };
        in
        {
          nostr-chatd = self.packages.${system}.nostr-chatd;
          noctalia-ssh-askpass = self.packages.${system}.noctalia-ssh-askpass;
          luau = pkgs.runCommand "luau-analyze" { nativeBuildInputs = [ pkgs.luau-lsp ]; } ''
            cd ${self}
            # Strict mode comes from .luaurc; per-file opt-outs would defeat it.
            if grep -rn -E '^--!(nonstrict|nocheck)' --include='*.luau' .; then
              echo "luau files must stay --!strict" >&2
              exit 1
            fi
            luau-lsp analyze --definitions=${apiDefinitions} $(find . -name '*.luau')
            touch $out
          '';
        }
      );
    };
}
