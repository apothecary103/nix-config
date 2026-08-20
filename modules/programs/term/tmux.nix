{
  flake.modules.hjem.base =
    {
      config,
      pkgs,
      palette,
      theme,
      ...
    }:
    {
      packages = [ pkgs.tmux ];

      # tmux has no rum module, so the config file, the plugin and the port are
      # all loaded by hand. The port comes first: its styles are the base that
      # the status line below overrides.
      xdg.config.files."tmux/tmux.conf".text = # shell
        ''
          set -g prefix C-a
          unbind C-b
          bind C-a send-prefix

          set -g base-index 1
          setw -g pane-base-index 1
          set -sg escape-time 0
          set -g history-limit 50000
          setw -g mode-keys vi
          set -g mouse on
          set -g default-terminal "tmux-256color"

          run-shell ${pkgs.tmuxPlugins.yank}/share/tmux-plugins/yank/yank.tmux

          source-file -q ${config.xdg.config.directory}/${theme.tmux.configFile}

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
}
