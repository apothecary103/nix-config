# agenix rules: which identities can decrypt which files. Read by the `agenix`
# CLI from the repo root, never by the flake. One entry per host, each being
# that host's ~/.ssh/id_ed25519 — the key you already need for the git+ssh
# asahi-firmware input, so there is nothing extra to generate or place.
let
  fern = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBg4iYGZb8lCh69N7AKWAeLBJ1f1B46jW7fUfxzIGn5I";
  frieren = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJMTySSX9bqz5ewfXQhOpqjLkX5Ch/j9060Za2i8So9D";
in
{
  "secrets/proton-wireguard.age".publicKeys = [
    fern
    frieren
  ];
}
