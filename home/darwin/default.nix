{ ... }:

{
  imports = [ ./yaagl.nix ];

  # Yet Another Anime Game Launcher — opt in per game / region here.
  #   "os" Global/HoYoverse | "cn" miHoYo | "both" | null (omit) to skip.
  yaagl = {
    genshin = "os";
    hsr = "os";
    # zzz = "cn";
  };
}
