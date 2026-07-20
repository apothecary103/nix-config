{ ... }:

{
  programs.eza = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = [ "--cmd cd" ];
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultOptions = [ 
      "--color=bg:-1,bg+:-1" 
    ];
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "Catppuccin Macchiato";
    };
  };

  home.sessionVariables = {
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      # 1. Force FZF to use Catppuccin Macchiato globally
      set -gx FZF_DEFAULT_OPTS "--color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 --color=marker:#b7bdf8,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796 --color=selected-bg:#494d64"

      set -g fish_cursor_default block
      set -g fish_cursor_insert block
      set -g fish_cursor_replace_one underscore
      set -g fish_cursor_visual block

      fish_vi_cursor

      set -g fish_color_normal normal
      set -g fish_color_command cyan
      set -g fish_color_keyword cyan --bold
      set -g fish_color_param green --bold
      set -g fish_color_option blue --bold
      set -g fish_color_quote green
      set -g fish_color_escape cyan --bold
      set -g fish_color_operator yellow
      set -g fish_color_redirection magenta --bold
      set -g fish_color_end magenta --bold
      set -g fish_color_error red --bold
      set -g fish_color_valid_path cyan
      set -g fish_color_variable magenta --bold
      set -g fish_color_autosuggestion brblack

      set -g fish_color_selection --reverse
      set -g fish_color_search_match --reverse

      set -g fish_pager_color_progress brwhite --background=brblack
      set -g fish_pager_color_background normal
      set -g fish_pager_color_prefix green --bold
      set -g fish_pager_color_completion normal
      set -g fish_pager_color_description yellow

      set -g fish_pager_color_selected_background --background=brblack
      set -g fish_pager_color_selected_prefix green --bold
      set -g fish_pager_color_selected_completion brwhite
      set -g fish_pager_color_selected_description bryellow

      bind up history-search-backward
      bind down history-search-forward
      bind \e\[A history-search-backward
      bind \e\[B history-search-forward

      bind -M default \r _transient_execute
      bind -M insert \r _transient_execute
    '';

    functions = {
      fish_prompt = ''
        set -l path_color (set_color green --bold)
        set -l sep_color (set_color brgreen --bold)
        set -l prompt_char (set_color cyan)

        if test "$USER" = "root"
          set path_color (set_color red --bold)
          set sep_color (set_color brred --bold)
          set prompt_char (set_color red --bold)
        end

        set -l pwd_str (string replace $HOME '~' $PWD)
        set -l colored_path (string replace -a '/' "$sep_color/$path_color" $pwd_str)

        echo -n -s $path_color $colored_path (set_color normal) $prompt_char '> ' (set_color normal)
      '';

      fish_right_prompt = ''
        # 2. CAPTURE STATUS FIRST! `set -q` overwrites $status immediately.
        set -l last_status $status

        if set -q TRANSIENT_RPROMPT
          return
        end

        set -l magenta (set_color magenta)
        set -l green (set_color green)
        set -l magenta_ul (set_color -u magenta)
        set -l reset (set_color normal)
        set -l date_str (date +'%m/%d/%Y %I:%M:%S %p')

        set -l time_colored (string replace -a '/' "$green/$magenta" $date_str)
        set time_colored (string replace -a ':' "$green:$magenta" $time_colored)
        set time_colored (string replace -a 'AM' "$magenta_ul"AM"$reset$magenta" $time_colored)
        set time_colored (string replace -a 'PM' "$magenta_ul"PM"$reset$magenta" $time_colored)

        set -l exit_code_str ""
        if test $last_status -ne 0
          set exit_code_str (set_color red --bold)"$last_status "(set_color normal)
        end

        echo -n -s $exit_code_str $magenta $time_colored $reset
      '';

      fish_command_not_found = ''
        set -l red (set_color red --bold)
        set -l reset (set_color normal)
        echo -e "$red ✗ $reset Command not found: $red$argv[1]$reset" >&2
      '';

      _transient_execute = ''
        set -l cmd (commandline)
        if test -n "$cmd"
          set -g TRANSIENT_RPROMPT 1
          commandline -f repaint
        end
        commandline -f execute
      '';

      _transient_prompt_reset = {
        onEvent = "fish_postexec";
        body = ''
          set -e TRANSIENT_RPROMPT
        '';
      };

      _transient_prompt_cancel = {
        onEvent = "fish_cancel";
        body = ''
          set -e TRANSIENT_RPROMPT
        '';
      };
    };
  };
}
