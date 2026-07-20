{ pkgs, ... }: {
  imports = [
    ./packages.nix
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
