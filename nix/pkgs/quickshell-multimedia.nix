# Quickshell with Qt Multimedia, for kirin's video wallpapers: the
# QtMultimedia QML module and its plugins (FFmpeg backend, hardware decoding
# through VA-API) on the paths Quickshell reads, plus extra QML modules
# (kirin's Kirin.Video). A wrapper, so Quickshell itself isn't rebuilt.
{
  lib,
  symlinkJoin,
  makeWrapper,
  quickshell,
  qt6,
  # Packages with lib/qt-6/qml.
  extraQmlModules ? [ ],
}:
symlinkJoin {
  name = "quickshell-multimedia-${quickshell.version}";
  paths = [ quickshell ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    for bin in qs quickshell; do
      wrapProgram $out/bin/$bin \
        --prefix QML_IMPORT_PATH : ${
          lib.concatMapStringsSep ":" (p: "${p}/lib/qt-6/qml") ([ qt6.qtmultimedia ] ++ extraQmlModules)
        } \
        --prefix QT_PLUGIN_PATH : ${qt6.qtmultimedia}/lib/qt-6/plugins
    done
  '';
  inherit (quickshell) meta;
}
