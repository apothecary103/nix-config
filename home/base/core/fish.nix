{ pkgs, ... }:

{
  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    git = true;
    icons = "auto";
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = [ "--cmd cd" ];
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    colors = {
      bg = "-1";
      "bg+" = "-1";
    };
  };

  programs.bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [ batman batgrep ];
  };

  home.sessionVariables = {
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = /* fish */ ''
      set -g fish_greeting ""

      set -g hydro_symbol_start "\n"
      set -g hydro_symbol_prompt ">"
      set -g hydro_color_prompt magenta
      set -g hydro_color_git magenta
      set -g hydro_color_pwd blue
      set -g hydro_color_duration yellow
      set -g hydro_color_error red
      set -g hydro_multiline true
      set -g hydro_cmd_duration_threshold 5000

      set -g fish_cursor_default block
      set -g fish_cursor_insert block
      set -g fish_cursor_replace_one underscore
      set -g fish_cursor_visual block

      function log_history --on-event fish_preexec
          echo "$argv" >> ~/.local/share/fish/full_history
      end

      fish_vi_cursor
    '';

    plugins = [
      {
        name = "hydro";
        src = pkgs.fishPlugins.hydro.src;
      }
    ];
  };
}
