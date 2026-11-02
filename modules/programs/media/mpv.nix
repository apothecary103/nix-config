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
          # (Silicon Bakery's media module), copied back for gpu-next:
          # Honeykrisp imports the decoder's frames zero-copy without error
          # but ignores their plane offset (Mesa #16429), so plain vaapi shows
          # wrong colours rather than falling back. mpv drops to software only
          # for a codec AVD lacks (AV1 on the M2 Pro).
          hwdec = if pkgs.stdenv.hostPlatform.isDarwin then "videotoolbox" else "vaapi-copy";

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
