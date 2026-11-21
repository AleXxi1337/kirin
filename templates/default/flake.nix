{
  description = "A NixOS system with kirin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    kirin.url = "github:AleXxi1337/kirin";
  };

  outputs =
    { nixpkgs, kirin, ... }:
    {
      nixosConfigurations.kirin = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          kirin.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
