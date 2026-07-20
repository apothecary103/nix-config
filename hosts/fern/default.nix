{ ... }:

{
  imports = [
    ../../modules/base
    ../../modules/darwin
  ];

  networking.hostName = "fern";

  system.stateVersion = 6;
}
