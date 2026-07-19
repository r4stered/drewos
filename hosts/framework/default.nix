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
  # systemd-boot is a TEMPORARY placeholder. It gets swapped for lanzaboote (signed
  # UKI + custom-key Secure Boot, ADR-0002) in the Secure Boot slice. This slice just
  # needs *a* bootloader so the dry-build is honest.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
  };

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
