{
  flake.modules.nixos.base = {
    # A crash dump is a full memory image — session cookies, decrypted messages,
    # whatever pass had open. /var/log is one of the three subvolumes that
    # survive the root wipe, so storing dumps anywhere would quietly undo the
    # point of the ephemeral root.
    systemd.coredump.settings.Coredump.Storage = "none";

    # /var/log is persistent and had no retention policy, so the journal grew
    # without bound and kept every SSID, BSSID and USB device ever seen.
    services.journald.extraConfig = ''
      SystemMaxUse=512M
      SystemMaxFileSize=64M
      MaxRetentionSec=1month
    '';
  };
}
