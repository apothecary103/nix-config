{
  # Global enabler for the per-project devShells under ../../templates. Entering
  # a directory with an `.envrc` (`use flake`) loads that project's toolchain
  # into scope and drops it on exit, so rust/python/web tooling never lands in
  # the global closure. nix-direnv adds flake-aware caching + GC roots so the
  # shell isn't re-evaluated on every cd.
  flake.modules.homeManager.base.programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true; # suppress the per-directory "direnv: loading" chatter
  };
}
