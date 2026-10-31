{
  # The kernel build wants about 30 GB of scratch, more than this disk spares,
  # and Nix rebuilds it from nothing whenever a patch changes. Maomao, the
  # external drive, carries an ext4 image for both: a place to point
  # `--option build-dir` at, and a ccache that turns the next kernel build into
  # recompiling what changed. Every piece is optional, so the machine boots and
  # builds (without the cache) while the drive is away.
  flake.modules.nixos."hosts/frieren" =
    { config, pkgs, ... }:
    let
      image = "/mnt/maomao/nixbuild.img";
      mount = "/var/cache/kbuild";
      ccacheDir = "${mount}/ccache";
    in
    {
      fileSystems."/mnt/maomao" = {
        device = "/dev/disk/by-uuid/6A60-D16C";
        fsType = "exfat";
        options = [
          "nofail"
          "noatime"
          "x-systemd.device-timeout=5s"
          # exFAT has no owners; hand the files to the user (uid 1000 here).
          "uid=1000"
          "gid=${toString config.users.groups.users.gid}"
        ];
      };

      fileSystems.${mount} = {
        device = image;
        fsType = "ext4";
        options = [
          "loop"
          "nofail"
          "noatime"
          "x-systemd.requires-mounts-for=/mnt/maomao"
        ];
      };

      # Created once the image is mounted, so without the drive there is no
      # cache directory and the wrapper below compiles straight through.
      systemd.services.kbuild-ccache = {
        description = "ccache directory for kernel builds";
        wantedBy = [ "var-cache-kbuild.mount" ];
        after = [ "var-cache-kbuild.mount" ];
        unitConfig.RequiresMountsFor = mount;
        serviceConfig.Type = "oneshot";
        script = "${pkgs.coreutils}/bin/install -d -m 0770 -o root -g nixbld ${ccacheDir}";
      };

      nix.settings.extra-sandbox-paths = [ "${ccacheDir}?" ];

      nixpkgs.overlays = [
        (final: prev: {
          ccacheWrapper = prev.ccacheWrapper.override {
            extraConfig = ''
              export CCACHE_DIR=${ccacheDir}
              export CCACHE_COMPRESS=1
              export CCACHE_SLOPPINESS=random_seed,time_macros
              export CCACHE_UMASK=007
              export CCACHE_MAXSIZE=20G
              [ -w "$CCACHE_DIR" ] || export CCACHE_DISABLE=1
            '';
          };

          # nixos-apple-silicon builds the kernel with the callPackage it is
          # given, so handing it one that swaps in ccache's stdenv is enough.
          linux-asahi = prev.linux-asahi.override {
            callPackage = fn: args: final.callPackage fn (args // { stdenv = final.ccacheStdenv; });
          };
        })
      ];
    };
}
