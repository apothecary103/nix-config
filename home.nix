{ pkgs, username, ... }:

{
  imports = [
    ./modules/home/base.nix
  ] ++ lib.optional pkgs.stdenv.isLinux ./modules/home/nixos.nix
    ++ lib.optional pkgs.stdenv.isDarwin ./modules/home/darwin.nix;
  
  # Home Manager needs a bit of information about you and the paths it should manage.
  home.username = username;
  home.homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  home.stateVersion = "25.11"; 

  # Configure Fonts
  # On macOS, this tells Home Manager to link fonts to ~/Library/Fonts
  fonts.fontconfig.enable = true;

  programs.git = {
    enable = true;
    settings = {
      user = {
        name  = "apothecary";
        email = "113787039+yukariha@users.noreply.github.com";
      };
      init.defaultBranch = "main";
    };
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
    '';
  };

  programs.helix = {
    enable = true;
    defaultEditor = true;
    
    themes = {
      catppuccin_macchiato_transparent = {
        inherits = "catppuccin_macchiato";
        "ui.background" = { bg = "none"; };
      };
    };

    settings = {
      theme = "catppuccin_macchiato_transparent";

      editor = {
        true-color = true;
        line-number = "relative";
        mouse = false;
        cursorline = true;
        bufferline = "multiple";
        default-line-ending = "lf";
        lsp.display-messages = true;
        
        cursor-shape = {
          insert = "bar";
          select = "underline";
        };
        
        file-picker = {
          hidden = false;
          git-ignore = true;
        };

        soft-wrap = {
          enable = true;
        };
      };
    };
  };

  programs.ghostty = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    settings = {
      theme = "Catppuccin Macchiato";
      font-family = "Maple Mono NF CN";
      font-size = 18;

      # macOS specific tweaks
      font-thicken = true;
      macos-titlebar-style = "hidden";
      macos-option-as-alt = true;

      background-opacity = 0.93;
      # background-blur-radius = 50;
      window-padding-x = 20;
      window-padding-y = 20;
    };
  };

  programs.zellij = {
    enable = true;
    settings = {
      pane_frames = false;
      simplified_ui = false;
      default_layout = "compact";
      theme = "catppuccin-macchiato";

      # copy_command = "pbcopy";
      copy_on_select = true;
      scroll_buffer_size = 10000;
      ui = {
        pane_frames = {
          rounded_corners = false;
        };
      };
    };
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
