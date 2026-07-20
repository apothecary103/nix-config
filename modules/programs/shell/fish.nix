{
  flake.modules.homeManager.base = { pkgs, ... }: {
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
  };
}
