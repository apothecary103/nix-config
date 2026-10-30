# Nix values as ZON, the format kwm and kwim read their config.zon in. Lists
# become tuples, attribute sets structs; enum literals and bare numbers such
# as colours are spelled with `enum` and `raw`.
{ lib }:
rec {
  enum = name: { _zon = ".${name}"; };

  raw = text: { _zon = text; };

  # "#rrggbb" and an alpha byte as kwm's 0xRRGGBBAA.
  colour = hex: alpha: raw "0x${lib.removePrefix "#" hex}${alpha}";

  field = name: if builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null then name else ''@"${name}"'';

  render =
    v:
    if lib.isAttrs v && v ? _zon then
      v._zon
    else if lib.isAttrs v then
      ".{ ${lib.concatStrings (lib.mapAttrsToList (k: x: ".${field k} = ${render x}, ") v)}}"
    else if lib.isList v then
      ".{ ${lib.concatMapStrings (x: "${render x}, ") v}}"
    else if lib.isString v then
      builtins.toJSON v
    else if lib.isBool v then
      lib.boolToString v
    else if v == null then
      "null"
    else
      toString v;
}
