{
  config,
  inputs,
  username,
  ...
}:
let
  hjem = modules: {
    # The tree is ported from home-manager, so every target path already exists
    # as a symlink into a home-manager generation. Without this the first
    # activation stops at the first one it finds.
    clobberByDefault = true;

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
