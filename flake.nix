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
        default = self.packages.${system}.nostr-chatd;
      });

      checks = forAllSystems (system: {
        nostr-chatd = self.packages.${system}.nostr-chatd;
      });
    };
}
