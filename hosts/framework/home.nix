# User environment via home-manager wired as a NixOS module (ADR-0004, #19).
#
# home-manager rides inside the system generation (`home-manager.nixosModules.home-manager`
# is imported in flake.nix), so ONE `nixos-rebuild switch` builds system + user config into
# ONE generation with ONE rollback, all inside the same Secure-Boot-signed, TPM-sealed
# generation. `useGlobalPkgs` = share the system's nixpkgs (one channel, no drift);
# `useUserPackages` = user packages install as part of system activation.
#
# Initial scope is git + shell + prompt ONLY. A terminal emulator and the rest of the
# desktop userland are deferred until COSMIC is proven on hardware (#20).
#
# Three package homes (CONTEXT.md): personal userland lives here under home-manager, NOT in
# `environment.systemPackages`. `programs.*.enable` below pull fish/bash/starship/git into
# drew's home profile; the global stdenv is left untouched.
{ ... }:
{
  # This file is purely the home-manager (personal userland) half of the user environment.
  # The system-level fish wiring — login shell + /etc/shells — lives with the account in
  # default.nix, so system concerns and home concerns each stay in one place.
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.drew =
    { config, pkgs, lib, ... }:
    {
      # Pinned to the install release, then left alone (mirrors system.stateVersion).
      home.stateVersion = "26.05";

      # --- Shells + prompt (CONTEXT.md: two shells, two jobs) ---
      # fish is the interactive daily driver (login shell set in default.nix); bash is kept
      # for POSIX scripts and anything expecting `sh` semantics. starship is the cross-shell
      # prompt, so it renders identically in fish and in a dropped-into bash — enabling
      # programs.bash here gives that bash a starship-initialised ~/.bashrc.
      programs.fish.enable = true;
      programs.bash.enable = true;
      programs.starship.enable = true;

      # --- Git + SSH commit signing (decision #14 / ADR-0004) ---
      # Sign every commit and annotated tag with a dedicated on-machine SSH key. The key is
      # generated on first activation (host-key-style, see below), never committed, and is
      # distinct from any push/auth key — the sign and push roles never blur.
      programs.git = {
        enable = true;
        # Freeform gitconfig (this home-manager release folds userName/userEmail/extraConfig
        # into `settings`). Attr paths map straight to gitconfig sections/keys.
        settings = {
          user.name = "Drew Williams";
          user.email = "williams.r.drew@gmail.com";
          # The dedicated commit signing key. Points at the PUBLIC half; ssh finds the private
          # half beside it. Generated on first boot (activation script below), never committed.
          user.signingKey = "${config.home.homeDirectory}/.ssh/id_ed25519_signing.pub";
          commit.gpgsign = true;
          tag.gpgsign = true;
          gpg.format = "ssh";
          # Committed, non-secret list of trusted signer pubkeys → `git log --show-signature`
          # verifies locally. Materialised at a stable path from the repo file (below).
          gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";
        };
      };

      # Materialise the committed allowed_signers at the stable path the git config expects.
      # The pubkey line is filled in during the first-boot bootstrap ritual (#24); until then
      # this is a comment-only placeholder and signatures read as unverified — expected.
      home.file.".config/git/allowed_signers".source = ./allowed_signers;

      # --- Commit signing key: generated on first boot, host-key-style ---
      # Disposable, no sops ceremony (CONTEXT.md "Commit signing key"): if lost, regenerate and
      # re-upload the public half. Idempotent — only generates when absent, never clobbers an
      # existing key. No passphrase; protected at rest by LUKS.
      #
      # LOAD-BEARING CAVEAT (tracked in the #24 acceptance checklist): once the public half is
      # uploaded to GitHub as a Signing key, NEVER delete that old public key from GitHub. SSH
      # signing keys carry no validity window, so removing it reverts all history signed with it
      # to "unverified". Rotating = add the new key, keep the old one forever.
      #
      # The manual half of the bootstrap (upload pubkey to GitHub, paste it into allowed_signers,
      # commit) is the #24 ritual — this only makes the key exist.
      home.activation.generateCommitSigningKey =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          keyPath="$HOME/.ssh/id_ed25519_signing"
          if [ ! -f "$keyPath" ]; then
            run mkdir -p "$HOME/.ssh"
            run chmod 700 "$HOME/.ssh"
            run ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" \
              -C "drewos commit signing key" -f "$keyPath"
          fi
        '';
    };
}
