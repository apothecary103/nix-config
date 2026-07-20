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
    };
  };
}
