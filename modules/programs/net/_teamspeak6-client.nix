{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
  makeWrapper,
}:
let
  version = "6.0.0-beta4.1";
in
stdenvNoCC.mkDerivation {
  pname = "teamspeak6-client";
  inherit version;

  src = fetchurl {
    url = "https://files.teamspeak-services.com/pre_releases/client/${version}/teamspeak-client-arm.dmg";
    hash = "sha256-cQf+X1JMLIwoCvf7Ff775B7PtcobbR/pSUNe1UFOfyc=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    undmg
    makeWrapper
  ];

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"

    cp -R "TeamSpeak.app" "$out/Applications/"

    makeWrapper "$out/Applications/TeamSpeak.app/Contents/MacOS/TeamSpeak" "$out/bin/TeamSpeak"

    runHook postInstall
  '';

  meta = {
    description = "TeamSpeak voice communication tool (beta version)";
    homepage = "https://teamspeak.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "TeamSpeak";
  };
}
