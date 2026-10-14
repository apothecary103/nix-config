let
  nix = {
    nixpkgs.config.allowUnfree = true;

    nix = {
      channel.enable = false;

      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];

        # The only indirect reference we use is pinned above, so the global
        # registry would only add an unpinned network fetch.
        flake-registry = "";

        extra-substituters = [ "https://nix-community.cachix.org" ];
        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };
  };
in
{
  flake.modules.nixos.base = {
    imports = [ nix ];
    nix.optimise = {
      automatic = true;
      dates = "weekly";
    };
  };

  flake.modules.darwin.base = {
    imports = [ nix ];
    # A NixOS VM on this Mac, so frieren's aarch64-linux install image can be
    # built here without another machine.
    nix.linux-builder = {
      enable = true;
      systems = [ "aarch64-linux" ];
      # Keeps the VM disk on the external drive; the image build needs far more
      # room than the internal disk has.
      workingDirectory = "/Users/apothecary/linux-builder";
      # The image build needs more than the VM default of 20 GiB, both for the
      # store and for the packaged root image.
      config.virtualisation.darwin-builder = {
        diskSize = 100 * 1024;
        memorySize = 8 * 1024;
      };
      # Eight of the Mac's ten cores; the rest stay free for macOS.
      config.virtualisation.cores = 8;
      maxJobs = 8;
    };
    nix.optimise = {
      automatic = true;
      interval = {
        Weekday = 7;
        Hour = 4;
        Minute = 15;
      };
    };
  };
}
