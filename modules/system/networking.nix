{
  flake.modules.nixos.base = {
    # NetworkManager as the connection manager, backed by iwd (rather than the
    # default wpa_supplicant) for Wi-Fi. Setting the backend to "iwd" makes the
    # networkmanager module enable and manage iwd itself, so we don't enable
    # networking.wireless.iwd separately. NetworkManager also drives DHCP, so
    # networking.useDHCP is left off.
    networking.networkmanager = {
      enable = true;
      wifi.backend = "iwd";

      # "stable-ssid" rather than "random": a fake but stable address per SSID
      # keeps DHCP reservations and captive portals working while still showing
      # a different device to every network. Do not set iwd's own
      # General.AddressRandomization alongside this — NetworkManager sets the
      # cloned MAC on the netdev and the two fight, with iwd usually winning and
      # reverting to the hardware address.
      wifi.macAddress = "stable-ssid";
      ethernet.macAddress = "random";

      connectionConfig = {
        "ipv4.dhcp-send-hostname" = false;
        "ipv6.dhcp-send-hostname" = false;
      };
    };

    # NetworkManager pulls this in at mkDefault; there is no WWAN modem, and it
    # probes every serial and USB device for AT commands.
    networking.modemmanager.enable = false;
  };
}
