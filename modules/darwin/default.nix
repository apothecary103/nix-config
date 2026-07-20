{
  inputs,
  username,
  pkgs,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
    inputs.nix-index-database.darwinModules.default
    ./apps.nix
    ./system.nix
    ./packages.nix
    ./wm.nix
  ];

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    description = username;
    shell = pkgs.fish;
  };
  environment.shells = [pkgs.fish];

  home-manager.users.${username}.imports = [../../home/darwin];
}
