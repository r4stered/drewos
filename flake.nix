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

    # The ONE deliberate exception to the single-channel rule below: a second nixpkgs,
    # deliberately NOT `follows`-pinned, used through a narrow overlay in the outputs to
    # pull individual LEAF USERLAND TOOLS whose stable version is unusable rather than
    # merely older (ADR-0008). Nothing in the boot, disk, secrets, or system closure may
    # come from here. If you are about to add a second consumer, re-read ADR-0008's
    # boundary first.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Every input below tracks the FIRST nixpkgs above, so every load-bearing part of the
    # closure stays on a single channel with no version drift. That guarantee is what
    # made stable worth choosing (ADR-0001) and still covers everything that can stop the
    # machine booting; ADR-0008 narrowed it to exclude leaf tools only.
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
    { nixpkgs, nixpkgs-unstable, nixos-hardware, disko, home-manager, lanzaboote, sops-nix, ... }:
    let
      system = "x86_64-linux";

      # The ENTIRE blast radius of the second channel (ADR-0008), kept next to the input
      # that creates it: one overlay, listing every package allowed to cross over. Adding
      # a name here is the reviewable event, exactly like the unfree list in default.nix.
      #
      # `nixpkgs-unstable.legacyPackages` is deliberately NOT used: it carries nixpkgs'
      # DEFAULT config, under which claude-code is unfree and evaluation throws. A
      # separately-imported nixpkgs cannot see `nixpkgs.config` from the NixOS module — that
      # option configures the system's instance only — so the named-package discipline from
      # default.nix is repeated here rather than defeated with `allowUnfree = true`.
      unstableLeafTools = _final: _prev: {
        claude-code =
          (import nixpkgs-unstable {
            inherit system;
            config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "claude-code";
          }).claude-code;
      };
    in
    {
      # Single seam: `nixos-rebuild build --flake .#framework`
      # (== `nix build .#nixosConfigurations.framework.config.system.build.toplevel`).
      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.overlays = [ unstableLeafTools ]; }
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
