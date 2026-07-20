{ ... }:

{
  imports = [ ./core ];

  # Yet Another Anime Game Launcher — opt in per game / region here.
  #   "os" Global/HoYoverse | "cn" miHoYo | "both" | null (omit) to skip.
  # The module itself is provided by pkgs/ (see hosts/fern/default.nix).
  yaagl = {
    genshin = "os";
    hsr = "os";
    # zzz = "cn";
  };
}
