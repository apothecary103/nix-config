{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.hardware.siliconBakery;
  media = cfg.media;
  encode = media.encode;
  soc = cfg.profile.soc or null;

  # The community driver's runtime overlay variant per SoC (docs/ave-port.txt).
  overlayVariants = {
    t6020 = 15;
  };

  apple-ave = config.boot.kernelPackages.callPackage ../pkgs/apple-ave.nix { };
in
{
  options.hardware.siliconBakery.media = {
    decode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Hardware video decode on the media engine's AVD block, as VideoToolbox
        does on macOS: the in-kernel apple-avd driver, Asahi's open AVD
        firmware, and VA-API through asahi-va-driver (nixos-apple-silicon's
        hardware.asahi.avd). Experimental upstream; players fall back to
        software when it fails. On the M2 Pro it decodes H.264, HEVC and VP9;
        AV1 needs an M3. Encode is media.encode.
      '';
    };

    decodeCodecs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "all" ];
      example = [ "all_free" ];
      description = ''
        Which codecs the AVD firmware is built with, once it can choose
        (avd-fw 0.2, nixpkgs#581622, and nixos-apple-silicon#575, which default
        to "all_free": VP9 and AV1 only). "all" keeps H.264 and HEVC, which the
        firmware decodes today; on an M2 Pro "all_free" leaves VP9 alone.
        Enabling the patented codecs is a licensing choice. Ignored while the
        firmware has no such switch.
      '';
    };

    decodeFixes = lib.mkEnableOption ''
      Silicon Bakery's fixes to the AVD driver (patches/linux-avd), built out
      of tree as apple_avd_bakery in place of the in-tree apple_avd, without a
      kernel rebuild: the codec mask where avd-fw 0.2 writes it, a failed job
      reset at once instead of after a 2 s watchdog, streams the hardware
      cannot decode refused, buffer reuse. Untested on hardware; compare with
      tools/avd-bench before and after (docs/avd-port.txt)'';

    decodeP210 = lib.mkEnableOption ''
      the V4L2 P210 pixel format (patches/linux-avd/0003), so decodeFixes can
      output HEVC 4:2:2 10-bit instead of refusing it. Rebuilds the kernel'';

    encode = {
      enable = lib.mkEnableOption ''
        the media engine's hardware video encoder (AVE): the community
        apple-ave V4L2 driver with Silicon Bakery's t6020 port, for
        h264_v4l2m2m / hevc_v4l2m2m in ffmpeg (pkgs.siliconBakery.ffmpeg-ave
        for B-frames and MP4/MKV) and v4l2h264enc / v4l2h265enc in GStreamer.
        EXPERIMENTAL and untested on the M2 Pro: a failed bring-up can hang or
        reset the machine. Follow docs/ave-port.txt's staged plan, with SSH
        from another machine, before turning on autoload or deviceTree'';

      firmware = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression ''inputs.asahi-firmware + "/ave"'';
        description = ''
          A directory holding apple/ave_h14s.bin, apple/ave-13.5-dpe-*.bin,
          apple/ave-13.5-axi2af-*.bin and optionally
          apple/ave-13.5-*-data-pristine.bin, as tools/bakery-ave-fw writes
          them from this Mac's own macOS 13.5 (the Asahi stub). They are
          Apple's: keep them in a private input, never a public flake or cache.
        '';
      };

      autoload = lib.mkEnableOption ''
        loading the encoder at boot (with the runtime device tree overlay
        unless deviceTree is on). Off, load it by hand: modprobe ave_overlay,
        then modprobe apple_ave'';

      deviceTree = lib.mkEnableOption ''
        the encoder and its DARTs in the kernel's device tree
        (patches/linux-ave) instead of the runtime overlay. m1n1's boot.bin
        carries the current kernel's device trees, so an older generation
        does not bring the old ones back; keep a copy of /boot/m1n1/boot.bin
        before switching (docs/ave-port.txt). Rebuilds the kernel'';
    };

    prores = {
      enable = lib.mkEnableOption ''
        the media engine's ProRes engine (apr0): Silicon Bakery's apple-prores
        V4L2 encoder for all six ProRes profiles (decoder behind the module's
        decoder=1). EXPERIMENTAL and untested: a wrong DMA tunables table can
        hang the machine. Follow docs/prores-port.txt's staged plan first'';

      firmware = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression ''inputs.asahi-firmware + "/prores"'';
        description = ''
          A directory holding apple/prores-13.5-d0.bin, the DMA tunables
          tools/bakery-prores-tables writes from this Mac's own macOS 13.5. Apple's
          data: keep it in a private input.
        '';
      };

      autoload = lib.mkEnableOption "loading apple_prores at boot (with the runtime overlay unless deviceTree is on)";

      deviceTree = lib.mkEnableOption ''
        the ProRes engine in the kernel's device tree (patches/linux-prores)
        instead of the runtime overlay. Rebuilds the kernel; keep a copy of
        /boot/m1n1/boot.bin first, as for media.encode.deviceTree'';
    };

    jpeg = {
      enable = lib.mkEnableOption ''
        the media engine's two JPEG cores: Silicon Bakery's apple-jpeg V4L2
        baseline JPEG encoder and decoder (GStreamer v4l2jpegenc/v4l2jpegdec).
        EXPERIMENTAL and untested; follow docs/jpeg-port.txt first'';

      autoload = lib.mkEnableOption "loading apple_jpeg at boot (with the runtime overlay unless deviceTree is on)";

      deviceTree = lib.mkEnableOption ''
        the JPEG cores in the kernel's device tree (patches/linux-jpeg) instead
        of the runtime overlay. Rebuilds the kernel'';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && media.prores.enable) {
      assertions = [
        {
          assertion = media.prores.firmware != null;
          message = "hardware.siliconBakery.media.prores needs firmware: run tools/bakery-prores-tables on macOS and point media.prores.firmware at its output.";
        }
        {
          assertion = soc == "t6020";
          message = "hardware.siliconBakery.media.prores: the ProRes port covers t6020, not ${toString soc}.";
        }
      ];
      boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ../pkgs/apple-prores.nix { }) ];
      hardware.firmware = lib.optional (media.prores.firmware != null) (
        pkgs.runCommand "apple-prores-firmware" { } ''
          mkdir -p $out/lib/firmware
          cp -r ${media.prores.firmware}/apple $out/lib/firmware/
        ''
      );
      boot.kernelPatches = lib.mkIf media.prores.deviceTree pkgs.siliconBakery.kernelPatchesProres;
      boot.blacklistedKernelModules = lib.optional (
        media.prores.deviceTree && !media.prores.autoload
      ) "apple_prores";
      boot.kernelModules = lib.optional media.prores.autoload "apple_prores";
      boot.extraModprobeConfig = lib.optionalString (!media.prores.deviceTree) ''
        softdep apple_prores pre: prores_overlay
      '';
      services.udev.extraRules = ''
        SUBSYSTEM=="video4linux", ATTR{name}=="apple-prores*", SYMLINK+="$attr{name}", GROUP="video", MODE="0660"
      '';
      environment.systemPackages = [ pkgs.v4l-utils ];
    })

    (lib.mkIf (cfg.enable && media.jpeg.enable) {
      assertions = [
        {
          assertion = soc == "t6020";
          message = "hardware.siliconBakery.media.jpeg: the JPEG port covers t6020, not ${toString soc}.";
        }
      ];
      boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ../pkgs/apple-jpeg.nix { }) ];
      boot.kernelPatches = lib.mkIf media.jpeg.deviceTree pkgs.siliconBakery.kernelPatchesJpeg;
      boot.blacklistedKernelModules = lib.optional (
        media.jpeg.deviceTree && !media.jpeg.autoload
      ) "apple_jpeg";
      boot.kernelModules = lib.optional media.jpeg.autoload "apple_jpeg";
      boot.extraModprobeConfig = lib.optionalString (!media.jpeg.deviceTree) ''
        options apple_jpeg_overlay cores=3
        softdep apple_jpeg pre: apple_jpeg_overlay
      '';
      services.udev.extraRules = ''
        SUBSYSTEM=="video4linux", ATTR{name}=="apple-jpeg*", SYMLINK+="$attr{name}", GROUP="video", MODE="0660"
      '';
      environment.systemPackages = [
        pkgs.v4l-utils
        pkgs.gst_all_1.gst-plugins-good
      ];
    })

    (lib.mkIf (cfg.enable && encode.enable) {
      assertions = [
        {
          assertion = encode.firmware != null;
          message = "hardware.siliconBakery.media.encode needs firmware: run tools/bakery-ave-fw on macOS and point media.encode.firmware at its output.";
        }
        {
          assertion = overlayVariants ? ${toString soc};
          message = "hardware.siliconBakery.media.encode: the AVE port covers ${lib.concatStringsSep ", " (lib.attrNames overlayVariants)}, not ${toString soc}.";
        }
      ];

      boot.extraModulePackages = [ apple-ave ];
      hardware.firmware = lib.optional (encode.firmware != null) (
        pkgs.runCommand "apple-ave-firmware" { } ''
          mkdir -p $out/lib/firmware
          cp -r ${encode.firmware}/apple $out/lib/firmware/
        ''
      );

      boot.kernelPatches = lib.mkIf encode.deviceTree pkgs.siliconBakery.kernelPatchesAve;
      # With the node in the device tree udev would load the driver at every
      # boot; only autoload should.
      boot.blacklistedKernelModules = lib.optional (encode.deviceTree && !encode.autoload) "apple_ave";
      boot.kernelModules = lib.optional encode.autoload "apple_ave";
      boot.extraModprobeConfig = lib.optionalString (!encode.deviceTree) ''
        options ave_overlay variant=${toString (overlayVariants.${toString soc} or 0)}
        softdep apple_ave pre: ave_overlay
      '';

      services.udev.extraRules = ''
        SUBSYSTEM=="video4linux", ATTR{name}=="apple-ave-enc", SYMLINK+="apple-ave-enc", GROUP="video", MODE="0660"
      '';
      environment.systemPackages = [
        pkgs.v4l-utils
        (lib.lowPrio pkgs.siliconBakery.ffmpeg-ave)
      ];
    })

    (lib.mkIf (cfg.enable && media.decode && media.decodeFixes) {
      boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ../pkgs/apple-avd.nix { }) ];
      # Same compatibles and driver name: udev then loads apple_avd_bakery.
      boot.blacklistedKernelModules = [ "apple_avd" ];
      boot.kernelPatches = lib.optional media.decodeP210 {
        name = "v4l2-p210";
        patch = ../patches/linux-avd/0003-media-v4l2-add-the-P210-pixel-format.patch;
      };
    })

    (lib.mkIf (cfg.enable && media.decode) (
      lib.mkMerge [
        {
          hardware.asahi.avd = {
            enable = true;
            vaapi-support = true;
          };
          # vainfo and v4l2-ctl, to see what the decoder offers.
          environment.systemPackages = [
            pkgs.libva-utils
            pkgs.v4l-utils
          ];
          # The attribute is always defined, so the overlay's names never depend
          # on a package (which would recurse); only its value looks inside.
          nixpkgs.overlays = [
            (final: prev: {
              avd-fw =
                if (lib.functionArgs prev.avd-fw.override) ? codecs then
                  prev.avd-fw.override { codecs = media.decodeCodecs; }
                else
                  prev.avd-fw;
            })
          ];
        }
        (lib.optionalAttrs (options.hardware.asahi.avd ? codecs) {
          hardware.asahi.avd.codecs = media.decodeCodecs;
        })
      ]
    ))
  ];
}
