# Touch ID

Whether the Mac14,9's fingerprint sensor can work under Linux. Read on
2026-11-02 from macOS 27.2's IORegistry and kernel collection (strings and
structure only), Asahi's kernel, m1n1 and documentation. No keys, templates
or Secure Enclave data were read.

## Verdict

Not realistically. The key itself works (macsmc-input reports it as
`KEY_POWER`); the fingerprint does not, and is unlikely to.

## Why

- The sensor (`mesa@0`, `biosensor,mesa`) is an SPI device on the
  application processor's own bus, powered and interrupted through its
  GPIOs, but once powered its traffic with the Secure Enclave (SEP) is
  encrypted with a factory-paired key. The AP relays it and never sees an
  image.
- On macOS the AP-side drivers (AppleBiometricSensor, AppleMesaSEPDriver) do
  much more than relay: power and reset, patch loading, calibration, about a
  hundred commands, and storage of the SEP-encrypted template database. They
  talk to the SEP's `sbio` app, which matches inside the enclave and is tied
  to Apple's keystore, credential manager and anti-replay storage (xART).
- Under Asahi the SEP is put to sleep before Linux; the only SEP code is a
  stub that boots it on M1 laptops for the microphone, and boots seen so far
  expose seven endpoints, none of them `sbio`. On this NixOS the SEP node is
  disabled.
- A Linux implementation would first need the keystore, credential manager
  and xART reimplemented blind (the SEP firmware is encrypted), and writing
  the shared anti-replay storage could break macOS. macOS enrollments cannot
  be reused. Multi-person-years, with a real chance it cannot be done.
  Asahi lists Touch ID as "TBA" for every M2 machine.

## Unlock with a touch, safely

A FIDO2 security key through `pam_u2f`; one with its own fingerprint reader
(YubiKey Bio and the like) is the closest thing to Touch ID, the match
happening inside the key:

```nix
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.pam_u2f ]; # pamu2fcfg
  security.pam.u2f = {
    control = "sufficient"; # key or password
    settings = {
      cue = true;
      origin = "pam://frieren";
      authfile = "/etc/u2f-mappings"; # root-owned
      userverification = 1; # the key's fingerprint (or PIN)
    };
  };
  security.pam.services = {
    swaylock.u2f.enable = true;
    greetd.u2f.enable = true;
  };
  environment.etc."u2f-mappings".text = ''
    <the line pamu2fcfg -u <user> -o pam://frieren -V prints>
  '';
}
```

Register a second key as a backup (`pamu2fcfg -n -o pam://frieren -V`,
appended to the same line). Leave sudo on its password, or use
`control = "required"` there: with "sufficient", a sudo prompt waiting in a
background terminal can be satisfied by a touch meant for something else.
swaylock asks PAM when Enter is pressed, so press Enter on the empty field,
then touch the key. A key without a fingerprint reader works the same
without `userverification`, but proves presence, not identity. An external
USB reader on libfprint's list works through fprintd
(`services.fprintd.enable`, with `enablePam = false` and per-service
`fprintAuth`). Never treat the Touch ID key's press as authentication: it
proves nothing about who pressed it.
