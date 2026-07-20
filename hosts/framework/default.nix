# Framework 13 (AMD 7040) host module.
#
# Composed on top of nixos-hardware's `framework-13-7040-amd`, which already provides
# fwupd, power-profiles-daemon, the AMD GPU/CPU (`amd_pstate=active`) setup,
# auto-brightness (`hardware.sensor.iio`), and the `amdgpu.dcdebugmask=0x10` kernel
# param. This file adds ONLY what that module doesn't — check it before adding any
# power/GPU/brightness/fwupd option here.
{ config, pkgs, lib, ... }:
{
  # --- Boot ---
  # lanzaboote (ADR-0002) boots a signed Unified Kernel Image — kernel + initrd + cmdline
  # bundled into one PE binary, signed with OUR OWN Secure Boot keys. systemd-boot is
  # explicitly OFF: lanzaboote installs its own boot entry and the two cannot coexist.
  # There is deliberately no fallback loader, so a bad UKI means booting install media.
  boot.loader.systemd-boot.enable = false;

  # Custom keys ONLY — our sbctl-generated PK/KEK/db, no shim, no Microsoft keys
  # (ADR-0002). Consequence: media signed only by Microsoft (stock Windows installer,
  # some vendor recovery ISOs) will not boot unless self-signed or Secure Boot is
  # temporarily disabled in BIOS for rescue.
  boot.lanzaboote = {
    enable = true;

    # The PK/KEK/db material is created by hand on the machine (`sbctl create-keys`,
    # before the first install) and exists ONLY here — not committed, not a sops secret,
    # so it does not survive the disk. CONTEXT.md, "Secure Boot signing key" states the
    # recovery cost; #32 is the work to back it up.
    pkiBundle = "/var/lib/sbctl";
  };

  # Still needed for lanzaboote to write/update the EFI boot entry for the signed UKI.
  boot.loader.efi.canTouchEfiVariables = true;

  # Pinned-latest kernel (Linux 7.1, cache-backed) — NOT the stable default (6.18).
  # A per-package opt-in on the stable channel, not a switch to unstable (ADR-0001).
  # The 7040 wants a recent kernel for brightness control and power draw.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # --- Firmware ---
  # Load-bearing, not a nicety: without linux-firmware amdgpu has no blob to load (COSMIC
  # comes up on a blank panel) and the MT7922 has no Wi-Fi firmware — so the installed
  # system has no network to rebuild itself from. Nothing else sets it: there is no
  # hardware-configuration.nix here (disko.nix supplies the filesystems), and it defaults
  # to false. Enabling it also turns on AMD microcode, which the hardware module defaults
  # *from* this option.
  #
  # Redistributable only: `enableAllFirmware` would pull unredistributable blobs for
  # hardware this laptop lacks, and force a blanket `allowUnfree` onto a config that names
  # its unfree packages one at a time (below).
  hardware.enableRedistributableFirmware = true;

  # --- Disk unlock (LUKS TPM2 + PIN, ADR-0003) ---
  # Declarative half only: the keyslot itself is created out-of-band on the machine
  # (docs/hardware-acceptance.md). Two invariants from ADR-0003 must survive any edit here:
  #
  #   * PIN IS LOAD-BEARING. The TPM authenticates the *platform, not the person*, so a
  #     no-PIN setup would let a stolen, powered-off laptop DECRYPT ITSELF on boot. Never
  #     use platform-only unlock. (Anti-hammering is what lets the PIN stay short.)
  #   * PCR 7 ONLY — never add PCR 0/4/11. PCR 0 breaks on every firmware update; 4/11
  #     break on most rebuilds absent a signed PCR policy. PCR 7 alone enforces "Secure
  #     Boot ON, with our keys" and is stable across kernel and firmware updates.
  #
  # Both fallbacks must always remain: the passphrase keyslot disko created, and the
  # recovery key in the password manager. A firmware update or SB toggle invalidates the
  # TPM keyslot — expected, not a failure — and until cryptenroll is re-run those two are
  # all that stand between Drew and lockout.
  #
  # crypttabExtraOpts requires the systemd initrd. The PCR policy and PIN are baked into
  # the keyslot metadata by cryptenroll, so crypttab only points unlocking at the TPM.
  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices."cryptroot".crypttabExtraOpts = [ "tpm2-device=auto" ];

  # --- Networking ---
  networking.hostName = "framework";
  networking.networkmanager.enable = true;

  # --- Locale ---
  # Santa Cruz, CA. Set explicitly because the NixOS default is UTC and there is no
  # hardware-configuration.nix to carry it. Pinned to a zone rather than left to
  # geoclue/automatic detection: a timezone that silently follows the network makes log
  # timestamps and snapper's timeline snapshots ambiguous after travel. The zone name
  # carries its own DST rules, so this needs no seasonal edit.
  time.timeZone = "America/Los_Angeles";

  # --- Time sync ---
  # Both lines below pin an EXISTING default and record why it is load-bearing; neither
  # turns on anything that was off.
  #
  # timesyncd is already enabled by nixpkgs. `servers` is deliberately left null: null
  # omits `NTP=` and leaves only `FallbackNTP=` (the nixos pool), so a network-supplied
  # NTP server wins when there is one and the pool is merely the backstop — the right
  # trade for a laptop that roams between networks.
  services.timesyncd.enable = true;

  # DON'T FLIP THIS. The option name does not suggest it, but `false` is the only thing
  # keeping the hardware clock updated at all. timesyncd never writes the RTC itself: on a
  # good sync it leaves STA_UNSYNC unset, switching on the kernel's "11-minute mode", and
  # the KERNEL then copies system time into the RTC. timesyncd sets STA_UNSYNC — killing
  # that mode and all RTC writeback — in exactly one case: an RTC in local time, which it
  # cannot reason about across DST. So `true` silently stops the RTC ever being updated.
  #
  # It bites harder here than on most laptops: the cold-boot posture (ADR-0005) means the
  # RTC, not a long-running session, carries time across a great many cold boots, and a
  # drifted clock breaks TLS validity before timesyncd can fix it — on a config whose whole
  # recovery story is "rebuild yourself from the network". Only a Windows dual-boot would
  # tempt this, and this disk has none.
  time.hardwareClockInLocalTime = false;

  # --- Desktop (COSMIC) ---
  # COSMIC over GNOME (ADR-0005): tiling is a per-workspace toggle (Super+Y) with
  # per-window float (Super+G), and it stays MOUSE-FIRST even while tiling — which is the
  # "learn on tiling but never keyboard-only" requirement. GNOME's only real tiling (Pop
  # Shell) is unmaintained and broken on the GNOME 48 that 26.05 ships.
  services.desktopManager.cosmic.enable = true;

  # cosmic-greeter is the login screen. Deliberately NO autologin: a greeter login at
  # every boot is defence-in-depth AFTER the LUKS PIN, and the login password auto-unlocks
  # the COSMIC keyring (ADR-0005).
  services.displayManager.cosmic-greeter.enable = true;

  # NOTE (declarative boundary, CONTEXT.md): COSMIC's tiling/keybind/float defaults and the
  # ~5-minute idle blank+lock are per-SESSION settings — COSMIC's own config under the user
  # profile, not NixOS options — so they cannot be pinned from this file. Mouse-first tiling
  # is COSMIC's native default, so nothing needs overriding to satisfy "never keyboard-only".
  # The idle->poweroff at 20 min IS enforced declaratively below.

  # --- Fingerprint auth (fprintd) ---
  # Genuine opt-in: the framework-13-7040-amd module does NOT set services.fprintd, so
  # nothing here duplicates it. The Framework's Goodix Match-on-Chip sensor is supported by
  # the IN-TREE libfprint, so we do NOT enable services.fprintd.tod — the Touch OEM Driver
  # path is for readers that need an out-of-tree blob, which this one doesn't. Scope is
  # deliberately narrow: login + sudo convenience only. It is NOT commit signing and NOT
  # LUKS unlock — the disk is still unlocked by the TPM+PIN.
  services.fprintd.enable = true;

  # fprintAuth is ADDITIVE: it sits alongside the existing unix/password auth, so PASSWORD
  # FALLBACK IS RETAINED on all four stacks — a failed, slow, or unenrolled fingerprint
  # always falls through to the password and can never lock Drew out. (nixpkgs defaults
  # fprintAuth from services.fprintd.enable; these four are pinned explicitly to document
  # the intended scope rather than rely on the global default.)
  security.pam.services.cosmic-greeter.fprintAuth = true; # graphical login
  security.pam.services.sudo.fprintAuth = true; # privilege escalation
  security.pam.services.polkit-1.fprintAuth = true; # GUI privilege prompts
  security.pam.services.login.fprintAuth = true; # TTY/console fallback

  # --- Power ---
  # power-profiles-daemon comes from the hardware module; NEVER enable tlp alongside it —
  # the two fight over the same knobs on AMD Framework.
  #
  # `hardware.framework.amd-7040.preventWakeOnAC` is left unset deliberately: the
  # AC-plug-wakes-from-suspend quirk is already fixed upstream in Linux >=6.7 and we run
  # linuxPackages_latest, so enabling it would only cost keyboard-wake. Don't "fix" this.
  #
  # Everything below is COLD-BOOT ENFORCEMENT, not comfort tuning. ADR-0005 owns the
  # rationale, the accepted lid-closed hole, and the rejected alternatives — don't soften
  # any of it without reopening that ADR.

  # HARD-MASKED, not soft-disabled: suspend/hibernate become impossible system-wide, so no
  # menu item, keybind, lid action, or package can reach a state that leaves keys in RAM.
  # A soft no-suspend would leave suspend.target reachable, and therefore bypassable.
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybridSleep.enable = false;

  # settings.Login.* freeform form because that is the NON-deprecated shape on 26.05:
  # services.logind.powerKey / lidSwitch are renamed aliases and .extraConfig is removed.
  services.logind.settings.Login = {
    HandlePowerKey = "poweroff"; # the deliberate "keys out of RAM NOW" control
    HandleLidSwitch = "lock"; # instant resume; the accepted hole, closed by IdleAction

    # The compensating control for lid=lock. logind idle is INPUT-idle, so an unattended
    # but silent long job is powered off too unless held awake with `systemd-inhibit`
    # (docs/hardware-acceptance.md, "Day-to-day operations").
    IdleAction = "poweroff";
    IdleActionSec = "20min";
  };

  # --- Swap ---
  # zram-only: a compressed RAM block device, NO disk swapfile and NO `resume_offset`. This
  # preserves the cold-boot posture (ADR-0003) — no on-disk swap for the LUKS master key to
  # leak into, and no hibernation image to couple into the signed UKI. The btrfs layout
  # (disko.nix) deliberately carries no swap partition to match.
  zramSwap.enable = true;

  # --- Snapshots ---
  # snapper watches /home ONLY (its own btrfs subvolume, disko.nix). System rollback is
  # NixOS generations' job, so / is not snapshotted here; /nix is a separate subvolume so it
  # is never captured either.
  services.snapper.configs.home = {
    SUBVOLUME = "/home";
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
  };

  # --- User ---
  # With the default `mutableUsers = true`, NixOS applies a declared password only when it
  # first CREATES the account — so a later `passwd` silently wins and the sops-managed hash
  # quietly stops being the truth. `false` makes every activation re-assert what is declared
  # here, which is what makes "the password is a sops secret" enforced rather than a
  # first-boot default.
  #
  # Real consequence: `passwd` no longer persists across a rebuild — change the password by
  # re-encrypting the hash into secrets/users.yaml. And if that secret ever fails to
  # decrypt, NO password authenticates and cosmic-greeter cannot be passed; recovery is a
  # generation rollback at the boot menu or a chroot from install media
  # (docs/hardware-acceptance.md).
  users.mutableUsers = false;

  # Root has NO password and cannot log in directly ("!" is not a valid hash, so nothing
  # authenticates against it). Administration goes through drew + wheel + sudo. Declared
  # explicitly rather than left implicit because `mutableUsers = false` makes every
  # account's password state a stated fact, and root's should be stated as "locked" on
  # purpose rather than by omission.
  users.users.root.hashedPassword = "!";

  users.users.drew = {
    isNormalUser = true;
    description = "Drew Williams";
    extraGroups = [ "wheel" "networkmanager" ];
    # `hashedPasswordFile` — not `hashedPassword` — because the value must never be a
    # literal in this public repo: NixOS reads the HASH out of the decrypted file at
    # activation, so the repo carries only ciphertext. The secret is marked
    # `neededForUsers` (secrets.nix) so it is decrypted before this account is created.
    hashedPasswordFile = config.sops.secrets.drew_password_hash.path;
    # fish is the interactive login shell (CONTEXT.md). drew's *personal* fish config is
    # home-manager's (home.nix).
    shell = pkgs.fish;
  };

  # System-level: puts fish in /etc/shells (so it is a valid login shell) and wires vendor
  # completions — the "fish exists on this machine" half, which is a system concern because
  # a second user could use it. Sits beside the login-shell assignment above so all
  # system-level fish wiring is in one place.
  programs.fish.enable = true;

  # --- Unfree: a named allowlist, NOT a blanket flag ---
  # DO NOT "simplify" this to `allowUnfree = true`. Naming each package makes adding one a
  # reviewed line in a diff rather than an invisible event — including one pulled in
  # TRANSITIVELY by a dependency you did not choose. Omitting a name produces a BUILD
  # FAILURE naming the package; that failure is the feature.
  #
  # `lib.getName` yields the pname, so match pnames here, not versioned derivation names.
  # NOT the complete inventory of unfree packages on this machine. This option configures
  # the SYSTEM's nixpkgs instance only; the unstable instance imported by the overlay in
  # flake.nix (ADR-0008) carries its own predicate, and claude-code is named there. Two
  # lists, same discipline — check both before concluding nothing else is unfree.
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [
      "vscode"
      "spotify"
    ];

  # --- Fonts ---
  # System-level because cosmic-greeter renders BEFORE any user session, so a home profile
  # cannot supply its fonts (CONTEXT.md's "would a second user need it?" tie-break).
  #
  # ONLY the monospace font. COSMIC already pulls in noto (incl. CJK and colour emoji),
  # dejavu, liberation and open-sans — do not re-add those.
  #
  # The fully-patched Nerd Font over upstream JetBrains Mono + nerd-fonts.symbols-only:
  # symbols-only is tidier but depends on fontconfig fallback resolving in every app, and
  # when it doesn't the failure is silent tofu in one app only. The patched font puts the
  # glyphs in the file — they are either there or not. Costs disk, buys certainty.
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # --- Dynamic linker shim for foreign binaries (nix-ld) ---
  # LOAD-BEARING FOR VS CODE (ADR-0006), not a nicety. VS Code extensions fetch PREBUILT
  # ELF binaries at runtime that expect /lib64/ld-linux-x86-64.so.2 — a path that does not
  # exist on NixOS. Without this they die with `cannot execute: required file not found`,
  # which names neither cause nor fix, so the extension merely appears broken.
  #
  # ADR-0006's choice to leave extensions mutable is only viable because of this option.
  # Removing it means revisiting that ADR, not just this line.
  programs.nix-ld.enable = true;

  # --- Printing (CUPS + mDNS autodiscovery) ---
  # avahi is what makes this useful rather than merely present: without mDNS you must know a
  # printer's IP, and modern printers advertise themselves instead of carrying a documented
  # static one. nssmdns4 wires .local resolution into NSS; the firewall hole is UDP 5353 only.
  services.printing.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # System packages: the load-bearing minimum for a from-repo rebuild workflow. Personal
  # userland lives in home-manager instead — see home.nix and CONTEXT.md, "Package homes".
  environment.systemPackages = with pkgs; [
    git

    # The RESCUE EDITOR (CONTEXT.md), not a leftover: the editor present for root, for a
    # second user, and — the case that matters — when home-manager activation has FAILED
    # and drew's personal userland (including nvim) does not exist. Deliberately never
    # aliased to nvim. Do not remove it when adding a daily editor; they are not redundant.
    vim

    # Secure Boot key management (ADR-0002). lanzaboote signs via `lzbt` at rebuild time
    # and does NOT put sbctl on PATH, so without this `sbctl enroll-keys` is missing on the
    # installed machine. Not only a bring-up tool: `sbctl status` / `sbctl verify` are how
    # you confirm the boot chain after a firmware update or re-enrollment, both expected
    # recurring events (ADR-0003).
    sbctl
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Pinned to the install release, then left alone.
  system.stateVersion = "26.05";
}
