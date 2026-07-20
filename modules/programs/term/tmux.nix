{
  flake.modules.homeManager.base =
    {
      pkgs,
      palette,
      ...
    }:
    {
      programs.tmux = {
        enable = true;
        shortcut = "a";
        baseIndex = 1;
        escapeTime = 0;
        historyLimit = 50000;
        keyMode = "vi";
        mouse = true;
        terminal = "tmux-256color";

        plugins = with pkgs.tmuxPlugins; [
          yank
        ];

        extraConfig = /* shell */ ''
          set -g window-style "bg=default"
          set -g window-active-style "bg=default"
          set -as terminal-features ",*:RGB"

          set -g display-time 4000
          set -g status-interval 2
          set -g focus-events on
          set-option -g renumber-windows on

          # --- Keybinds ---
          bind-key -T copy-mode-vi v send-keys -X begin-selection
          bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
          bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

          bind r source-file ~/.config/tmux/tmux.conf \; display-message " Modeline reloaded..."

          bind | split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"
          unbind '"'
          unbind %

          bind h select-pane -L
          bind j select-pane -D
          bind k select-pane -U
          bind l select-pane -R

          bind -n S-Left previous-window
          bind -n S-Right next-window

          # --- Statusline ---
          set -g status-position bottom
          set -g status-justify left
          set -g status-style "bg=${palette.mantle},fg=${palette.text}"

          # Left side:
          set -g status-left ""

          # Right side:
          set -g status-right-length 50
          set -g status-right "#[fg=${palette.subtext0},bg=${palette.mantle}] %H:%M "

          # Inactive Tab:
          setw -g window-status-format "#[fg=${palette.surface2},bg=${palette.mantle}] #I #W "

          # Active Tab:
          setw -g window-status-current-format "#[fg=${palette.mantle},bg=${palette.blue},bold] #I #W#{?window_zoomed_flag, [Z],} "

          # --- Pane & Message Styling ---
          set -g pane-border-style "fg=${palette.surface0}"
          set -g pane-active-border-style "fg=${palette.mauve}"
          set -g message-style "bg=${palette.surface0},fg=${palette.text},bold"
        '';
      };
    };
}
