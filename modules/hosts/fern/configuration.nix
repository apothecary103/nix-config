{
  config,
  inputs,
  ...
}:
{
  flake.modules.darwin."hosts/fern" = {
    imports = [ config.flake.modules.darwin.base ];

    networking.hostName = "fern";
    nixpkgs.hostPlatform = "aarch64-darwin";
    system.stateVersion = 6;
  };

  flake.darwinConfigurations.fern = inputs.nix-darwin.lib.darwinSystem {
    modules = [ config.flake.modules.darwin."hosts/fern" ];
  };
}
