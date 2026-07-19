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

  # --- Disk unlock (LUKS TPM2 + PIN, ADR-0003, #23) ---
  # The root LUKS2 container "cryptroot" (declared in disko.nix) is unlocked at boot by
  # the TPM2, sealed to the Secure Boot state, AND gated behind a PIN. This is the
  # declarative half only — the actual keyslot is created on hardware (#24) with:
  #   systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes <dev>
  #
  # PIN is LOAD-BEARING (--tpm2-with-pin). A TPM auto-unlock authenticates the *platform,
  # not the person*: a no-PIN setup would let a stolen, powered-off laptop DECRYPT ITSELF
  # on boot, forfeiting FDE's whole guarantee. The PIN restores "possess the powered-off
  # device, get nothing". The TPM's hardware anti-hammering lets the PIN be short while
  # still resisting brute force. Platform-only / no-PIN unlock must NEVER be used here.
  #
  # PCR 7 ONLY — do NOT add PCR 0/4/11 (ADR-0003):
  #   * PCR 0 breaks on every firmware update (frequent on Framework).
  #   * PCR 4/11 break on most rebuilds unless a signed PCR policy is set up (deferred).
  # PCR 7 alone enforces "Secure Boot ON, with our keys" and is stable across kernel and
  # firmware updates. Combined with the signed UKI (fixed cmdline, bundled initrd) from
  # ADR-0002 this gives evil-maid resistance without brittleness. DO NOT bind more PCRs.
  #
  # Fallbacks (both must always remain):
  #   * The passphrase keyslot disko created stays present (verify, never remove it).
  #   * A high-entropy recovery key lives in the password manager. A TPM re-seal after a
  #     firmware update or a Secure Boot toggle invalidates the TPM keyslot — the
  #     passphrase / recovery key are the ONLY thing standing between Drew and lockout,
  #     after which `systemd-cryptenroll` is re-run to re-bind the TPM.
  #
  # crypttabExtraOpts requires the systemd-based initrd, so we enable it. The PCR policy
  # and PIN requirement are baked into the enrolled keyslot metadata by cryptenroll, so
  # crypttab only needs to point unlocking at the TPM device (`tpm2-device=auto`).
  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [ "tpm2-device=auto" ];

  # --- Networking ---
  networking.hostName = "framework";
  networking.networkmanager.enable = true;

  # --- Desktop (COSMIC) ---
  # COSMIC over GNOME (ADR-0005): a minimal, trackpad-first desktop whose tiling is a
  # per-workspace toggle (Super+Y) with per-window float (Super+G) and which stays
  # MOUSE-FIRST even while tiling (drag tiles/borders, right-click title bars). That lets
  # Drew build tiling/vim fluency without ever losing the trackpad as the primary way to
  # move between windows — the "learn on tiling but never keyboard-only" requirement.
  # GNOME was rejected because its only real tiling (Pop Shell) is unmaintained by System76
  # and broken on the GNOME 48 that 26.05 ships. COSMIC is a first-class module on 26.05.
  services.desktopManager.cosmic.enable = true;

  # cosmic-greeter is the login screen. Deliberately NO autologin — we set no
  # services.displayManager.*.autoLogin. A greeter login is required at every boot as
  # defence-in-depth AFTER the LUKS PIN, and the login password auto-unlocks the COSMIC
  # keyring (ADR-0005). Autologin was rejected: it saves one prompt per boot but breaks
  # keyring auto-unlock and is flaky through cosmic-greeter on 26.05.
  services.displayManager.cosmic-greeter.enable = true;

  # NOTE (declarative boundary): COSMIC's tiling/keybind/float defaults and the ~5-minute
  # idle blank+lock are per-SESSION settings (COSMIC's own config under the user profile),
  # NOT NixOS options, so they cannot be pinned from this file. Mouse-first tiling is
  # COSMIC's native default, so no override is needed to satisfy "never keyboard-only".
  # The idle->poweroff at ~20 min IS enforced declaratively below (Power); the ~5-min
  # blank+lock is left as a session/hardware-checklist item (#24).

  # --- Fingerprint auth (fprintd) ---
  # Genuine opt-in: the framework-13-7040-amd hardware module does NOT set
  # services.fprintd (verified upstream), so nothing here duplicates it. The Framework's
  # Goodix Match-on-Chip sensor is supported by the IN-TREE libfprint, so we do NOT enable
  # services.fprintd.tod — the Touch OEM Driver path is for readers that need an
  # out-of-tree blob, which this one doesn't. Committed UNCONDITIONALLY (not gated on
  # hardware detection); actual enrolment is verified on-hardware in checklist #24.
  # Scope is deliberately narrow: this is login + sudo convenience only. It is NOT commit
  # signing (#19) and NOT LUKS unlock (#5) — the disk is still unlocked by the TPM+PIN.
  services.fprintd.enable = true;

  # Add the fingerprint reader as an ADDITIONAL auth method on exactly the four PAM stacks
  # that matter for login + sudo. fprintAuth is additive: it sits alongside the existing
  # unix/password auth, so PASSWORD FALLBACK IS RETAINED on all four — a failed, slow, or
  # unenrolled fingerprint always falls through to the password and can never lock Drew
  # out. (nixpkgs defaults fprintAuth to services.fprintd.enable, but we pin these four
  # explicitly to document the intended scope rather than rely on the global default.)
  #   - cosmic-greeter: the graphical login (PAM entry created by the COSMIC module above)
  #   - sudo:           fingerprint instead of retyping the password for privilege escalation
  #   - polkit-1:       GUI privilege prompts (COSMIC settings, mounting, etc.)
  #   - login:          the TTY/console login fallback
  security.pam.services.cosmic-greeter.fprintAuth = true;
  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.polkit-1.fprintAuth = true;
  security.pam.services.login.fprintAuth = true;

  # --- Power ---
  # power-profiles-daemon is enabled by the framework-13-7040-amd module; we rely on it
  # and NEVER enable tlp (running both fights over the same knobs on AMD Framework).
  #
  # `hardware.framework.amd-7040.preventWakeOnAC` is left unset: the AC-plug-wakes-from-
  # suspend quirk is already fixed upstream in Linux >=6.7, and we run linuxPackages_latest,
  # so enabling it would only cost keyboard-wake for no benefit. Don't "fix" this. (#12)
  #
  # Everything below here is COLD-BOOT ENFORCEMENT (ADR-0005 / ADR-0003 / CONTEXT.md), NOT
  # comfort tuning. The posture is "the LUKS master key must never sit in POWERED RAM while
  # the laptop is out of Drew's hands", and a security property is enforced by making the
  # bad state structurally unreachable — hence the sleep masking and idle/button poweroffs.

  # Hard-mask every sleep pathway. Keys survive in powered RAM across a suspend, so a
  # suspended laptop is a cold-boot/DMA target — ADR-0003 therefore treats "no suspend, no
  # hibernation" as a security property. Disabling all four systemd sleep targets makes
  # suspend/hibernate IMPOSSIBLE system-wide: no menu item, keybind, lid action, or package
  # can reach a state that leaves keys in RAM. This is the structural guarantee ADR-0005
  # demands over a "soft" no-suspend (which would leave suspend.target reachable, and thus
  # bypassable by a stray keybind or package).
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybridSleep.enable = false;

  # logind power-button / lid / idle behaviour, all as cold-boot enforcement. Written in
  # the settings.Login.* freeform form because that is the NON-deprecated shape on 26.05:
  # services.logind.powerKey / lidSwitch are renamed aliases and .extraConfig is removed,
  # so this keeps eval free of deprecation warnings and puts all logind config in one place.
  services.logind.settings.Login = {
    # Power button -> clean poweroff. The deliberate "keys out of RAM NOW" control: one
    # press returns the machine to a COLD (powered-off) state on demand.
    HandlePowerKey = "poweroff";

    # Lid close -> lock + screen off, but KEEP RUNNING. Chosen for instant resume; this
    # machine is never used clamshell/docked. This is the one accepted hole in the posture
    # (a laptop bagged while running still holds the key in RAM), closed on a delay by the
    # idle->poweroff timer below — its compensating control.
    HandleLidSwitch = "lock";

    # Idle -> poweroff, the compensating control for lid=lock: it automatically returns the
    # machine to a COLD state when Drew walks away or bags it while it is still running, so
    # the key cannot linger in RAM indefinitely. logind idle is INPUT-idle, so a silent
    # unattended long job (a big nixos-rebuild, a download) is also powered off at the
    # timeout unless the machine is kept awake — an accepted consequence (ADR-0005).
    # (The ~5-min blank+lock that precedes this is a COSMIC session setting, not a logind
    # option — see the Desktop NOTE above; logind's single IdleAction can only do one of
    # lock/poweroff, so we spend it on the security-critical poweroff.)
    IdleAction = "poweroff";
    IdleActionSec = "20min";
  };

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
