# Hardware Acceptance Checklist

The manual seam. A `nixos-rebuild dry-build` proves the config *evaluates*; it
cannot prove that Secure Boot enrolls, the TPM unlocks, a finger reads, a commit
signs, or a secret decrypts on **this** physical Framework 13. Those are
hardware-and-firmware facts, established once, by hand, on the machine. This is
the ritual Drew runs to sign off that the laptop actually *is* the machine the
repo describes.

> **Read the run-book straight through before you start.** This document is
> ordered, and the order is load-bearing — several steps are impossible if done
> out of sequence, and two of them (the sbctl keys, the LUKS fallbacks) cannot be
> retrofitted after the fact without a reinstall or a lockout. The per-subsystem
> sections further down are *detail and recovery*, not an alternative sequence.

> **Posture note — this doc follows the ADRs, not the old handoff.** Two steps
> from the original project handoff are **reversed** here and the old wording is
> dead:
> - Desktop is **COSMIC**, not GNOME. ([ADR-0005](adr/0005-cosmic-desktop-cold-boot-power.md))
> - Secure Boot is **enrolled with our own keys and turned ON**, *not* disabled.
>   Anywhere the handoff says "disable Secure Boot", read "enroll our keys and
>   enable it". ([ADR-0002](adr/0002-custom-key-secure-boot-via-lanzaboote.md))

---

## Why the ordering is what it is

Four constraints fix the sequence. Every one of them has a failure mode that is
silent, expensive, or both.

1. **sops cannot bootstrap itself.** A secret is only decryptable by a key that
   was a *recipient at encryption time*. The host key must exist, and
   `.sops.yaml` must already list it, **before the first activation** — a key
   generated during activation is already too late.
2. **lanzaboote cannot bootstrap itself either, for the same shape of reason.**
   `boot.lanzaboote.enable = true` and `systemd-boot.enable = false` are set from
   the very first install, so `nixos-install` signs the Unified Kernel Image at
   install time and needs the `db` key *then*. The sbctl bundle must therefore be
   created into the target root **before `nixos-install`**, exactly like the host
   ssh key. You cannot create it "on the booted machine" — without it there is no
   bootable machine.
3. **Signing and enrolling are separable.** A signed UKI boots perfectly well with
   Secure Boot still **off**. So the first boot happens with SB off, and key
   enrollment (which needs BIOS Setup Mode) happens afterwards, from a system you
   have actually seen come up.
4. **PCR 7 measures the *final* Secure Boot state.** So the LUKS TPM keyslot is
   enrolled **last** — after keys are enrolled, after SB is switched on, and after
   any firmware update. Enroll it earlier and it binds to a PCR 7 that is about to
   change, and the TPM unlock breaks on the next reboot.

The one-line version: **keys before install, boot before enroll, TPM last.**

---

## Before you start

**Install media: the graphical NixOS 26.05 ISO** (`nixos-26.05-x86_64-linux.iso`),
not the minimal one. This is a deliberate choice. Phase B moves credentials in
both directions across machines — a LUKS passphrase *out* of the password manager,
a recovery key and an age recipient *in* — and the recovery key is a last-resort
credential where a silent transcription typo is permanent data loss. The graphical
ISO gives you a browser for the password manager, a Wi-Fi GUI, and a terminal with
scrollback. Hand-copying a recovery key off a bare console is the one place in this
whole ritual worth spending 2GB of ISO to avoid.

**Flakes in the installer.** The live ISO does not enable them by default:

```
nix --extra-experimental-features 'nix-command flakes' ...
```

**Long jobs must be inhibited.** [ADR-0005](adr/0005-cosmic-desktop-cold-boot-power.md)
sets `IdleAction = "poweroff"` at `IdleActionSec = "20min"`, and logind idle is
**input**-idle — not CPU-idle. A 40-minute build with your hands off the trackpad
powers the machine off mid-build. This is a stated, accepted trade-off of the
cold-boot posture, and the config is deliberately **not** weakened for bring-up.
Wrap long commands instead:

```
systemd-inhibit --what=idle:shutdown:sleep --why="bring-up build" \
  sudo nixos-rebuild switch --flake github:r4stered/drewos#framework

systemd-inhibit --what=idle:shutdown --why="fwupd flash" \
  fwupdmgr update

systemd-inhibit --list      # what is currently holding things off
```

This matters most during `fwupdmgr update`: an idle poweroff part-way through a
firmware flash is a bricking scenario, not an inconvenience.

**Confirm the disk device.** `hosts/framework/disko.nix` hardcodes
`device = "/dev/nvme0n1"`. On a single-NVMe Framework 13 that is correct, but
**verify with `lsblk` before running disko** — disko will destroy whatever is at
that path. If it differs, you must commit and push a corrected `disko.nix` before
installing, because the install pulls the config from GitHub rather than from a
local file.

---

## Top-level checklist

- [ ] **Firmware/config merged to `main`** — the install pulls the default branch
- [ ] **LUKS fallbacks:** passphrase keyslot *and* recovery key both in the password manager, enrolled in the installer
- [ ] **Secrets (sops):** host key generated *before* the first install, both recipients in `.sops.yaml`, secrets decrypt at activation, no plaintext in the repo
- [ ] **Secure Boot:** sbctl bundle created *before* install; our keys enrolled (no `--microsoft`), SB ON in BIOS, signed UKI boots
- [ ] **BIOS firmware ≥ 3.05** confirmed (fingerprint reader depends on it)
- [ ] **LUKS TPM+PIN:** enrolled to PCR 7 + PIN **last**, unlocks at boot
- [ ] **Fingerprint:** `lsusb` shows `27c6:609c`, firmware current, `fprintd-enroll` succeeds
- [ ] **Fingerprint gating:** cosmic-greeter login and `sudo` accept a finger; password fallback still works
- [ ] **Commit signing:** key generated by activation, **public** half uploaded to GitHub as a *Signing key*, pasted into `hosts/framework/allowed_signers`, committed
- [ ] **Brightness keys** change the panel backlight
- [ ] **Wi-Fi** connects via NetworkManager
- [ ] **COSMIC trackpad gestures + fractional scaling** feel right on the 13" panel *(research-#5 gap — validate here)*

---

# The run-book

## Phase A — on the dev machine, before touching the laptop

> **Already done as of #18 — skip to Phase B.** `.sops.yaml` carries a real admin
> recipient and `secrets/users.yaml` is committed as ciphertext, so Phase A is
> recorded here for the *re-do* cases (a lost admin age key, a password change, a
> fresh start), not as pending work. Do **not** run step A1 again on the current
> setup: a new admin age key cannot decrypt the already-committed ciphertext, and
> the `sops updatekeys` in Phase B would then fail with nothing able to re-key it.

**A1. Generate the admin age key.** Print it to the terminal; do *not* write it to
a file on a machine that isn't encrypted at rest:

```
nix shell nixpkgs#age -c age-keygen
```

Put the `AGE-SECRET-KEY-1…` line in the **password manager** immediately, and the
`# public key: age1…` line into `.sops.yaml` as the admin recipient. The private
half must never land on the laptop or in the repo. **This is the one key whose
loss is unrecoverable** — a reinstalled laptop is re-keyed *from* this key, so
without it every committed secret is permanently unreadable.

**A2. Generate the password hash.** yescrypt, and note it is a *hash* — the
plaintext password never leaves your head:

```
nix shell nixpkgs#mkpasswd -c mkpasswd -m yescrypt
```

**A3. Encrypt it.** With the admin key in the environment:

```
read -rs SOPS_AGE_KEY && export SOPS_AGE_KEY
nix shell nixpkgs#sops -c sops secrets/users.yaml
```

The editor opens on a new file; the single key it must contain is:

```yaml
drew_password_hash: $y$j9T$…the mkpasswd output…
```

Save, then confirm the file on disk is ciphertext (`grep drew_password_hash
secrets/users.yaml` should show an `ENC[…]` value, not the hash). Commit it.

**A4. Merge to `main`.** The install command pulls the **default branch**, so
whatever is on `main` is what the laptop becomes. Confirm `main` carries the
firmware fix, the sops slice, and this document before you boot the ISO.

- [ ] Admin age key generated, private half **in the password manager only**
- [ ] `secrets/users.yaml` committed as ciphertext, password hash inside
- [ ] `main` is the config you actually intend to install

---

## Phase B — in the installer, before `nixos-install`

Everything in this phase is "things that must exist before the first activation".
Do it in order.

**B0. Generate the LUKS passphrase in the password manager — first, before disko.**
High-entropy, generated and *saved* before you need to type it. disko is about to
prompt for it, and it becomes **keyslot 0**: the only way into the disk until the
recovery key exists, and the fallback that ADR-0003's whole recovery story rests
on (`default.nix`: *"the passphrase keyslot disko created stays present — verify,
never remove it"*).

**B1. Partition, format, and mount** — verify the device with `lsblk` first:

```
lsblk
nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko -- \
  --mode destroy,format,mount \
  --flake github:r4stered/drewos#framework
```

`disko.nix` sets no `passwordFile` and no `settings.keyFile`, so disko's
`askPassword` defaults to true and **it will prompt interactively**. Paste the
passphrase from B0. The target root ends up mounted at `/mnt`.

**B2. Enroll the recovery key immediately — do not defer this.** This is the second
independent fallback, and enrolling it now closes the window in which a single
forgotten passphrase is total, unrecoverable data loss:

```
sudo systemd-cryptenroll --recovery-key /dev/nvme0n1p2
```

It prints the recovery key **once**. Put it in the password manager before you
press another key. You now have two fallbacks (keyslots 0 and 1) on disk, before
the machine has ever booted and long before the TPM is involved.

**B3. Generate the host ssh key into the target root.** This is the key the machine
will decrypt secrets with, and `/mnt/etc/ssh` is on the LUKS-encrypted root:

```
mkdir -p /mnt/etc/ssh
ssh-keygen -t ed25519 -N "" -f /mnt/etc/ssh/ssh_host_ed25519_key
```

No sshd is or will be running — we want the key, not the server.
`hosts/framework/secrets.nix` explains at length why this is not auto-generated.

**B4. Generate the Secure Boot PKI bundle into the target root.** Same shape as B3
and for the same reason: `nixos-install` will sign the UKI with the `db` key from
this bundle, so it has to exist *now*.

```
nix --extra-experimental-features 'nix-command flakes' \
  shell nixpkgs#sbctl -c sbctl create-keys --database-path /mnt/var/lib/sbctl
```

> **Verify the flag on the machine.** This was written against sbctl `0.18` but
> not exercised — sbctl is Linux-only and could not be run from the macOS dev box.
> Run `sbctl --help` first. If `--database-path` is not accepted on your build, get
> the same result with a bind mount, which works regardless of flag support:
> ```
> mkdir -p /mnt/var/lib/sbctl /var/lib/sbctl
> mount --bind /mnt/var/lib/sbctl /var/lib/sbctl
> nix shell nixpkgs#sbctl -c sbctl create-keys
> ```
> Either way, confirm `ls /mnt/var/lib/sbctl` shows key material before continuing.
> **Do not enroll the keys yet** — that happens in Phase C, from a booted system.

**B5. Convert the host public key to an age recipient:**

```
nix --extra-experimental-features 'nix-command flakes' \
  shell nixpkgs#ssh-to-age -c ssh-to-age -i /mnt/etc/ssh/ssh_host_ed25519_key.pub
```

This prints an `age1…` line. It is a **public** recipient — non-secret, safe to
copy by hand, screenshot, or paste into a message to yourself.

**B6. Re-key, back on the dev machine** (this needs the admin private key, which
stays on the one trusted machine). Uncomment the host recipient in `.sops.yaml`,
paste in the `age1…` from B5, then:

```
read -rs SOPS_AGE_KEY && export SOPS_AGE_KEY
nix shell nixpkgs#sops -c sops updatekeys secrets/users.yaml
```

`updatekeys` re-encrypts the existing secret to the *new* recipient list — this is
the admin key doing the one job it exists for. Commit and push **to `main`**.

Confirm it took: the build-time warning in `secrets.nix` should now be gone, and
`secrets/users.yaml` should carry two `recipient:` lines.

**B7. Install**, pulling the just-pushed commit:

```
systemd-inhibit --what=idle:shutdown:sleep --why="nixos-install" \
  nixos-install --no-root-passwd --flake github:r4stered/drewos#framework
```

`--no-root-passwd` because root is declaratively locked (`users.users.root.hashedPassword = "!"`)
and `users.mutableUsers = false` would discard anything the prompt collected anyway.

- [ ] LUKS passphrase generated **before** disko, in the password manager
- [ ] Recovery key enrolled in the installer and saved (keyslots 0 **and** 1 exist)
- [ ] Host key at `/mnt/etc/ssh/ssh_host_ed25519_key` **before** install
- [ ] sbctl bundle at `/mnt/var/lib/sbctl` **before** install
- [ ] `.sops.yaml` lists **both** recipients; `sops updatekeys` run, committed, pushed to `main`

---

## Phase C — first boot

Secure Boot is still **off** at this point and that is expected; the signed UKI
boots fine without it. Unlock with the passphrase from B0.

**C1. Verify the secret decrypted — do this first, while install media is still to
hand.** This is the step with no earlier generation to roll back to:

```
sudo ls -l /run/secrets-for-users/drew_password_hash
```

Then confirm the password actually authenticates: log in at cosmic-greeter, and
`sudo -k && sudo true`. A decryption failure surfaces as an activation error
naming `sops-install-secrets`; the usual cause is B6 having been skipped, so the
ciphertext has no recipient this machine holds. See *Recovery* below.

**C2. Network.** Connect Wi-Fi via NetworkManager (`nmcli device wifi connect …`
or the COSMIC applet) and confirm it survives a reboot. This also implicitly
confirms the MT7922 firmware landed — the `hardware.enableRedistributableFirmware`
fix in `default.nix`. If Wi-Fi is dead here, that is the first thing to check.

**C3. Enroll Secure Boot keys and turn SB on.** Detail in the *Secure Boot* section
below. Summary: BIOS → Setup Mode, `sudo sbctl enroll-keys` (no `--microsoft`),
`sudo sbctl verify`, BIOS → Secure Boot ON, reboot, confirm with `bootctl status`.

**C4. Update firmware — before the TPM, not after.** Firmware updates shift PCR 7,
so doing this after TPM enrollment would immediately invalidate the keyslot. Also
needed to get the fingerprint reader to ≥ 3.05:

```
fwupdmgr refresh && fwupdmgr get-updates
systemd-inhibit --what=idle:shutdown --why="fwupd flash" fwupdmgr update
```

**C5. Enroll the LUKS TPM keyslot — last.** PCR 7 is only settled now that keys are
enrolled, SB is on, and firmware is current. Detail in the *LUKS* section below.

**C6. Enroll a finger.** Detail in the *Fingerprint* section below.

**C7. Bootstrap commit signing.** Detail in the *Commit signing* section below.

---

# Per-subsystem detail and recovery

## Secure Boot — enroll our keys, enable, confirm signed-UKI boot

*Relates to slice #21 (lanzaboote). See [ADR-0002](adr/0002-custom-key-secure-boot-via-lanzaboote.md).*

We own the entire key hierarchy: `sbctl`-generated PK/KEK/db, **no shim, no
Microsoft keys**. lanzaboote signs a Unified Kernel Image (kernel + initrd +
cmdline bundled) with the `db` key so the firmware will run it.

The bundle was already created in **B4** — that is what let `nixos-install`
produce a signed UKI at all. What remains is enrollment, which needs a booted
system and a BIOS action.

1. Put the BIOS into **Setup Mode** (clear/reset the existing Secure Boot keys in
   the BIOS security menu) so custom keys can be enrolled.
2. Enroll **our keys only** — deliberately *without* `--microsoft`:
   ```
   sudo sbctl enroll-keys
   ```
   `sbctl` will demand an explicit acknowledgment because omitting the Microsoft
   keys can brick boards with an MS-signed option ROM. This board (7840U,
   integrated GPU) has none, so it is safe here.
3. Confirm the boot image is signed and check status:
   ```
   sudo sbctl verify     # UKI(s) under /boot/EFI should show "signed"
   sbctl status
   ```
4. **Turn Secure Boot ON** in the BIOS and save.
5. Reboot. Confirm the signed UKI boots and Secure Boot is active:
   ```
   bootctl status        # "Secure Boot: enabled (user)"
   ```

**Consequence to remember:** with our keys only, media signed *solely* by
Microsoft (stock Windows installer, some vendor recovery ISOs, MS-signed memtest)
will **not** boot. To run rescue media, sign it yourself or turn Secure Boot off
in the BIOS temporarily — and note that toggling SB off will invalidate the TPM
keyslot (see below).

**No fallback bootloader exists.** `systemd-boot.enable = false` and lanzaboote
owns the entry, so a bad UKI means booting install media. That is the accepted
cost of the single-loader design, not an oversight.

---

## LUKS TPM+PIN — enroll, unlock, fallbacks, re-enroll

*Relates to slice #23. See [ADR-0003](adr/0003-luks-tpm-pin-encrypted-btrfs.md).*

The root disk is a single LUKS2 container (everything but the ~1G ESP). Unlock is
via the TPM sealed to **PCR 7** **and** a **PIN**. The PIN is load-bearing: the
TPM authenticates the *platform, not the person*, so TPM-only would let a stolen,
powered-off laptop decrypt itself. TPM anti-hammering lets the PIN stay short.

**Do this only after Secure Boot is enrolled, SB is ON, and firmware is current**
(Phase C, steps C3–C4). PCR 7 encodes the Secure Boot state; enrolling against a
PCR 7 that is about to change just guarantees a broken keyslot.

```
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/nvme0n1p2
```

**Why PCR 7 only:** PCR 7 encodes "Secure Boot on, with our keys" and is stable
across kernel and firmware updates. PCR 0 would break on **every** firmware
update (frequent on Framework); PCR 4/11 would break on most rebuilds unless a
signed PCR policy is set up — that's deferred as a later enhancement. Binding PCR
7 pairs with the signed UKI (fixed cmdline, bundled initrd) from ADR-0002 to give
evil-maid resistance without the brittleness of measuring the kernel directly.

**Verify unlock:**

- [ ] Reboot. At the LUKS prompt, entering the **PIN** unlocks (the TPM supplies
      the rest). No passphrase needed on the happy path.

**Confirm both fallbacks still work — do NOT skip these.** Both were enrolled back
in Phase B (keyslots 0 and 1); this confirms the TPM enrollment did not disturb
them:

- [ ] **Passphrase keyslot:** at the unlock prompt, use the passphrase from B0
      instead of the TPM+PIN and confirm it unlocks.
- [ ] **Recovery key:** unlock with the recovery key from B2.

> **Re-enroll note (expected, not a failure).** Re-enrolling Secure Boot keys,
> toggling Secure Boot in the BIOS, or a Framework firmware update can shift
> **PCR 7** and **invalidate the TPM keyslot**. When that happens the TPM+PIN
> unlock stops working — this is by design. Recover by:
> 1. Unlocking with the **passphrase** (or recovery key) at the boot prompt.
> 2. Wiping the stale TPM keyslot and re-enrolling:
>    ```
>    sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p2
>    sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes /dev/nvme0n1p2
>    ```

---

## Fingerprint — reader present, firmware current, enroll, gating

*Relates to slice #22. Uses the in-tree libfprint (no vendor TOD driver).*

1. **Confirm the reader is present** on USB:
   ```
   lsusb | grep -i 27c6:609c
   ```
   `27c6:609c` is the Framework 13 / Goodix reader. No match → wrong port/model
   or a firmware issue; stop here.
2. **Firmware ≥ 3.05** — already handled in C4. Confirm the reported reader
   firmware is **≥ 3.05** with `fwupdmgr get-devices` before enrolling.
3. **Enroll a finger:**
   ```
   fprintd-enroll
   fprintd-verify     # sanity-check the enrolled finger reads back
   ```
4. **Verify gating works both ways:**
   - [ ] **cosmic-greeter login** accepts the enrolled finger.
   - [ ] **`sudo`** accepts the enrolled finger.
   - [ ] **Password fallback is intact** — at both the greeter and a `sudo`
         prompt, a password still authenticates when no finger is offered. The
         fingerprint is an *addition*, never a replacement.

---

## Commit signing — bootstrap the dedicated SSH signing key

*Relates to slice #19. See CONTEXT.md, "Commit signing key".*

This is a **dedicated** Ed25519 SSH key that signs commits and tags — distinct
from the SSH key that authenticates pushes, so the sign and push roles never blur.

> **home-manager already did most of this. Do not run `git config --global`.**
> `hosts/framework/home.nix` declares `gpg.format = ssh`, `user.signingKey`,
> `commit.gpgsign`, `tag.gpgsign`, and `gpg.ssh.allowedSignersFile`, and an
> activation script *already generated the key* at `~/.ssh/id_ed25519_signing` on
> first activation. home-manager owns `~/.config/git/config` as a **read-only
> symlink into the nix store**, so `git config --global` will fail against it —
> and if it did succeed it would put the machine's git config outside the repo,
> which is the opposite of what this config is for. Config changes go in
> `home.nix`.

What remains is only the part that cannot be declared: telling GitHub and the repo
about the public half.

1. **Read the public key** the activation script generated:
   ```
   cat ~/.ssh/id_ed25519_signing.pub
   ```
2. **Upload the *public* half to GitHub as a *Signing key*** — GitHub → Settings →
   SSH and GPG keys → New SSH key → **Key type: Signing Key** (NOT Authentication
   Key).
3. **Paste the same public half into the repo** so local `git log --show-signature`
   verifies. Edit `hosts/framework/allowed_signers` (the file's own header
   documents the format) and add:
   ```
   williams.r.drew@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA…
   ```
   Then commit, push, and `nixos-rebuild switch` so home-manager materialises the
   updated file at `~/.config/git/allowed_signers`.
4. **Verify** a new commit signs and reads as verified:
   ```
   git commit --allow-empty -m "test: verify commit signing"
   git log --show-signature -1     # expect "Good \"git\" signature"
   ```

> ### ⚠️ Load-bearing caveat: never delete an old public signing key from GitHub
>
> SSH signing keys have **no validity window** — GitHub cannot know *when* a key
> was in use, only *whether* it is currently registered to the account. If you
> remove an old public signing key from GitHub, **every commit ever signed with
> it reverts from "Verified" to "Unverified"** across all of history. Rotating to
> a new key means *adding* the new key alongside the old ones; the old public
> keys stay on the account **forever**. Regenerating the private key (a disposable
> act — see CONTEXT.md) still means the retired *public* half stays uploaded.

---

## Secrets (sops) — verification, re-keying, recovery

*Relates to slice #18. See CONTEXT.md, "Host age key" / "Admin age key".*

Every secret is encrypted to two recipients — the admin age key (off-machine, in
the password manager) and the laptop's host age key (its SSH host key, root-only
on the encrypted root). The machine decrypts at *activation*. The recipient list
lives in `.sops.yaml`; the NixOS wiring lives in `hosts/framework/secrets.nix`.
Generation is Phase A, and the ordering constraint is Phase B — this section is
verification and what to do when it goes wrong.

### Verify

- [ ] **Secrets decrypt at activation** (Phase C1):
      ```
      sudo ls -l /run/secrets-for-users/drew_password_hash
      ```
- [ ] **The password actually works** — cosmic-greeter, and `sudo -k && sudo true`.
      Do this *before* you trust the machine, while install media is still to hand.
- [ ] **No plaintext in the repo:**
      ```
      grep -rn "ENC\[" secrets/
      git grep -nI '\$y\$\|AGE-SECRET-KEY' -- . ':!secrets/' ':!docs/'
      ```
      The first should list ciphertext; the second should find **nothing**. `docs/`
      is excluded because this very checklist names those patterns in its
      instructions — it would otherwise always match itself and train you to
      ignore a real hit.
- [ ] **Admin key is off-machine:** `sudo grep -rl AGE-SECRET-KEY /etc /var /home`
      finds nothing.

### Re-keying after a reinstall

A fresh install means a fresh host key, so every secret must be re-encrypted to
it. This is the routine case, not an emergency — losing the *host* key is a re-key,
losing the *admin* key is a loss (CONTEXT.md).

Repeat B3, B5, and B6: generate the new host key, `ssh-to-age` its public half,
replace the host recipient in `.sops.yaml`, `sops updatekeys` with the admin key,
commit. The old host recipient is simply dropped; no need to preserve it. Note a
reinstall also means repeating **B4** — a fresh sbctl bundle means new Secure Boot
keys, so they must be re-enrolled and the TPM keyslot re-created.

### Recovery — locked out by a secret that won't decrypt

If no password authenticates, the sops secret didn't decrypt. In order of cost:

1. **Roll back a generation** at the boot menu, if a working one exists. Fastest,
   and available for every failure *except* a broken first install.
2. **Install media.** Boot it, unlock (passphrase from B0 or recovery key from B2)
   and mount the root, then `nixos-enter`. Inside, check whether
   `/etc/ssh/ssh_host_ed25519_key` exists and whether its `ssh-to-age` output
   matches the host recipient in `.sops.yaml`. Mismatch is the near-certain cause;
   fix it by re-keying (B3, B5, B6) and rebuilding. Note `passwd` is **not** a fix —
   `mutableUsers = false` discards it on the next activation.

---

## Cross-cutting hardware-only checks

These belong to no single subsystem — they are pure "does the hardware behave"
checks the dry-build can't reach.

### BIOS firmware ≥ 3.05

- [ ] Confirm the **BIOS/firmware is ≥ 3.05** (`fwupdmgr get-devices`, or the BIOS
      screen). Prerequisite for the fingerprint reader. Handled in C4 —
      **before** the TPM enrollment, because a firmware update shifts PCR 7.

### Brightness keys (kernel sanity check)

- [ ] The display **brightness keys** raise and lower the panel backlight. This is
      a quick sanity check that the pinned-latest kernel (Linux 7.1) is driving
      the 7040 backlight correctly — brightness control was a reason for opting
      into the newer kernel in the first place.

### Wi-Fi via NetworkManager

- [ ] **Wi-Fi connects** through NetworkManager (`nmcli device wifi connect …` or
      the COSMIC applet) and survives a reboot. Wired/wireless are the only
      networking here. Doubles as the check that redistributable firmware landed
      for the MT7922.

### COSMIC trackpad gestures + fractional scaling — research-#5 gap

- [ ] **Validate the final feel on the 13" panel.** This is the **explicit
      unverified gap flagged in research #5**: COSMIC is the youngest candidate DE
      with the shallowest NixOS troubleshooting corpus (ADR-0005), so
      trackpad-first gestures (workspace/overview swipes) and **fractional
      scaling** on the 13" display are not proven until checked on real hardware.
      Confirm gestures respond, scaling looks crisp (no blur/tearing) at the
      chosen fraction, and — per the desktop workflow requirement — the
      **trackpad keeps working even in tiling mode** (tiling is a per-workspace
      toggle, never keyboard-only). If any of this feels wrong, this is where the
      gap gets recorded and chased.
