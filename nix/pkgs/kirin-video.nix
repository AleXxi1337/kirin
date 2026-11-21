# Kirin.Video: kirin's QML module for video wallpapers (one decoder for all
# monitors), from plugins/video. Built with the system's Qt, the
# same Quickshell runs on: a QML plugin must match it exactly.
{
  stdenv,
  cmake,
  ninja,
  qt6,
  src,
}:
stdenv.mkDerivation {
  pname = "kirin-video";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [
    cmake
    ninja
  ];
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
  ];
  # A library, not an app.
  dontWrapQtApps = true;
}
