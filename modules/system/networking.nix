{
  flake.modules.nixos.base = {
    # The "iwd" backend makes the networkmanager module enable and manage iwd
    # itself, so networking.wireless.iwd stays off. NetworkManager also drives
    # DHCP, so networking.useDHCP is left off.
    networking.networkmanager = {
      enable = true;
      wifi.backend = "iwd";

      # Stable per SSID, so DHCP reservations and captive portals keep working.
      # Do not set iwd's own General.AddressRandomization alongside this —
      # NetworkManager sets the cloned MAC on the netdev and iwd usually wins,
      # reverting to the hardware address.
      wifi.macAddress = "stable-ssid";
      ethernet.macAddress = "random";

      connectionConfig = {
        "ipv4.dhcp-send-hostname" = false;
        "ipv6.dhcp-send-hostname" = false;
      };
    };

    # Pulled in by NetworkManager at mkDefault. There is no WWAN modem, and it
    # probes every serial and USB device for AT commands.
    networking.modemmanager.enable = false;
  };
}
