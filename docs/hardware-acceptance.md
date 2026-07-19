# Hardware Acceptance Checklist

The manual seam. A `nixos-rebuild dry-build` proves the config *evaluates*; it
cannot prove that Secure Boot enrolls, the TPM unlocks, a finger reads, a commit
signs, or a secret decrypts on **this** physical Framework 13. Those are
hardware-and-firmware facts, established once, by hand, on the machine. This is
the ritual Drew runs after a fresh install (or a re-key) to sign off that the
laptop actually *is* the machine the repo describes.

Work top-down: run the top-level checklist, and when a box won't tick, drop into
the matching per-subsystem ritual below for the full ceremony. Cross-cutting
hardware-only checks come last.

> **Posture note — this doc follows the ADRs, not the old handoff.** Two steps
> from the original project handoff are **reversed** here and the old wording is
> dead:
> - Desktop is **COSMIC**, not GNOME. ([ADR-0005](adr/0005-cosmic-desktop-cold-boot-power.md))
> - Secure Boot is **enrolled with our own keys and turned ON**, *not* disabled.
>   Anywhere the handoff says "disable Secure Boot", read "enroll our keys and
>   enable it". ([ADR-0002](adr/0002-custom-key-secure-boot-via-lanzaboote.md))

## Top-level checklist

- [ ] **BIOS firmware ≥ 3.05** confirmed (fingerprint reader depends on it — see below)
- [ ] **Secure Boot:** our keys enrolled with `sbctl` (no `--microsoft`), SB ON in BIOS, signed UKI boots
- [ ] **LUKS TPM+PIN:** enrolled to PCR 7 + PIN, unlocks at boot
- [ ] **LUKS fallbacks:** passphrase keyslot unlocks; recovery key unlocks
- [ ] **Fingerprint:** `lsusb` shows `27c6:609c`, firmware current, `fprintd-enroll` succeeds
- [ ] **Fingerprint gating:** cosmic-greeter login and `sudo` accept a finger; password fallback still works
- [ ] **Commit signing:** dedicated Ed25519 key generated, git points at it, **public** half uploaded to GitHub as a *Signing key*, pubkey + `allowed_signers` committed
- [ ] **Secrets (sops):** secrets decrypt at activation; no plaintext in the repo
- [ ] **Brightness keys** change the panel backlight
- [ ] **Wi-Fi** connects via NetworkManager
- [ ] **COSMIC trackpad gestures + fractional scaling** feel right on the 13" panel *(research-#5 gap — validate here)*

---

## Secure Boot — enroll our keys, enable, confirm signed-UKI boot

*Relates to slice #21 (lanzaboote). See [ADR-0002](adr/0002-custom-key-secure-boot-via-lanzaboote.md).*

We own the entire key hierarchy: `sbctl`-generated PK/KEK/db, **no shim, no
Microsoft keys**. lanzaboote signs a Unified Kernel Image (kernel + initrd +
cmdline bundled) with the `db` key so the firmware will run it.

1. Put the BIOS into **Setup Mode** (clear/reset the existing Secure Boot keys in
   the BIOS security menu) so custom keys can be enrolled.
2. Create our key pair:
   ```
   sudo sbctl create-keys
   ```
   Keys land in the on-device PKI bundle at **`/var/lib/sbctl`**. This directory
   is on the LUKS-encrypted root; the private `db` key's long-term home is a
   sops-nix secret (see CONTEXT.md, "Secure Boot signing key"), but the working
   copy the signer reads lives here.
3. Enroll **our keys only** — deliberately *without* `--microsoft`:
   ```
   sudo sbctl enroll-keys
   ```
   `sbctl` will demand an explicit acknowledgment because omitting the Microsoft
   keys can brick boards with an MS-signed option ROM. This board (7840U,
   integrated GPU) has none, so it is safe here.
4. Confirm the boot image is signed and verify status:
   ```
   sudo sbctl verify     # UKI(s) under /boot/EFI should show "signed"
   sbctl status
   ```
5. **Turn Secure Boot ON** in the BIOS and save.
6. Reboot. Confirm the signed UKI boots and Secure Boot is active:
   ```
   bootctl status        # "Secure Boot: enabled (user)"
   ```

**Consequence to remember:** with our keys only, media signed *solely* by
Microsoft (stock Windows installer, some vendor recovery ISOs, MS-signed
memtest) will **not** boot. To run rescue media, sign it yourself or turn Secure
Boot off in the BIOS temporarily — and note that turning SB off will invalidate
the TPM keyslot (see next section).

---

## LUKS TPM+PIN — enroll, unlock, fallbacks, re-enroll

*Relates to slice #23. See [ADR-0003](adr/0003-luks-tpm-pin-encrypted-btrfs.md).*

The root disk is a single LUKS2 container (everything but the ~1G ESP). Unlock is
via the TPM sealed to **PCR 7** **and** a **PIN**. The PIN is load-bearing: the
TPM authenticates the *platform, not the person*, so TPM-only would let a stolen,
powered-off laptop decrypt itself. TPM anti-hammering lets the PIN stay short.

**Enroll** (run against the actual LUKS device — find it with `lsblk`, e.g.
`/dev/nvme0n1p2`):

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

**Confirm both fallbacks work — do NOT skip these:**

- [ ] **Passphrase keyslot:** at the unlock prompt, use the original LUKS
      passphrase instead of the TPM+PIN and confirm it unlocks.
- [ ] **Recovery key:** unlock with the high-entropy recovery key (stored in the
      password manager). If one was not created at install, add one now:
      ```
      sudo systemd-cryptenroll --recovery-key /dev/nvme0n1p2
      ```

> **Re-enroll note (expected, not a failure).** Re-enrolling Secure Boot keys,
> toggling Secure Boot in the BIOS, or an occasional Framework firmware update
> can shift **PCR 7** and **invalidate the TPM keyslot**. When that happens the
> TPM+PIN unlock stops working — this is by design. Recover by:
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
2. **Update reader firmware via fwupd** — the enroll path needs firmware
   **≥ 3.05**:
   ```
   fwupdmgr refresh
   fwupdmgr get-updates
   fwupdmgr update
   ```
   Confirm the reported reader firmware is **≥ 3.05** before enrolling.
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
from the SSH key that authenticates pushes, so the sign and push roles never
blur. It is generated on-machine, never committed, and protected at rest by LUKS
(no passphrase). Run this on **first boot** of a fresh machine.

1. Generate the dedicated signing key:
   ```
   ssh-keygen -t ed25519 -C "drewos commit signing" -f ~/.ssh/id_ed25519_signing
   ```
2. Point git at it (SSH signing format):
   ```
   git config --global gpg.format ssh
   git config --global user.signingkey ~/.ssh/id_ed25519_signing.pub
   git config --global commit.gpgsign true
   git config --global tag.gpgsign true
   ```
3. **Upload the *public* half to GitHub as a *Signing key*** — GitHub → Settings
   → SSH and GPG keys → New SSH key → **Key type: Signing Key** (NOT
   Authentication Key). Paste the contents of
   `~/.ssh/id_ed25519_signing.pub`.
4. Commit the **public** key and an `allowed_signers` entry into the repo so
   local `git log --show-signature` verifies:
   ```
   echo "williams.r.drew@gmail.com $(cat ~/.ssh/id_ed25519_signing.pub)" >> allowed_signers
   git config --global gpg.ssh.allowedSignersFile "$(pwd)/allowed_signers"
   ```
5. **Verify** a new commit signs and reads as verified:
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

## Secrets (sops) — decrypt at activation, no plaintext in repo

*Depends on the sops scaffolding (slice #18), which is **human-in-the-loop**:
Drew provides the **admin age key** off-machine and the **host key** public half.
See CONTEXT.md, "Host age key" / "Admin age key".*

Every secret is encrypted to two recipients — the admin age key (off-machine, in
the password manager) and the laptop's host age key (its SSH host key, root-only
on the encrypted root). The machine decrypts at *activation*.

- [ ] **Secrets decrypt at activation.** After a `nixos-rebuild switch`, confirm
      the sops-nix secrets materialized (e.g. under `/run/secrets/…`) and the
      services that consume them came up — including the Secure Boot signing key,
      which is itself a sops secret (ADR-0002). A decryption failure here surfaces
      as an activation error or a service that can't start.
- [ ] **No plaintext in the repo.** `git grep` / a scan of the tree shows only
      the *encrypted* forms; no decrypted secret is committed. The account
      password, the SB signing private key, and any other secret exist in the repo
      only as sops ciphertext.

---

## Cross-cutting hardware-only checks

These belong to no single subsystem — they are pure "does the hardware behave"
checks the dry-build can't reach.

### BIOS firmware ≥ 3.05

- [ ] Confirm the **BIOS/firmware is ≥ 3.05**. This is flagged as a prerequisite
      for the fingerprint reader (above), and updating firmware can shift PCR 7 —
      so if you update firmware here, expect to re-enroll the LUKS TPM keyslot.
      Check current firmware with `fwupdmgr get-devices` (or the BIOS screen).

### Brightness keys (kernel sanity check)

- [ ] The display **brightness keys** raise and lower the panel backlight. This is
      a quick sanity check that the pinned-latest kernel (Linux 7.1) is driving
      the 7040 backlight correctly — brightness control was a reason for opting
      into the newer kernel in the first place.

### Wi-Fi via NetworkManager

- [ ] **Wi-Fi connects** through NetworkManager (`nmcli device wifi connect …` or
      the COSMIC applet) and survives a reboot. Wired/wireless are the only
      networking here.

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
