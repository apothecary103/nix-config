{
  config,
  inputs,
  username,
  ...
}:
let
  hjem = modules: {
    extraModules = [ inputs.hjem-rum.hjemModules.default ];
    users.${username} = {
      enable = true;
      imports = modules;
    };
  };
in
{
  flake.modules.darwin.base = {
    imports = [ inputs.hjem.darwinModules.hjem ];
    hjem = hjem [
      config.flake.modules.hjem.base
      config.flake.modules.hjem.darwin
    ];
  };

  flake.modules.nixos.base = {
    imports = [ inputs.hjem.nixosModules.hjem ];
    hjem = hjem [
      config.flake.modules.hjem.base
      config.flake.modules.hjem.linux
    ];
  };
}
