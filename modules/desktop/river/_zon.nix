# Nix values as ZON, the format kwm and kwim read their config.zon in. Lists
# become tuples, attribute sets structs; enum literals and bare numbers such
# as colours are spelled with `enum` and `raw`. One field or element per
# line: kwm's preprocessor reads lines through a 1 KiB buffer.
{ lib }:
rec {
  enum = name: { _zon = ".${name}"; };

  raw = text: { _zon = text; };

  # "#rrggbb" and an alpha byte as kwm's 0xRRGGBBAA.
  colour = hex: alpha: raw "0x${lib.removePrefix "#" hex}${alpha}";

  field = name: if builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null then name else ''@"${name}"'';

  block =
    indent: items:
    if items == [ ] then
      ".{}"
    else
      ".{\n${lib.concatMapStrings (item: "${indent}    ${item},\n") items}${indent}}";

  pretty =
    indent: v:
    if lib.isAttrs v && v ? _zon then
      v._zon
    else if lib.isAttrs v then
      block indent (lib.mapAttrsToList (k: x: ".${field k} = ${pretty "${indent}    " x}") v)
    else if lib.isList v then
      block indent (map (pretty "${indent}    ") v)
    else if lib.isString v then
      builtins.toJSON v
    else if lib.isBool v then
      lib.boolToString v
    else if v == null then
      "null"
    else
      toString v;

  render = v: pretty "" v + "\n";
}
