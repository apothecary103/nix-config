# Only knobs that are additive on aarch64/linux-asahi. Most of what hardening
# guides list is either already set by nixpkgs' kernel common-config
# (dmesg_restrict, init_on_alloc, hardened usercopy, slab freelist hardening) or
# x86-only and silently ignored here (pti, nosmt, microcode, spectre_v2=, ...).
# nixpkgs' hardened profile was removed in 26.05, so this is hand-rolled.
{
  flake.modules.nixos.base = {
    # nohibernate + kexec_load_disabled. Free: swap is a 2G zram/swapfile pair
    # and hibernation was never possible on this machine.
    security.protectKernelImage = true;

    # Additive: upstream defaults SLAB_MERGE_DEFAULT to y.
    boot.kernelParams = [ "slab_nomerge" ];

    boot.kernel.sysctl = {
      "kernel.perf_event_paranoid" = 3;
      "dev.tty.ldisc_autoload" = 0;
      "kernel.sysrq" = 4;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;

      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv4.tcp_rfc1337" = 1;
    };

    # AF_* families are module-autoloaded by any unprivileged socket() call, so
    # these are live local-privilege-escalation surface rather than dormant code
    # (CVE-2017-6074 in DCCP, the TIPC RCEs). hfs/hfsplus are deliberately absent
    # — the macOS half of the dual boot needs them.
    boot.blacklistedKernelModules = [
      "dccp"
      "sctp"
      "rds"
      "tipc"
      "n-hdlc"
      "ax25"
      "netrom"
      "x25"
      "rose"
      "decnet"
      "econet"
      "af_802154"
      "ipx"
      "appletalk"
      "psnap"
      "p8023"
      "p8022"
      "llc"
      "atm"

      "cramfs"
      "freevxfs"
      "jffs2"
      "udf"
    ];
  };
}
