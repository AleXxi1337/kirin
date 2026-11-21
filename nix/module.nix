# kirin on NixOS: `kirin.enable = true; kirin.user = "name";` is all it
# takes. The module turns on what the shell runs on (Hyprland, sound,
# network, Bluetooth, power, polkit, portals, fonts…) and starts the session
# through greetd; everything it turns on is a default (mkDefault), so the
# system's own config wins wherever it says otherwise.
#
# The shell itself (Quickshell config, Hyprland config) isn't in the store:
# it's the checkout in ~/.kirin, a git repository to change and commit (a
# fork's too: kirin.repo). Each login runs `kirin init` first, which clones
# it if it isn't there (or copies this source, offline), links it into the
# home directory (install/manifest.toml) and makes the default colours.
#
# Compiled parts are built here: Hyprland and the titlebar plugin from
# kirin's own nixpkgs (the plugin must match Hyprland exactly); Quickshell
# and its video module from the system's (the module must match its Qt).
# A plugin of your own from ~/.kirin: `kirin plugins build`.
{ self, nixpkgs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kirin;
  system = pkgs.stdenv.hostPlatform.system;
  upstream = nixpkgs.legacyPackages.${system};
  manifest = builtins.fromTOML (builtins.readFile ../install/manifest.toml);
  attr = name: lib.getAttrFromPath (lib.splitString "." name) pkgs;

  # Sources copied on their own (builtins.path), not as part of kirin's
  # tree: rebuilt only when they change, not with every commit of kirin
  # (a new titlebar plugin means logging out to load it).
  own = name: path: builtins.path { inherit name path; };
  kirinBars = upstream.callPackage ./pkgs/kirin-bars.nix { src = own "kirin-bars-src" ../plugins/bars; };
  kirinVideo = pkgs.callPackage ./pkgs/kirin-video.nix { src = own "kirin-video-src" ../plugins/video; };
  quickshell = pkgs.callPackage ./pkgs/quickshell-multimedia.nix { extraQmlModules = [ kirinVideo ]; };
  kirinCli = pkgs.callPackage ./pkgs/kirin-cli.nix { src = own "kirin-cli-src" ../cli; };

  # The session greetd starts: the checkout and links first (Hyprland reads
  # its config as it starts), then Hyprland. A failed init doesn't keep the
  # session from starting.
  session = pkgs.writeShellScript "kirin-session" ''
    export KIRIN_DIR="$HOME/${cfg.path}"
    export KIRIN_REPO=${lib.escapeShellArg cfg.repo}
    export KIRIN_SOURCE=${self}
    ${kirinCli}/bin/kirin init --session > "''${XDG_RUNTIME_DIR:-/tmp}/kirin-init.log" 2>&1 || true
    exec start-hyprland > /dev/null 2>&1
  '';
in
{
  imports = [
    ./sleep.nix
    ./hibernation.nix
    (import ./update.nix { inherit self; })
  ];

  options.kirin = {
    enable = lib.mkEnableOption "the kirin shell";

    user = lib.mkOption {
      type = lib.types.str;
      description = "The user whose session greetd starts (kirin's lock screen is the login).";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = ".kirin";
      description = "The checkout of kirin, relative to the home directory.";
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/AleXxi1337/kirin.git";
      description = "The repository cloned into kirin.path on the first login (a fork, say).";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      package = upstream.hyprland;
      portalPackage = upstream.xdg-desktop-portal-hyprland;
    };

    # The polkit agent (password prompts for system actions: auto update's
    # switch, mounting…), started by Hyprland (config/hypr/modules/
    # autostart.lua). Packages' libexec isn't linked into the system's
    # profile, so here at a fixed path.
    environment.etc."kirin/polkit-agent".source = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";

    # The titlebar plugin (config/hypr/hyprland.lua loads it).
    environment.etc."kirin/plugins.lua".text = ''
      hl.plugin.load("${kirinBars}/lib/kirin-bars.so")
    '';

    environment.systemPackages = map attr manifest.packages.nixos ++ [
      quickshell
      kirinCli
      (pkgs.callPackage ./pkgs/yaru-sounds.nix { })
      (pkgs.callPackage ./pkgs/papirus-symbolic.nix { })
    ];
    # App symbols for the bar (share/kirin/symbols).
    environment.pathsToLink = [ "/share/kirin" ];

    fonts.packages = map attr manifest.fonts.nixos;
    fonts.fontconfig.defaultFonts = {
      sansSerif = lib.mkDefault [ "Roboto" ];
      monospace = lib.mkDefault [ "JetBrainsMono Nerd Font" ];
      emoji = lib.mkDefault [ "Noto Color Emoji" ];
    };

    # The login: greetd starts the session at once; kirin shows its lock
    # screen, which checks the password through this PAM service.
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${session}";
        user = cfg.user;
      };
    };
    security.pam.services.kirin = { };

    # What the shell talks to.
    security.polkit.enable = true;
    security.rtkit.enable = lib.mkDefault true;
    services.pipewire = {
      enable = lib.mkDefault true;
      alsa.enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
    };
    networking.networkmanager.enable = lib.mkDefault true;
    hardware.bluetooth.enable = lib.mkDefault true;
    services.upower.enable = lib.mkDefault true;
    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.udisks2.enable = lib.mkDefault true;
    services.gvfs.enable = lib.mkDefault true;
    xdg.portal = {
      enable = lib.mkDefault true;
      # File choosers for apps that ask the portal.
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    users.users.${cfg.user}.extraGroups = [ "networkmanager" ];
  };
}
