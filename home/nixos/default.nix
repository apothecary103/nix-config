{ ... }:
{
  # Only ever imported by the Linux (NixOS) hosts, so the platform
  # guard is redundant — and `imports` cannot live inside `config`.
  imports = [
    ./gui
    ./core
  ];
}
