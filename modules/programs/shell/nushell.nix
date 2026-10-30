{
  # The river rice's fish, in nushell: its greeting, vi bindings and
  # `user dir change` prompt, coloured by orchard's nushell port.
  flake.modules.hjem.base =
    { lib, pkgs, ... }:
    {
      rum.programs.nushell = {
        enable = true;

        aliases = {
          cal = "cal --week-start=mo";
        };

        extraConfig = # nu
          ''
            source ${
              pkgs.runCommand "carapace-init-nu" { } ''
                ${lib.getExe pkgs.carapace} _carapace nushell > "$out"
              ''
            }

            $env.config.show_banner = false
            $env.config.edit_mode = "vi"
            $env.config.cursor_shape = { vi_insert: line, vi_normal: block, emacs: line }

            def git-info []: nothing -> record {
              let root = (^git rev-parse --show-toplevel | complete)
              if $root.exit_code != 0 { return {} }
              let head = (^git branch --show-current | complete | get stdout | str trim)
              {
                branch: (if ($head | is-empty) {
                  ^git rev-parse --short HEAD | complete | get stdout | str trim
                } else { $head })
                dirty: (^git status --porcelain | complete | get stdout | is-not-empty)
              }
            }

            # The working copy's change as the rice's fish_jj_prompt shows it, or
            # failing jj, the git branch.
            def vcs-info []: nothing -> string {
              if (which jj | is-not-empty) {
                let jj = (^jj log --no-graph --ignore-working-copy --color=always --revisions @ --template r#'
                  separate(commit_summary_separator,
                    format_short_change_id_with_hidden_and_divergent_info(self),
                    separate(" ",
                      if(self.conflict(), label("conflict", "(conflict)")),
                      if(self.empty(), label("empty", "(empty)")),
                    )
                  )
                '# | complete)
                if $jj.exit_code == 0 and ($jj.stdout | is-not-empty) {
                  return $" ($jj.stdout | str trim)"
                }
              }
              let git = (git-info)
              if ($git | is-empty) { return "" }
              $" (ansi blue)($git.branch)(ansi yellow)(if $git.dirty { '*' })"
            }

            $env.PROMPT_COMMAND = {||
              let user_colour = if $env.LAST_EXIT_CODE == 0 { ansi cyan } else { ansi red }
              let dir = if $env.PWD == $nu.home-dir { "~" } else {
                $env.PWD | path basename | default -e "/"
              }
              $"($user_colour)($env.USER) (ansi cyan)($dir)(vcs-info)(ansi reset)"
            }
            $env.PROMPT_COMMAND_RIGHT = ""
            $env.PROMPT_INDICATOR = " "
            $env.PROMPT_INDICATOR_VI_INSERT = " "
            $env.PROMPT_INDICATOR_VI_NORMAL = " "
            $env.PROMPT_MULTILINE_INDICATOR = "::: "

            if $nu.is-interactive {
              print $"(' ' | fill --width 5)welcome back! (ansi cyan)<3(ansi reset)"
              print ("" | fill --character '─' --width 26)
            }
          '';
      };

      # carapace has no rum module and nushell no autoload directory, so the
      # completer is sourced by hand.
      packages = [ pkgs.carapace ];
    };
}
