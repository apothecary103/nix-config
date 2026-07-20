{ ... }: {

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      setopt PROMPT_SUBST

      function _nushell_left_prompt() {
          local p="''${(%):-%~}"
          local path_color="%B%F{2}"
          local sep_color="%B%F{10}"
        
          if [[ $EUID -eq 0 ]]; then
              path_color="%B%F{1}"
              sep_color="%B%F{9}"
          fi

          local colored_path="''${p//\//$sep_color/$path_color}"
          echo "''${path_color}''${colored_path}%b%f"
      }

      function _nushell_right_prompt() {
          local last_status=$?
          local magenta="%F{5}"
          local green="%F{2}"
          local magenta_ul="%U%F{5}"
          local reset="%u%f"
          local date_str="$(date +'%m/%d/%Y %I:%M:%S %p')"
        
          local time_colored="''${date_str//\//$green/$magenta}"
          time_colored="''${time_colored//:/$green:$magenta}"
          time_colored="''${time_colored//AM/''${magenta_ul}AM}"
          time_colored="''${time_colored//PM/''${magenta_ul}PM}"
          time_colored="''${magenta}''${time_colored}''${reset}"
        
          local exit_code_str=""
          if [[ $last_status -ne 0 ]]; then
              exit_code_str="%B%F{1}''${last_status}%b%f "
          fi
        
          echo "''${exit_code_str}''${time_colored}"
      }

      PROMPT='$(_nushell_left_prompt)%B%F{14}> %b%f'
      PROMPT2='::: '
      RPROMPT='$(_nushell_right_prompt)'

      zstyle ':completion:*' menu select
      # 'ma' sets the Match highlight. 
      # 7 is 'reverse' (swaps fg/bg), or use 48;5;COLOR_CODE for a specific background
      zstyle ':completion:*:default' list-colors "ma=7"
    '';
  };
}
