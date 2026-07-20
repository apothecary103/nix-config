{ pkgs, ... }:
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
      cpu
      yank
    ];

    extraConfig = ''
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
      set -g status-style "bg=#1e2030,fg=#cad3f5"

      set -g status-left-length 40
      set -g status-left "#[bg=#c6a0f6,fg=#181926,bold] #S #[bg=#1e2030,fg=#1e2030] "

      setw -g window-status-format "#[fg=#5b6078,bg=#1e2030] #I #W "
      setw -g window-status-current-format "#[fg=#8aadf4,bg=#1e2030,bold] #I #W#{?window_zoomed_flag, [Z],} "

      set -g status-right-length 120
      set -g status-right "#[fg=#8087a2]#{pane_current_command} #[fg=#494d64]• #[fg=#cad3f5]cpu:#{cpu_percentage} #[fg=#494d64]• #[fg=#cad3f5]mem:#{ram_percentage} "

      set -g pane-border-style "fg=#363a4f"
      set -g pane-active-border-style "fg=#c6a0f6"
      set -g message-style "bg=#363a4f,fg=#cad3f5,bold"
      setw -g window-status-activity-style "fg=#eed49f,bg=#1e2030,none"
      setw -g window-status-bell-style "fg=#ed8796,bg=#1e2030,bold"
    '';
  };
}
