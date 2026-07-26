{
  flake.modules.nixos.base = {
    services.resolved = {
      enable = true;

      settings.Resolve = {
        DNS = [
          "9.9.9.9#dns.quad9.net"
          "149.112.112.112#dns.quad9.net"
          "2620:fe::fe#dns.quad9.net"
        ];

        # Opportunistic, not strict: strict DoT cannot get through a captive
        # portal, which is exactly where an untrusted resolver shows up.
        DNSOverTLS = "opportunistic";
        DNSSEC = "allow-downgrade";

        # Without this, resolved still prefers the DHCP-supplied resolvers for
        # most names and the DNS/DNSOverTLS settings above do nothing.
        Domains = [ "~." ];

        # resolved would otherwise introduce the link-local responders this
        # machine currently doesn't run at all, broadcasting the hostname.
        LLMNR = "no";
        MulticastDNS = "no";
      };
    };

    networking.networkmanager.dns = "systemd-resolved";
  };
}
