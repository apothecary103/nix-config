{
  flake.modules.nixos.base = {
    security.sudo = {
      # Makes the setuid binary 0750 root:wheel, so a sudo CVE is only reachable
      # by accounts that could already escalate.
      execWheelOnly = true;

      # 5 minutes rather than sudo's 15: agentic tools run in the same terminals
      # where the ticket is granted.
      extraConfig = ''
        Defaults lecture = never
        Defaults timestamp_timeout = 5
      '';
    };
  };
}
