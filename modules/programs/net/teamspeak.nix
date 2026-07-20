{
  flake.modules.homeManager.darwin = { pkgs, ... }: {
    home.packages = [ (pkgs.callPackage ./_teamspeak6-client.nix { }) ];
  };
}
