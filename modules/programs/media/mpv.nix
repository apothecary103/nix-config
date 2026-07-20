{
  flake.modules.homeManager.base =
    { ... }:

    {
      programs.mpv = {
        enable = true;

        config = {
          profile = "high-quality";
          vo = "gpu-next";
          hwdec = "videotoolbox";

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
