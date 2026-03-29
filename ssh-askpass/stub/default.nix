{ buildGoModule }:

buildGoModule {
  pname = "noctalia-ssh-askpass";
  version = "0.1.0";
  src = ./.;
  vendorHash = null; # stdlib only

  env.CGO_ENABLED = "0";

  meta = {
    description = "SSH_ASKPASS stub that proxies to the noctalia ssh-askpass plugin";
    mainProgram = "noctalia-ssh-askpass";
  };
}
