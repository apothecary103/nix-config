{ username, ... }: {
  flake.modules.darwin.base = { pkgs, ... }: {
    users.users.${username} = {
      name = username;
      home = "/Users/${username}";
      description = username;
      shell = pkgs.fish;
    };
    environment.shells = [ pkgs.fish ];

    programs.fish.enable = true;
    system.primaryUser = username;
  };

  flake.modules.nixos.base = { pkgs, ... }: {
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

    programs.fish.enable = true;
  };
}
