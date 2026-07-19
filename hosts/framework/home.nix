# User environment via home-manager wired as a NixOS module (ADR-0004, #19).
#
# home-manager rides inside the system generation (`home-manager.nixosModules.home-manager`
# is imported in flake.nix), so ONE `nixos-rebuild switch` builds system + user config into
# ONE generation with ONE rollback, all inside the same Secure-Boot-signed, TPM-sealed
# generation. `useGlobalPkgs` = share the system's nixpkgs (one channel, no drift);
# `useUserPackages` = user packages install as part of system activation.
#
# Scope now covers the daily-driver userland: terminal, editors, browser, music, and the
# CLI tooling that makes NixOS itself pleasant. The earlier "deferred until COSMIC is
# proven on hardware (#20)" note is discharged.
#
# Application CONFIG is deliberately NOT declared here — only which applications exist.
# nvim ships with no plugins, VS Code's extensions are installed by clicking, Firefox's
# profile is whatever Firefox writes. That is a recorded decision with a rationale and
# consequences, not an omission: see ADR-0006, and the "Declarative boundary" entry in
# CONTEXT.md. The rule it follows is to prefer apps that COULD be declared, then decline
# to declare them yet — so every app below has an unused home-manager module waiting.
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

      # --- Terminal emulator (ghostty) ---
      # Chosen over Alacritty/foot because those have NO native tabs or splits, which
      # forces tmux for multiplexing — and tmux is pure keyboard. That would quietly
      # reintroduce exactly what ADR-0005 picked COSMIC to avoid ("tiling to learn on,
      # never keyboard-only"). ghostty's tabs and splits are mouse-driven, so the trackpad
      # stays a first-class way to move around.
      #
      # Chosen over cosmic-term (which COSMIC already ships) because cosmic-term has no
      # home-manager module: its font and theme could only ever be set by clicking, putting
      # the daily terminal permanently outside the declarative boundary. ghostty's config
      # is left mutable TODAY, but the module exists, so it can be pulled into this repo
      # whenever it stops changing. Option preserved, not exercised (ADR-0006).
      #
      # Safe to live in home rather than system: cosmic-term IS in the system closure, so a
      # failed home-manager activation still leaves a working terminal to repair it from.
      programs.ghostty = {
        enable = true;
        settings = {
          # Must match the family name of the patched font added in default.nix.
          font-family = "JetBrainsMono Nerd Font";
          font-size = 13;
        };
      };

      # --- Editors ---
      # The DAILY editor (CONTEXT.md). Plain nvim: no plugins, no lua config, by choice —
      # plugin management is deferred until taste exists to encode (ADR-0006).
      #
      # viAlias but deliberately NOT vimAlias: `vim` must keep resolving to the system
      # RESCUE editor, the one that still exists when this home profile has failed to
      # activate. Turning on vimAlias would shadow it in drew's PATH and make the two
      # indistinguishable by name — precisely when telling them apart matters most.
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = false;
      };

      # The get-work-done escape hatch — reached for when nvim is costing more time than it
      # is teaching. Extensions and settings stay mutable and in-app ON PURPOSE: an escape
      # hatch that needs a `nixos-rebuild` to install an extension is not an escape hatch.
      # This only works because of `programs.nix-ld.enable` in default.nix — see ADR-0006.
      # Unfree; named in the allowlist in default.nix.
      programs.vscode.enable = true;

      # Browser. Profile, extensions and settings left mutable (ADR-0006); the
      # programs.firefox module is available to take them over later.
      programs.firefox.enable = true;

      # --- Development environment plumbing ---
      # direnv is what makes the third package home from CONTEXT.md ("dev shell") actually
      # usable. Without it, a per-project toolchain means typing `nix develop` on every cd
      # and losing it in every new terminal tab — so the documented rule "per-project
      # toolchains, never global" would quietly lose to just installing things globally.
      # nix-direnv adds caching and GC-root pinning, turning a multi-second stall on every
      # directory change into something instant. The fish hook is wired automatically.
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      # Fixes NixOS's least helpful moment. By default a missing command produces a bare
      # `command not found`, because there is no global bin directory to scan for a
      # suggestion. nix-index builds that database, so the shell can answer "that's in
      # ripgrep". enableFishIntegration installs the fish command-not-found handler.
      programs.nix-index = {
        enable = true;
        enableFishIntegration = true;
      };

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

      # --- Personal userland packages ---
      # Everything here answers "no" to CONTEXT.md's tie-break (would a second user on this
      # laptop need it?), so it lives in home rather than environment.systemPackages.
      #
      # The CLI list was checked against the existing 208-package system closure before
      # being written — every one of these was genuinely absent (only `curl` was already
      # present, which is why it is not repeated here). No GUI file manager, text editor or
      # media player either: COSMIC already ships cosmic-files, cosmic-edit and
      # cosmic-player.
      home.packages = with pkgs; [
        # Music. Unfree; named in the allowlist in default.nix. Audio needs nothing extra —
        # the COSMIC module already enables pipewire (with pulse + alsa) and rtkit.
        spotify

        # `,` — runs a program once from nixpkgs without installing it (`, rg foo`). Pairs
        # with programs.nix-index above: nix-index tells you which package has the command,
        # comma lets you just use it without committing it to this file.
        comma

        # Shell basics.
        ripgrep # rg — fast recursive grep
        fd # friendlier find
        bat # cat with syntax highlighting
        eza # modern ls
        jq # JSON slicing
        btop # process/resource monitor
        tree
        file
        unzip
        wget
      ];

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
