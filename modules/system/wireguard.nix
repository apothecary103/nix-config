# Proton VPN. Endpoints and peer public keys are public information and live
# here; the private key comes from agenix (modules/system/agenix.nix). Proton
# issues one private key per "WireGuard configuration" and reuses it across
# every per-server config generated from it, so all interfaces read the same
# file.
#
# The pasted config puts all three servers under one [Interface]. WireGuard
# routes to peers by AllowedIPs, so three peers each claiming 0.0.0.0/0 collide
# and only one is reachable — hence one interface per exit server.
{ lib, ... }:
let
  servers = {
    fi = {
      publicKey = "z0Otc6w9MlvMxpTRMhs125k/FcTTqN5TG8oaQ58K2CI=";
      endpoint = "193.187.151.98:51820";
    };
    jp = {
      publicKey = "lDqI02+FFU6CeisxCSKxVgi28TKT9SowZybo1M4abEU=";
      endpoint = "45.14.71.6:51820";
    };
    hk = {
      publicKey = "giBCbR12im6jWSvwEQ0mJ1PH8NUhRFUDedozBSYC8n4=";
      endpoint = "146.70.113.114:51820";
    };
  };

  address = [
    "10.2.0.2/32"
    "2a07:b944::2:2/128"
  ];

  # Reachable only inside the tunnel, and what NetShield filters on.
  dns = [
    "10.2.0.1"
    "2a07:b944::2:1"
  ];

  allowedIPs = [
    "0.0.0.0/0"
    "::/0"
  ];

  names = map (region: "proton-${region}") (lib.attrNames servers);

  eachServer =
    f: lib.mapAttrs' (region: server: lib.nameValuePair "proton-${region}" (f server)) servers;
in
{
  flake.modules.nixos.base =
    { config, ... }:
    {
      networking.wg-quick.interfaces = eachServer (server: {
        inherit address dns;
        privateKeyFile = config.age.secrets.proton-wireguard.path;
        autostart = false;
        peers = [
          {
            inherit (server) publicKey endpoint;
            inherit allowedIPs;
            persistentKeepalive = 25;
          }
        ];
      });

      # Every peer claims the default route, so two tunnels up at once is a
      # routing conflict rather than redundancy. Starting one therefore has to
      # stop the others; this is what makes switching exit servers a single
      # `systemctl start`.
      systemd.services = lib.genAttrs (map (name: "wg-quick-${name}") names) (unit: {
        conflicts = map (other: "wg-quick-${other}.service") (
          lib.remove (lib.removePrefix "wg-quick-" unit) names
        );
      });

      # wg-quick moves the default route behind an fwmark policy rule, which the
      # strict reverse-path filter's FIB lookup does not reproduce for the
      # inbound encrypted flow — every handshake reply gets dropped.
      networking.firewall.checkReversePath = "loose";

      # NetworkManager natively supports wireguard links and will otherwise
      # adopt netdevs it did not create, racing wg-quick over their addresses,
      # routes and DNS.
      networking.networkmanager.unmanaged = map (name: "interface-name:${name}") names;
    };

  # nix-darwin has no wireguard module, so the same interfaces are hand-written
  # for the wg-quick CLI, which on macOS is a userspace wireguard-go tunnel.
  # `sudo wg-quick up proton-fi` / `down`; unlike systemd there is nothing to
  # enforce that only one is up, and bringing a second up will fail on routes.
  flake.modules.darwin.base =
    { config, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wireguard-tools ];

      environment.etc =
        lib.mapAttrs' (name: text: lib.nameValuePair "wireguard/${name}.conf" { inherit text; })
          (
            eachServer (server: ''
              [Interface]
              Address = ${lib.concatStringsSep ", " address}
              DNS = ${lib.concatStringsSep ", " dns}
              # %i is the utun device wg-quick actually allocated. Referencing the
              # key by path rather than inlining it keeps this file, which /etc
              # exposes as a world-readable store symlink, free of secrets.
              PostUp = ${pkgs.wireguard-tools}/bin/wg set %i private-key ${config.age.secrets.proton-wireguard.path}

              [Peer]
              PublicKey = ${server.publicKey}
              Endpoint = ${server.endpoint}
              AllowedIPs = ${lib.concatStringsSep ", " allowedIPs}
              PersistentKeepalive = 25
            '')
          );
    };
}
