{ pkgs, ... }:
{
  imports = [
    ./packages.nix
    ./typography.nix
  ];

  networking.wireless.iwd.enable = true;
  networking.useDHCP = true;

  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
        };
      };
    };
  };
}
