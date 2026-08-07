{
  flake.modules.homeManager.base = {
    programs.nushell = {
      enable = true;
      shellAliases = {
        cal = "cal --week-start=mo";
      };

      extraConfig = /* nu */ ''
        def git-info []: nothing -> record {
          let root = (^git rev-parse --show-toplevel | complete)
          if $root.exit_code != 0 { return {} }
          let head = (^git branch --show-current | complete | get stdout | str trim)
          {
            root: ($root.stdout | str trim)
            branch: (if ($head | is-empty) {
              ^git rev-parse --short HEAD | complete | get stdout | str trim
            } else { $head })
            dirty: (^git status --porcelain | complete | get stdout | is-not-empty)
          }
        }

        # Truncate every path component to its first character (a leading dot doesn't
        # count), except the current directory and the repo root, which stay whole.
        def shorten-path [repo: string]: string -> string {
          let parts = ($in | split row (char path_sep))
          let last = (($parts | length) - 1)
          let keep = ($parts | enumerate | where item == $repo | get index.0? | default (-1))
          $parts
          | enumerate
          | each {|it|
              if $it.index in [$last $keep] or ($it.item | is-empty) {
                $it.item
              } else if ($it.item | str starts-with ".") {
                $it.item | str substring 0..<2
              } else {
                $it.item | str substring 0..<1
              }
            }
          | str join (char path_sep)
        }

        $env.PROMPT_COMMAND = {||
          let dir = match (do -i { $env.PWD | path relative-to $nu.home-dir }) {
            null => $env.PWD
            "" => "~"
            $relative_pwd => ([~ $relative_pwd] | path join)
          }

          let git = (git-info)
          let short = ($dir | shorten-path ($git.root? | default "" | path basename))

          let path_color = (if (is-admin) { ansi red_bold } else { ansi green_bold })
          let separator_color = (if (is-admin) { ansi light_red_bold } else { ansi light_green_bold })
          let path_segment = ($"($path_color)($short)(ansi reset)"
            | str replace --all (char path_sep) $"($separator_color)(char path_sep)($path_color)")

          let git_segment = if ($git | is-empty) { "" } else {
            $" (ansi blue)($git.branch)(ansi yellow)(if $git.dirty { '*' })(ansi reset)"
          }

          $"($path_segment)($git_segment)"
        }

        $env.PROMPT_COMMAND_RIGHT = ""
      '';
    };

    programs.carapace.enable = true;
  };
}
