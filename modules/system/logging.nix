{
  flake.modules.nixos.base = {
    # A crash dump is a full memory image, keys and all, left on disk.
    systemd.coredump.settings.Coredump.Storage = "none";

    # Without a retention policy the journal keeps every SSID, BSSID and USB
    # device ever seen, without bound.
    services.journald.settings.Journal = {
      SystemMaxUse = "512M";
      SystemMaxFileSize = "64M";
      MaxRetentionSec = "1month";
    };
  };
}
