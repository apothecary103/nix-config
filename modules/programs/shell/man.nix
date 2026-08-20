{
  # man itself comes from the OS (documentation.man on NixOS, the SDK on
  # darwin); only the pager is the user's business.
  flake.modules.hjem.base.environment.sessionVariables = {
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };
}
