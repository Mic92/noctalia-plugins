{ buildGoModule }:

buildGoModule {
  pname = "nostr-chatd";
  version = "0.1.0";
  src = ./.;
  vendorHash = "sha256-j5zsJhU5RAB1uF2ZayQJ+3CotLWCh/PTY/Ag5TQRf90=";

  # modernc.org/sqlite is pure Go — no CGO, no system deps.
  env.CGO_ENABLED = "0";

  meta = {
    description = "Nostr NIP-17 DM bridge for a noctalia-shell chat panel";
    mainProgram = "nostr-chatd";
  };
}
