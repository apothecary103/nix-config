{
  flake.modules.hjem.base =
    { pkgs, ... }:

    {
      rum.programs.mpv = {
        enable = true;

        config = {
          profile = "high-quality";
          vo = "gpu-next";
          # VideoToolbox on darwin; on Asahi the AVD decoder through VA-API
          # (hardware.asahi.avd), which mpv drops back from to software when a
          # codec is unsupported.
          hwdec = if pkgs.stdenv.hostPlatform.isDarwin then "videotoolbox" else "vaapi";

          icc-profile-auto = true;
          target-colorspace-hint = true;

          scale = "ewa_lanczossharp";
          cscale = "ewa_lanczossharp";
          dscale = "hermite";
          deband = true;

          cache = true;
          demuxer-max-bytes = "500MiB";
          demuxer-max-back-bytes = "250MiB";

          video-sync = "display-resample";
          interpolation = true;
          tscale = "oversample";

          alang = "jp,jpn";
          slang = "en,eng";
          demuxer-mkv-subtitle-preroll = true;
        };
      };
    };
}
