---
status: accepted
---

# Custom-key Secure Boot via lanzaboote (supersedes systemd-boot)

The map originally settled the bootloader as **systemd-boot** and listed Secure
Boot as out of scope. A later hard requirement — "a secure system" — pulls Secure
Boot into scope, and on NixOS the only way to get it is **lanzaboote**, which
replaces systemd-boot and boots a **signed Unified Kernel Image** (kernel + initrd
+ cmdline bundled and signed). This ADR records that reversal so a future reader
isn't confused about why the "settled" bootloader changed.

We enroll **our own keys only** (`sbctl`-generated PK/KEK/db) with **no shim and no
Microsoft keys**. Because the kernel command line is embedded in the signed UKI,
systemd-stub ignores any injected cmdline while Secure Boot is on — closing the
classic `init=/bin/sh` and evil-maid-initrd attacks.

**Where the Secure Boot signing key lives (as built).** `boot.lanzaboote.pkiBundle` points at
`/var/lib/sbctl` — an on-device bundle created by hand in the installer, on the
LUKS-encrypted root. It is **not** committed and **not** a sops secret. This ADR
originally specified a sops-nix secret; that remains the intent, but it cannot be
the *first* state: `nixos-install` signs the UKI before there is a booted system or
a host age key to decrypt with, so the first bundle is necessarily on-device.
Capturing it into sops afterwards is tracked as
[#32](https://github.com/r4stered/drewos/issues/32).

## Considered Options

- **systemd-boot (keep the settled choice), Secure Boot off** — rejected. Directly
  contradicts the "secure system" requirement; systemd-boot cannot sign boot images.
- **lanzaboote with Microsoft keys / shim enrolled** — rejected. Not needed on the
  7840U (integrated GPU, no third-party option ROM that requires MS keys; Framework
  firmware updates are UEFI capsules verified by vendor keys, not the Secure Boot
  `db`). Owning the entire key hierarchy is the stronger, cleaner posture.

## Consequences

- `sbctl enroll-keys` without `--microsoft` requires an explicit acknowledgment flag
  and is only safe here because this board has no MS-signed option ROM.
- Media signed **only** by Microsoft (stock Windows installer, some vendor recovery
  ISOs, MS-signed memtest) will not boot; sign it yourself or disable Secure Boot in
  BIOS temporarily to run rescue media.
- Until #32 lands, the Secure Boot signing key has **no off-machine copy**, and its loss
  costs a BIOS-level re-enroll rather than a restore (CONTEXT.md states the exact cost).
  Once #32 lands, the key's blast radius moves onto the **admin age key**, and losing
  *that* would compromise the whole secure-boot chain.
