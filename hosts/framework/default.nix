# Minimal Framework 13 (AMD 7040) host — tracer-bullet slice (#16).
#
# Composed on top of nixos-hardware's `framework-13-7040-amd` module, which already
# provides fwupd, power-profiles-daemon, the AMD GPU/CPU (`amd_pstate=active`) setup,
# auto-brightness (`hardware.sensor.iio`), and the `amdgpu.dcdebugmask=0x10` kernel
# param. This file adds ONLY what the hardware module doesn't — verify against that
# module before adding any power/GPU/brightness/fwupd option here (issue #15 note).
{ pkgs, ... }:
{
  # --- Boot ---
  # lanzaboote (ADR-0002, #21) replaces systemd-boot. It boots a signed Unified Kernel
  # Image — kernel + initrd + kernel cmdline bundled into one PE binary and signed with
  # OUR OWN Secure Boot keys. This supersedes the earlier temporary systemd-boot stub.
  #
  # systemd-boot is explicitly turned OFF: lanzaboote installs its own stub as the boot
  # entry and the two loaders cannot coexist.
  boot.loader.systemd-boot.enable = false;

  # Custom keys ONLY. We enroll our own sbctl-generated PK/KEK/db with NO shim and NO
  # Microsoft keys (ADR-0002): the 7840U has no MS-signed option ROM to accommodate, so
  # owning the whole key hierarchy is the cleaner, stronger posture. Consequence: media
  # signed only by Microsoft (stock Windows installer, some vendor recovery ISOs) will
  # not boot unless self-signed or SB is temporarily disabled in BIOS for rescue.
  boot.lanzaboote = {
    enable = true;

    # On-device sbctl PKI bundle. The PK/KEK/db key material is generated on the
    # unlocked machine by `sbctl create-keys` and lives here — it is a HARDWARE RITUAL
    # (checklist #24), never committed to the repo. Keeping eval green only requires the
    # path to be declared; the keys need not exist at build time on this Darwin dev box.
    #
    # sops seam (#18, OPEN): once sops-nix lands, the Secure Boot *signing* private key
    # should be provisioned as a sops-nix secret (committed encrypted, decrypted only on
    # the unlocked machine) and pointed at from here per ADR-0002. Until #18 lands we use
    # the plain on-device sbctl bundle so NOTHING secret is fabricated or committed now.
    pkiBundle = "/var/lib/sbctl";
  };

  # Still needed for lanzaboote to write/update the EFI boot entry for the signed UKI.
  boot.loader.efi.canTouchEfiVariables = true;

  # NOTE (handoff reversal): this config assumes Secure Boot is ENROLLED and ON with our
  # keys. This deliberately reverses the old handoff's stale "disable Secure Boot" step —
  # that guidance predates lanzaboote (ADR-0002). Because the kernel cmdline is embedded
  # inside the signed UKI, systemd-stub ignores any externally injected cmdline while SB
  # is on, which closes the classic `init=/bin/sh` and evil-maid-initrd attacks.

  # Pinned-latest kernel (Linux 7.1, cache-backed) — NOT the stable default (6.18).
  # A per-package opt-in on the stable channel, not a switch to unstable (ADR-0001).
  # The 7040 wants a recent kernel for brightness control and power draw.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # --- Networking ---
  networking.hostName = "framework";
  networking.networkmanager.enable = true;

  # --- Power ---
  # power-profiles-daemon is enabled by the framework-13-7040-amd module; we rely on it
  # and NEVER enable tlp (running both fights over the same knobs on AMD Framework).
  #
  # `hardware.framework.amd-7040.preventWakeOnAC` is left unset: the AC-plug-wakes-from-
  # suspend quirk is already fixed upstream in Linux >=6.7, and we run linuxPackages_latest,
  # so enabling it would only cost keyboard-wake for no benefit. Don't "fix" this. (#12)

  # --- Swap ---
  # zram-only swap: a compressed RAM block device, NO disk swapfile and NO
  # `resume_offset`. This preserves the cold-boot posture (ADR-0003) — there is no
  # on-disk swap for the LUKS master key to leak into, and no hibernation image to
  # couple into the signed UKI. The btrfs layout (disko.nix) deliberately carries no
  # swap partition to match.
  zramSwap.enable = true;

  # --- Snapshots ---
  # snapper watches /home ONLY (its own btrfs subvolume, disko.nix). System rollback
  # is NixOS generations' job, so / is not snapshotted here; /nix is a separate
  # subvolume so it is never captured either. Timeline snapshots with automatic
  # cleanup, on the module's default schedule.
  services.snapper.configs.home = {
    SUBVOLUME = "/home";
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
  };

  # --- User ---
  # Real credential handling lands with the sops slice. For now the account is locked
  # ("!" is not a valid hash, so no password authenticates) — no plaintext in the repo.
  users.users.drew = {
    isNormalUser = true;
    description = "Drew Williams";
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "!"; # placeholder — sops slice replaces this with a real hash
    # fish is the interactive login shell (CONTEXT.md). bash stays the scripting shell and
    # is always present regardless. drew's *personal* fish config is home-manager's (home.nix).
    shell = pkgs.fish;
  };

  # System-level: puts fish in /etc/shells (so it is a valid login shell) and wires vendor
  # completions — the "fish exists on this machine" half (a second user could use it, so it
  # is a system concern). Sits here beside the login-shell assignment so all system-level
  # fish wiring is in one place.
  programs.fish.enable = true;

  # Load-bearing minimum for a from-repo rebuild workflow; broader package curation
  # is deliberately deferred (issue #15 out-of-scope).
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Pinned to the install release, then left alone.
  system.stateVersion = "26.05";
}
