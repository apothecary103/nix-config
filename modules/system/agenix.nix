# Secrets are committed encrypted (secrets/*.age, recipients in
# ../../secrets.nix) and decrypted to a tmpfs at /run/agenix on activation.
#
# Both hosts decrypt with the user's own ~/.ssh/id_ed25519 — the same key
# `agenix -e` edits with. Activation runs as root, which reads it regardless of
# owner, so no root-owned host identity is needed. On frieren this means
# modules/system/preservation.nix must keep .ssh across the root rollback; that
# is already load-bearing for the git+ssh asahi-firmware input.
{ inputs, username, ... }:
let
  secrets =
    { config, ... }:
    {
      age.identityPaths = [ "${config.users.users.${username}.home}/.ssh/id_ed25519" ];
      age.secrets.proton-wireguard.file = ../../secrets/proton-wireguard.age;
    };
in
{
  flake.modules.hjem.base =
    { pkgs, ... }:
    {
      packages = [ inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default ];
    };

  flake.modules.nixos.base.imports = [
    inputs.agenix.nixosModules.default
    secrets
  ];

  flake.modules.darwin.base.imports = [
    inputs.agenix.darwinModules.default
    secrets
  ];
}
