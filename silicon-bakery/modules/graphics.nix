{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.siliconBakery;
  graphics = cfg.graphics;

  # The GPU's node in Asahi's device trees, by SoC (the profile's soc, from
  # the GPU's compatible string under macOS).
  gpuNodes = {
    t8103 = "206400000";
    t8112 = "206400000";
    t6000 = "406400000";
    t6001 = "406400000";
    t6002 = "406400000";
    t6020 = "406400000";
    t6021 = "406400000";
    t6022 = "406400000";
  };
  soc = cfg.profile.soc or null;
in
{
  options.hardware.siliconBakery.graphics = {
    mesaPatches = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Mesa with patches/mesa as the runtime graphics driver
        (hardware.graphics.package): Honeykrisp leaving input attachments
        uncompressed, without which wlroots' 10-bit Vulkan scanout flickers a
        border round the panel on G14S (M2 Pro/Max), and the compute barrier
        AGXMetalG14X uses on single-die G14X instead of every known bit. Only
        the driver package changes, so nothing that links Mesa is rebuilt.
      '';
    };

    renderNode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if soc != null && gpuNodes ? ${soc} then
          "/dev/dri/by-path/platform-${gpuNodes.${soc}}.gpu-render"
        else
          null;
      defaultText = lib.literalExpression ''"/dev/dri/by-path/platform-<gpu node>.gpu-render" for the profile's SoC'';
      description = ''
        The GPU's render node, for wlroots (WLR_RENDER_DRM_DEVICE). The panel is
        driven by appledrm, which has no render node, while the GPU is a
        separate asahi device; wlroots hands the display node to the Vulkan
        renderer by default, and no Vulkan device owns it. Buffers still scan
        out on the panel through dmabuf.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics.package = lib.mkIf graphics.mesaPatches pkgs.siliconBakery.mesa;
    environment.sessionVariables = lib.mkIf (graphics.renderNode != null) {
      WLR_RENDER_DRM_DEVICE = graphics.renderNode;
    };
  };
}
