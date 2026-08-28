# Secrets are committed encrypted (secrets/*.age, recipients in
# ../../secrets.nix) and decrypted to a tmpfs at /run/agenix on activation.
#
# Both hosts decrypt with the user's own id_ed25519 — the same key `agenix -e`
# edits with. Activation runs before preservation's home bind mounts, so NixOS
# reads the key directly from its backing path under /persist; Darwin reads it
# from the normal home directory.
{ inputs, username, ... }:
let
  secrets =
    { config, pkgs, ... }:
    {
      age.identityPaths = [
        (
          if pkgs.stdenv.hostPlatform.isLinux then
            "/persist/home/${username}/.ssh/id_ed25519"
          else
            "${config.users.users.${username}.home}/.ssh/id_ed25519"
        )
      ];
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
