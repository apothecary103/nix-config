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

      # --- Minimal Tab UI ---
      # Put the tab bar at the top (change to 'bottom' if preferred)
      set -g status-position top
      set -g status-justify left
      
      # Solid background color for the status bar
      set -g status-style "bg=#1e2030,fg=#cad3f5"

      # Left side empty (no session name)
      set -g status-left ""

      # Right side: Clean clock (Hours:Minutes)
      set -g status-right-length 50
      set -g status-right "#[fg=#a5adce,bg=#1e2030] %H:%M "

      # Inactive Tab: Subtle grey text, matches bar background
      setw -g window-status-format "#[fg=#5b6078,bg=#1e2030] #I #W "
      
      # Active Tab: Bold blue background, dark text
      setw -g window-status-current-format "#[fg=#1e2030,bg=#8aadf4,bold] #I #W#{?window_zoomed_flag, [Z],} "

      # --- Pane & Message Styling ---
      set -g pane-border-style "fg=#363a4f"
      set -g pane-active-border-style "fg=#c6a0f6"
      set -g message-style "bg=#363a4f,fg=#cad3f5,bold"
    '';
  };
}
