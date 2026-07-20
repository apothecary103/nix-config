{
  inputs,
  username,
  pkgs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.default
    ./packages.nix
    ./typography.nix
    ./memory.nix
    ./bluetooth.nix
  ];

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "video"
      "input"
    ];
  };

  home-manager.users.${username}.imports = [../../home/nixos];

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
