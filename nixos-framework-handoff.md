# NixOS on Framework 13 (AMD Ryzen 7040) — Implementation Handoff

## Purpose of this document
The user wants to build a **fully declarative, reproducible NixOS configuration in a GitHub repo**, then install NixOS on their laptop by pointing the installer at that repo. This document hands off the context and a concrete implementation plan to the next agent. The user is setting up the empty GitHub repo in parallel while you work.

**Your job:** help the user build out the repo (flake + host config + disko + desktop + secrets), then walk them through the install. Concrete starter code is included below — adapt, don't just paste blindly.

---

## User profile (important for tone/approach)
- Experienced **Arch Linux** user. Technically comfortable — don't over-explain basic Linux concepts.
- **New to NixOS.** The paradigm shift (declarative config, atomic rebuilds, the Nix language) is the real learning curve, not the hardware. Expect to explain "the Nix way" of doing familiar things.
- Wants the reproducibility payoff: *the repo IS the machine.* Rebuild reads it, rollback returns to a prior version of it, reinstall = point the installer at the same URL.

## Preferences established earlier in the conversation
- **Minimal aesthetic**, but NOT a keyboard-only tiling WM. Wants trackpad usability.
- Workflow: **alt-tab / gesture-switch between fullscreen apps**, not tiling everything. Small 13" screen.
- Leaning recommendation was **GNOME** (excellent Wayland trackpad gestures, one-maximized-app-per-workspace workflow, minimal chrome). This is a decision point — see Open Decisions. GNOME is the current default in the starter config below.

---

## Hardware target & key facts
- **Machine:** Framework Laptop 13, **AMD Ryzen 7040 series** mainboard.
- **nixos-hardware module:** `framework-13-7040-amd`
  - flakes: `nixos-hardware.nixosModules.framework-13-7040-amd`
  - channels: `<nixos-hardware/framework/13-inch/7040-amd>`
- **First-party support:** Since April 2025 the NixOS Foundation and Framework officially partner; Framework contributes directly to `nixos-hardware` and `nixpkgs`. This is one of the best-supported laptops on NixOS. There is also an official Framework "NixOS on the Framework Laptop 13" install guide worth referencing.
- **Latest stable NixOS release:** 26.05 (use this or unstable — see decisions).

### 7040-specific quirks to handle (checklist)
- [ ] **Kernel:** use a recent kernel (≥ 6.7, ideally latest). On older release-default kernels users hit missing display-brightness control and higher power draw. Set via `boot.kernelPackages = pkgs.linuxPackages_latest;`
- [ ] **Power management:** use **power-profiles-daemon**, NOT tlp, on the AMD Framework. (`services.power-profiles-daemon.enable = true;` — note the hardware module / GNOME may enable this already; don't double-configure with tlp.)
- [ ] **BIOS ≥ 3.05** for acceptable standby power draw. This is a firmware step for the user, not config. Flag it.
- [ ] **Lid/AC wake quirk:** 7040 series can wake from suspend when AC is plugged in. The hardware module exposes a `preventWakeOnAC` option. Trade-off on older kernels: enabling it disables keyboard wake. Less of an issue on 6.7+. Confirm with user whether they want it.
- [ ] **Fingerprint reader:** supported; check the nixos-hardware README / NixOS wiki for the current enable steps if the user wants it.

---

## Target architecture

Fully flake-based, disk layout declared with **disko**, secrets encrypted with **sops-nix** (or agenix). Install via `nixos-install --flake` from the stock installer ISO, optionally automated end-to-end with **nixos-anywhere**.

### Proposed repo structure
```
.
├── flake.nix              # pins nixpkgs + nixos-hardware + disko + sops-nix; defines the host
├── flake.lock             # generated; commit it (this is what makes it reproducible)
├── hosts/
│   └── framework/
│       ├── default.nix    # host config: imports hw module, desktop, services, packages
│       └── disko.nix       # declarative disk layout (partitions, LUKS, filesystems)
├── modules/               # optional: reusable config split out
└── secrets/               # sops-encrypted secrets (safe to commit when encrypted)
```

### How the "no hardware-configuration.nix" part works
Normally NixOS generates `hardware-configuration.nix` **on the target machine** (`nixos-generate-config`) because it contains disk UUIDs, filesystem layout, and boot kernel modules. **disko removes the filesystem/partition part of that gap** by declaring the disk layout in the repo — partitioning + formatting become declarative. Combined with **nixos-anywhere**, provisioning (partition → format → install) can run in one shot, even over SSH. You still need the small set of boot `kernelModules`/`availableKernelModules`; the `framework-13-7040-amd` module + disko cover the vast majority, so a from-repo install is realistic.

---

## Starter code

> These are starting points sized for a 7040 Framework 13 with an encrypted btrfs-on-LUKS layout and GNOME. Confirm the Open Decisions first, then adapt.

### `flake.nix`
```nix
{
  description = "Framework 13 AMD 7040 NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-hardware, disko, sops-nix, ... }: {
    nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-hardware.nixosModules.framework-13-7040-amd
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./hosts/framework/disko.nix
        ./hosts/framework/default.nix
      ];
    };
  };
}
```

### `hosts/framework/disko.nix` (encrypted btrfs example)
```nix
# Encrypted root: EFI boot partition + LUKS -> btrfs with subvolumes.
# CHANGE `device` to the real disk (e.g. /dev/nvme0n1) before installing.
{
  disko.devices.disk.main = {
    device = "/dev/nvme0n1";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root"  = { mountpoint = "/";        mountOptions = [ "compress=zstd" "noatime" ]; };
                "/home"  = { mountpoint = "/home";    mountOptions = [ "compress=zstd" "noatime" ]; };
                "/nix"   = { mountpoint = "/nix";     mountOptions = [ "compress=zstd" "noatime" ]; };
                "/swap"  = { mountpoint = "/.swapvol"; swap.swapfile.size = "16G"; };
              };
            };
          };
        };
      };
    };
  };
}
```

### `hosts/framework/default.nix`
```nix
{ pkgs, ... }:
{
  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;   # 7040 wants a recent kernel

  networking.hostName = "framework";
  networking.networkmanager.enable = true;

  # --- Framework 7040 power ---
  services.power-profiles-daemon.enable = true;      # NOT tlp on AMD Framework
  # preventWakeOnAC: enable if the AC-plug-wakes-from-suspend quirk bothers the user
  # (option comes from the framework-13-7040-amd hardware module)

  # --- Desktop: GNOME (see Open Decisions) ---
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # --- User (password via sops or hashedPassword, NOT plaintext) ---
  users.users.CHANGEME = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # hashedPassword = "..."; # generate with `mkpasswd -m sha-512`
  };

  environment.systemPackages = with pkgs; [ git vim ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.05";  # set to install release, then DON'T change casually
}
```

---

## Install workflow (two paths)

### Path A — from the machine itself (simplest first time)
1. User sets BIOS: **disable Secure Boot** (F2 at boot → Administer Secure Boot). Also confirm BIOS ≥ 3.05.
2. Boot the stock NixOS installer ISO, get networking up.
3. Apply the disko layout (this partitions + formats + mounts):
   `sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode disko github:USER/REPO#framework` *(or run disko against the local checkout)*
4. Install: `sudo nixos-install --flake github:USER/REPO#framework`
5. Set the user password if not managed by secrets, reboot.

### Path B — nixos-anywhere (fully automated, can run remotely)
- `nix run github:nix-community/nixos-anywhere -- --flake github:USER/REPO#framework root@TARGET_IP`
- Handles disko + install in one shot. Great once the config is proven; good for reinstalls.

Recommend **Path A for the first install** so the user sees each step, then Path B as the "reinstall in one command" payoff.

---

## Secrets — do NOT skip this (Arch habit will bite here)
A public GitHub repo means **no plaintext secrets**.
- **User passwords:** store as hashes — `users.users.<name>.hashedPassword` (generate with `mkpasswd -m sha-512`), or manage via sops.
- **Real secrets** (SSH keys, API tokens, wifi PSKs): use **sops-nix** (in the starter flake) or **agenix**. Encrypted files live in the repo and are decrypted at activation time.
- Set up the sops age key / recipient before the first secret-bearing rebuild.

---

## Open decisions to confirm with the user before finalizing
1. **Exact disk device** — `/dev/nvme0n1` assumed. Confirm the real device name on the machine (`lsblk`).
2. **Disk encryption?** — starter uses LUKS full-disk encryption. Confirm they want it (recommended for a laptop) and how they want to unlock (passphrase; TPM/secure-boot auto-unlock is a later enhancement).
3. **Filesystem** — btrfs w/ subvolumes assumed (pairs well with NixOS + snapshots). ext4 is simpler if they prefer.
4. **Desktop** — GNOME defaulted per earlier discussion. Confirm vs. alternatives raised (elementary/Pantheon, COSMIC). If GNOME, decide on the Pop Shell extension for optional tiling.
5. **nixpkgs channel** — 26.05 stable vs nixos-unstable (unstable gets newer kernels/GNOME faster, relevant for fresh hardware). 
6. **Secrets tool** — sops-nix (defaulted) vs agenix.
7. **preventWakeOnAC** — on or off?
8. **Home management** — do they want `home-manager` for dotfiles/user config in the same flake? (Recommended given the "repo is the machine" goal; not yet included in starter.)

---

## Suggested implementation sequence
1. Confirm the Open Decisions above.
2. Scaffold repo: `flake.nix`, `hosts/framework/{default,disko}.nix`.
3. `nix flake lock` to generate + commit `flake.lock`.
4. Add `home-manager` if wanted; wire the desktop + packages.
5. Set up sops-nix + at least the user password hash.
6. Dry-build to catch errors before touching the laptop: `nix build .#nixosConfigurations.framework.config.system.build.toplevel` (or `nixos-rebuild build --flake .#framework` on a NixOS host).
7. First install via Path A. Verify quirks checklist (brightness, suspend, power draw, wifi, trackpad gestures, fingerprint if wanted).
8. Once stable, demonstrate Path B (nixos-anywhere) as the reproducible reinstall path.

## Verification checklist post-install
- [ ] Boots to GNOME (or chosen desktop), user can log in
- [ ] Display brightness keys work (kernel sanity check)
- [ ] Suspend/resume clean; AC-plug behavior as desired
- [ ] Idle/standby power draw reasonable (BIOS ≥ 3.05)
- [ ] Wifi + trackpad gestures working
- [ ] `nixos-rebuild switch --flake` from the repo works and a rollback boot entry exists
- [ ] Secrets decrypt at activation (no plaintext in repo)
