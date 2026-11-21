{
  description = "kirin: a desktop shell on Hyprland and Quickshell";

  # Hyprland and the titlebar plugin come from here (they must match).
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # kirin.enable = true; kirin.user = "…"; (nix/module.nix)
      nixosModules.default = import ./nix/module.nix { inherit self nixpkgs; };

      packages.${system} = rec {
        kirin-bars = pkgs.callPackage ./nix/pkgs/kirin-bars.nix { src = ./plugins/bars; };
        kirin-cli = pkgs.callPackage ./nix/pkgs/kirin-cli.nix { src = ./cli; };
        default = kirin-cli;
      };

      # nix flake init -t github:AleXxi1337/kirin
      templates.default = {
        path = ./templates/default;
        description = "A NixOS system with kirin";
      };
    };
}
