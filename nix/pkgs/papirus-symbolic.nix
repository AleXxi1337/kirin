# Papirus's one-colour (symbolic) icons only, from the theme's repository.
# kirin draws app icons on the bar from them (share/kirin/symbols); the icon
# theme itself stays Colloid.
{
  runCommand,
  fetchFromGitHub,
}:
let
  version = "20250501";
  src = fetchFromGitHub {
    owner = "PapirusDevelopmentTeam";
    repo = "papirus-icon-theme";
    rev = version;
    hash = "sha256-KbUjHmNzaj7XKj+MOsPM6zh2JI+HfwuXvItUVAZAClk=";
  };
in
runCommand "papirus-symbolic-${version}" { } ''
  mkdir -p $out/share/kirin
  # -L: many icons are links to others; copy what they point to.
  cp -rL ${src}/Papirus/24x24/symbolic $out/share/kirin/symbols
''
