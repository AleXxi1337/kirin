# Ubuntu's Yaru sound theme only (share/sounds/Yaru), without the rest of the
# Yaru theme (icons, GTK…, hundreds of MB in nixpkgs' yaru-theme).
{
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation rec {
  pname = "yaru-sounds";
  version = "25.10.3";

  src = fetchFromGitHub {
    owner = "ubuntu";
    repo = "yaru";
    rev = version;
    sparseCheckout = [ "sounds" ];
    hash = "sha256-D76OiIkScXD4OXAgOmcVUGWHt2JxQu8goAj3ivnrrHI=";
  };

  installPhase = ''
    mkdir -p $out/share/sounds/Yaru
    # -L: some sounds are links to others.
    cp -rL sounds/src/stereo $out/share/sounds/Yaru/stereo
    printf '[Sound Theme]\nName=Yaru\nInherits=freedesktop\nDirectories=stereo\n\n[stereo]\nOutputProfile=stereo\n' > $out/share/sounds/Yaru/index.theme
  '';
}
