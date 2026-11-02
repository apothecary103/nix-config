{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.siliconBakery;
  display = cfg.display;
  internal = cfg.profile.display.internal or "eDP-1";
  trueTone = display.trueTone;
  macosTrueTone = cfg.profile.display.trueTone or { };
in
{
  options.hardware.siliconBakery.display = {
    kernelPatches = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        appledrm fixes on top of linux-asahi (patches/linux): XRGB2101010, which
        10-bit clients scan out in, blended as premultiplied so its X bits are
        not read as alpha.
      '';
    };

    p3Outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ internal ];
      defaultText = lib.literalExpression ''[ "eDP-1" ]'';
      description = ''
        Outputs whose panel is Display P3, for Silicon Bakery's river
        (RIVER_DISPLAY_P3_OUTPUTS). macOS profiles the built-in Liquid Retina
        panels as exactly P3 primaries, D65 white and the sRGB curve with an
        identity vcgt, because DCP applies the factory calibration in firmware;
        untagged content is sRGB and ColorSync maps it into P3 while
        compositing. river does the same with these outputs: the kernel leaves
        RGB planes NATIVE on the internal panel, so DCP passes the P3 river
        composites straight through, and clients that tag wider content
        through colour management keep it instead of having it clipped to
        sRGB. Needs WLR_RENDERER=vulkan; 10-bit rendering
        (RIVER_RENDER_BIT_DEPTH=10) keeps the transform from banding.
      '';
    };

    experimentalHdr = lib.mkEnableOption ''
      the experimental HDR path through DCP (patches/linux-hdr): appledrm,
      booted with appledrm.experimental_hdr=1, offers the standard Colorspace
      and HDR_OUTPUT_METADATA connector properties, drives external displays
      in a PQ colour mode where DCP reports one, and in HDR tags RGB surfaces
      BT.2020 with DCP's PQ transfer function. The internal panels have no
      PQ link mode (their one colour mode is 8-bit RGB SDR), so there DCP is
      left to convert; whether it does, and whether it lifts the mini-LEDs
      past the 500-nit SDR ceiling as macOS's EDR does, is untested. Turning
      this on rebuilds the kernel; off, the driver is unchanged'';

    experimentalVrr = lib.mkEnableOption ''
      ProMotion as adaptive sync on the internal panel (patches/linux-vrr).
      In its 120 Hz timing DCP already hands every swap to the panel's timing
      controller, which refreshes between 120 and 24 Hz as frames arrive
      (bounds the 13.5 firmware sets and macOS publishes in
      IOMFBDisplayRefresh). Booted with appledrm.experimental_vrr=1, the
      panel's connector says so (vrr_capable), and a compositor that turns
      adaptive sync off holds it at 120 Hz through the firmware's APTFixedRR
      property, without a modeset. DCP 13.5 firmware only; untested on
      hardware. Turning this on rebuilds the kernel; off, the driver is
      unchanged'';

    trueTone = {
      enable = lib.mkEnableOption ''
        True Tone on the built-in panel, as macOS's CoreBrightness does it
        (docs/truetone.md). bakery-truetoned feeds the ambient light sensor's
        lux and colour temperature to CoreBrightness's colour engine,
        transliterated to C and checked against macOS's own to the bit, and
        hands the panel's DCP the matrix at the location macOS uses, ramped
        as macOS ramps it. Needs the tables from this Mac's macOS (tables).
        Turning this on rebuilds the kernel (patches/linux-truetone)'';

      tables = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression ''inputs.asahi-firmware + "/truetone"'';
        description = ''
          A directory holding apple/truetone.bin, which
          tools/bakery-truetone-tables writes from this Mac's macOS:
          CoreBrightness's a*b* gamut, adaptation tables, ramp curve and
          blackbody table. Apple's numbers: keep them in a private input,
          never a public flake or cache.
        '';
      };

      mode = lib.mkOption {
        type = lib.types.ints.between 0 5;
        default = macosTrueTone.mode or 1;
        defaultText = lib.literalExpression "profile.display.trueTone.mode or 1";
        description = ''
          CoreBrightness's ColorAdaptationMode, from the profile: the index of
          the adaptation strength (0: off, 1 and 2: 0.2, 3 to 5: 0.1).
        '';
      };

      harmonyShift = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [
          (macosTrueTone.shiftA or (-294912))
          (macosTrueTone.shiftB or 137626)
        ];
        defaultText = lib.literalExpression "[ profile.display.trueTone.shiftA profile.display.trueTone.shiftB ]";
        description = ''
          The panel's a*b* shift at full strength, DCP's HarmonyShiftA and
          HarmonyShiftB in 16.16 as macOS publishes them (from the profile).
        '';
      };

      nativeWhitePoint = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        example = [
          "0.3127"
          "0.3290"
        ];
        description = ''
          The panel's native white point (CIE x, y), for CoreBrightness's
          native white point correction. macOS takes it from WindowServer,
          which does not publish it; unset, no correction, as for a panel
          whose native white is the D65 macOS profiles it at.
        '';
      };
    };

    hdrOutputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.optional display.experimentalHdr internal;
      defaultText = lib.literalExpression ''lib.optional config.hardware.siliconBakery.display.experimentalHdr "eDP-1"'';
      example = [ "DP-1" ];
      description = ''
        Outputs Silicon Bakery's river drives in HDR (BT.2020 primaries, PQ, 10
        bits; RIVER_HDR_OUTPUTS) when they advertise both. SDR content is
        mapped into it by wlroots. Outputs that do not advertise HDR stay SDR.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = trueTone.enable -> trueTone.tables != null;
        message = "hardware.siliconBakery.display.trueTone.tables: needs apple/truetone.bin from tools/bakery-truetone-tables.";
      }
      {
        assertion = builtins.length trueTone.harmonyShift == 2;
        message = "hardware.siliconBakery.display.trueTone.harmonyShift: two 16.16 integers.";
      }
    ];

    # True Tone's patches go last: their DCP hunk applies on top of the HDR
    # and VRR patches as well as without them.
    boot.kernelPatches =
      lib.optionals display.kernelPatches pkgs.siliconBakery.kernelPatches
      ++ lib.optionals display.experimentalHdr pkgs.siliconBakery.kernelPatchesHdr
      ++ lib.optionals display.experimentalVrr pkgs.siliconBakery.kernelPatchesVrr
      ++ lib.optionals trueTone.enable pkgs.siliconBakery.kernelPatchesTrueTone;

    systemd.services.bakery-truetoned = lib.mkIf trueTone.enable {
      description = "True Tone on the built-in panel";
      wantedBy = [ "multi-user.target" ];
      # The sensor and the panel's DCP come up with their modules; until
      # then the daemon exits and is started again.
      startLimitIntervalSec = 0;
      serviceConfig = {
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe pkgs.siliconBakery.truetone)
            "--tables"
            "${trueTone.tables}/apple/truetone.bin"
            "--mode"
            (toString trueTone.mode)
            "--harmony-shift"
            (lib.concatMapStringsSep "," toString trueTone.harmonyShift)
          ]
          ++ lib.optionals (trueTone.nativeWhitePoint != null) [
            "--native-white"
            (lib.concatStringsSep "," trueTone.nativeWhitePoint)
          ]
        );
        Restart = "always";
        RestartSec = 5;
      };
    };
    boot.kernelParams =
      lib.optional display.experimentalHdr "appledrm.experimental_hdr=1"
      ++ lib.optional display.experimentalVrr "appledrm.experimental_vrr=1";

    environment.sessionVariables =
      lib.optionalAttrs (display.p3Outputs != [ ]) {
        RIVER_DISPLAY_P3_OUTPUTS = lib.concatStringsSep "," display.p3Outputs;
      }
      // lib.optionalAttrs (display.hdrOutputs != [ ]) {
        RIVER_HDR_OUTPUTS = lib.concatStringsSep "," display.hdrOutputs;
      };
  };
}
