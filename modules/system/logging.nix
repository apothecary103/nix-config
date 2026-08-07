{
  flake.modules.nixos.base = {
    # A crash dump is a full memory image, and /var/log survives the root wipe,
    # so storing dumps would quietly undo the point of the ephemeral root.
    systemd.coredump.settings.Coredump.Storage = "none";

    # /var/log is persistent, so without a retention policy the journal keeps
    # every SSID, BSSID and USB device ever seen, without bound.
    services.journald.extraConfig = ''
      SystemMaxUse=512M
      SystemMaxFileSize=64M
      MaxRetentionSec=1month
    '';
  };
}
