{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.siliconBakery;
  trackpad = cfg.trackpad;
  profile = cfg.profile;
  bakery = import ../lib { inherit lib; };
  measured = profile.trackpad.measured or { };
  palm = profile.trackpad.palm or null;

  curves = trackpad.curves;
  pointsArg = curve: lib.concatMapStringsSep ";" builtins.toJSON curve.points;
  libinputExe = lib.getExe' trackpad.libinput "libinput";

  # The curve tables in finger units, for reading against macOS.
  table = lib.concatStringsSep "\n" (
    [ "finger mm/s  pointer pt/s  scroll pt/s" ]
    ++
      map
        (
          mm:
          let
            inches = mm / 25.4;
          in
          lib.concatStringsSep "  " [
            (lib.fixedWidthString 11 " " (toString mm))
            (lib.fixedWidthString 12 " " (
              toString (builtins.floor (curves.functions.pointer inches * 1000 + 0.5))
            ))
            (lib.fixedWidthString 11 " " (
              toString (builtins.floor (curves.functions.scrollPixels inches * 1000 + 0.5))
            ))
          ]
        )
        [
          1
          2
          5
          10
          20
          50
          100
          200
          300
          500
          800
        ]
  );

  trackpadTool = pkgs.writeShellApplication {
    name = "bakery-trackpad";
    runtimeInputs = [
      pkgs.gawk
      pkgs.coreutils
    ];
    text = ''
      device() {
        ${libinputExe} list-devices |
          awk -v name=${lib.escapeShellArg profile.trackpad.name} '
            $1 == "Device:" { sub(/^Device: +/, ""); current = $0 }
            $1 == "Kernel:" && current == name { print $2; exit }'
      }
      debug() {
        dev=$(device)
        [ -n "$dev" ] || { echo "no ${profile.trackpad.name} found (libinput list-devices)" >&2; exit 1; }
        exec ${libinputExe} debug-events --device "$dev" --set-profile=custom \
          --set-custom-type="$1" --set-custom-step="$2" --set-custom-points="$3"
      }
      case "''${1:-}" in
        pointer) debug motion ${builtins.toJSON curves.pointer.step} ${lib.escapeShellArg (pointsArg curves.pointer)} ;;
        scroll) debug scroll ${builtins.toJSON curves.scroll.step} ${lib.escapeShellArg (pointsArg curves.scroll)} ;;
        curves) cat <<'EOF'
      ${table}
      EOF
          ;;
        *)
          echo "usage: bakery-trackpad curves | pointer | scroll" >&2
          echo "  curves   what the trackpad's macOS curves do to finger speeds" >&2
          echo "  pointer  libinput debug-events with the pointer curve (needs input access)" >&2
          echo "  scroll   the same with the scroll curve" >&2
          exit 2
          ;;
      esac
    '';
  };

  readOnly =
    type: description: value:
    lib.mkOption {
      inherit type description;
      readOnly = true;
      default = value;
      defaultText = lib.literalMD "from the model's profile";
    };
in
{
  options.hardware.siliconBakery = {
    trackpad = {
      quirks = lib.mkOption {
        type = lib.types.bool;
        default = palm != null;
        description = ''
          libinput quirks with this trackpad's measured touch sizes
          (profiles/<model>/linux.json): libinput's Apple defaults let the base
          of the thumb and grazing touches through.
        '';
      };

      quantisation = lib.mkOption {
        type = lib.types.enum [
          "exact"
          "floor"
        ];
        default = measured.pointerQuantisation or "exact";
        description = ''
          How macOS turns fractional motion into a speed before looking up its
          curve (see lib/macos-accel.nix). Measured by tools/mt-probe; "exact"
          until a measurement says otherwise.
        '';
      };

      scroll = lib.mkOption {
        type = lib.types.attrsOf lib.types.float;
        default =
          if measured ? scrollPixelsPerLine then
            { pixelsPerLine = measured.scrollPixelsPerLine; }
          else
            { slowPixelsPerMM = 5.0; };
        example = {
          pixelsPerLine = 10.0;
        };
        description = ''
          The absolute scroll speed: points per scroll-wheel line as macOS
          renders them ({ pixelsPerLine }), or the slow-speed content travel per
          mm of finger travel with Apple's curve shape kept ({ slowPixelsPerMM }).
          tools/mt-probe measures the former.
        '';
      };

      curves =
        readOnly lib.types.attrs
          ''
            The trackpad's macOS pointer and scroll acceleration as libinput custom
            curves ({ pointer = { step; points; }; scroll = ...; }), for a
            compositor to apply with LIBINPUT_CONFIG_ACCEL_PROFILE_CUSTOM. Speeds are
            in the trackpad's own units per ms, output in logical pixels per ms
            (macOS points at scale 2).
          ''
          (
            bakery.macosAccel {
              inherit profile;
              inherit (trackpad) quantisation scroll;
            }
          );

      libinput = readOnly lib.types.package ''
        libinput with palm rejection by where hands rest, as macOS does it, and
        no wobble hysteresis on Apple trackpads (patches/libinput). Only what a
        compositor is built against picks it up; Silicon Bakery's river is.
      '' pkgs.siliconBakery.libinput;
    };

    keyboard.repeat =
      readOnly lib.types.attrs
        ''
          macOS's key repeat on this Mac: { delay; } in ms before the first repeat
          and { rate; } repeats a second (HIDInitialKeyRepeat and HIDKeyRepeat).
        ''
        {
          delay = builtins.floor (profile.keyboard.initialKeyRepeat / 1000000.0 + 0.5);
          rate = builtins.floor (1.0e9 / profile.keyboard.keyRepeat + 0.5);
        };

    pointer.doubleClick = readOnly lib.types.int ''
      macOS's double-click interval in ms (HIDClickTime).
    '' (builtins.floor (profile.pointer.clickTime / 1000000.0 + 0.5));
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # bakery-trackpad: the curves as numbers, and libinput's own debugger
        # running them on the trackpad, to check on the machine what the
        # compositor applies.
        environment.systemPackages = [ trackpadTool ];
      }

      (lib.mkIf trackpad.quirks {
        # The pad reports pressure in grams with a resolution, so libinput
        # ignores it; size is all there is. A size-based thumb rule cannot
        # help: libinput wants the minor axis under 0.6 of the threshold, and
        # a thumb is too round.
        environment.etc."libinput/local-overrides.quirks".text = ''
          [${profile.model} trackpad, measured]
          MatchUdevType=touchpad
          MatchName=${profile.trackpad.name}
          MatchVendor=0x05AC
          ModelAppleTouchpad=1
          AttrTouchSizeRange=${toString (builtins.elemAt palm.touchSizeRange 0)}:${toString (builtins.elemAt palm.touchSizeRange 1)}
          AttrPalmSizeThreshold=${toString palm.palmSizeThreshold}
        '';
      })
    ]
  );
}
