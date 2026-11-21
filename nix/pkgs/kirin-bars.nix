# kirin-bars: the window titlebars (Hyprland plugin, plugins/bars). Built
# against the Hyprland it's loaded into: a plugin must match it exactly, so
# the module builds it with the same nixpkgs as its Hyprland.
{
  lib,
  stdenv,
  hyprland,
  cmake,
  ninja,
  pkg-config,
  pango,
  cairo,
  src,
}:
(hyprland.stdenv or stdenv).mkDerivation {
  pname = "kirin-bars";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];
  buildInputs = [
    hyprland.dev
    pango
    cairo
  ]
  ++ hyprland.buildInputs;

  meta.platforms = lib.platforms.linux;
}
