{
  description = "DrewOS — Framework 13 (AMD Ryzen 7040) NixOS config";

  inputs = {
    # Stable release track (ADR-0001). Pinned-latest kernel is opted into per-package
    # in the host module, not by switching this to unstable.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      # Only its .nixosModules are consumed, but pin its nixpkgs to ours so the lock
      # doesn't drag in a second (unstable) nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Every input below tracks the one nixpkgs above so the whole closure stays on
    # a single channel with no version drift.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, nixos-hardware, disko, home-manager, lanzaboote, sops-nix, ... }:
    {
      # Single seam: `nixos-rebuild build --flake .#framework`
      # (== `nix build .#nixosConfigurations.framework.config.system.build.toplevel`).
      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nixos-hardware.nixosModules.framework-13-7040-amd
          disko.nixosModules.disko
          # home-manager wired as a NixOS module → user config rides inside the same
          # generation as the system (one rebuild, one rollback). ADR-0004.
          home-manager.nixosModules.home-manager
          # lanzaboote: provides `boot.lanzaboote.*`, replacing systemd-boot with a signed
          # Unified Kernel Image booted under our OWN Secure Boot keys (ADR-0002).
          lanzaboote.nixosModules.lanzaboote
          # sops-nix: provides `sops.*`. Secrets are committed encrypted and decrypted at
          # activation from the host's own SSH key; the admin age key stays off-machine
          # (ADR-0007, CONTEXT.md).
          sops-nix.nixosModules.sops
          ./hosts/framework/disko.nix
          ./hosts/framework/default.nix
          ./hosts/framework/home.nix
          ./hosts/framework/secrets.nix
        ];
      };
    };
}
