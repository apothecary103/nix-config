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

          set -g status-position bottom
          set -g status-justify left
          set -g status-style "fg=${palette.text}"
          # Set explicitly: these inherit nothing, so a server carrying a
          # previous theme's values keeps painting a bar background.
          set -g status-left-style default
          set -g status-right-style default
          setw -g window-status-style default
          setw -g window-status-current-style default

          set -g status-left-length 20
          set -g status-left "#[fg=${palette.mauve}] #S  "

          set -g status-right-length 50
          set -g status-right "#[fg=${palette.overlay0}]%H:%M "

          setw -g window-status-format "#[fg=${palette.overlay0}]#I:#W"

          setw -g window-status-current-format "#[fg=${palette.blue}]#I:#W#{?window_zoomed_flag, [Z],}"

          set -g window-status-separator " #[fg=${palette.overlay0}]/#[default] "

          set -g pane-border-style "fg=${palette.surface0}"
          set -g pane-active-border-style "fg=${palette.mauve}"
          set -g message-style "fg=${palette.text},bold"
          set -g message-command-style "fg=${palette.text},bold"
        '';
      };
    };
}
