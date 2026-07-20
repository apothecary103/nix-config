# This file exports an overlay that takes all your custom packages 
# and injects them into the standard Nixpkgs set.

final: prev: {
  # final.callPackage automatically passes dependencies (like stdenv, fetchurl, muvm)
  # to your package derivations.
  
  # You can easily add your other custom packages here as they grow:
  # yaagl = final.callPackage ./yaagl { };
  # teamspeak6-client = final.callPackage ./teamspeak6-client { };
}
