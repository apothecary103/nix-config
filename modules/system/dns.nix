{
  flake.modules.nixos.base = {
    services.resolved = {
      enable = true;

      settings.Resolve = {
        FallbackDNS = [
          "9.9.9.9#dns.quad9.net"
          "149.112.112.112#dns.quad9.net"
          "2620:fe::fe#dns.quad9.net"
        ];

        # Opportunistic, not strict: strict DoT cannot get through a captive
        # portal, which is exactly where an untrusted resolver shows up.
        DNSOverTLS = "opportunistic";
        DNSSEC = "allow-downgrade";

        # resolved would otherwise broadcast the hostname over responders this
        # machine does not otherwise run.
        LLMNR = "no";
        MulticastDNS = "no";
      };
    };

    networking.networkmanager.dns = "systemd-resolved";
  };
}
