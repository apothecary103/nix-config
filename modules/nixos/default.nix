{ pkgs, ... }: {
  imports = [
    ./packages.nix
    ./typography.nix
  ];

  networking.networkmanager.enable = true;

  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        };
      };
    };
  };
}
