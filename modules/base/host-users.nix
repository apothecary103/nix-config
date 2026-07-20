{ pkgs, lib, hostname, username, ... }:

{
  networking.hostName = hostname;
  networking.computerName = hostname;

  users.users."${username}" = {
    home = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
    description = username;
  } // lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  nix.settings.trusted-users = [ username ];
}
