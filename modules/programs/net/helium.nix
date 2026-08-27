{ inputs, ... }:
{
  flake.modules.hjem.darwin =
    { pkgs, ... }:
    {
      packages = [ inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.helium ];
    };
}
