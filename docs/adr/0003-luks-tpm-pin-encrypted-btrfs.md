---
status: accepted
---

# LUKS2 full-disk encryption with TPM2+PIN unlock

The root disk is a single **LUKS2** container (whole disk except the ~1G ESP), with
an encrypted **btrfs** filesystem inside. Unlock is via the **TPM**
(`systemd-cryptenroll`) sealed to **PCR 7** (Secure Boot state) **and requires a
PIN** (`--tpm2-with-pin`). The PIN is the load-bearing decision: TPM auto-unlock
authenticates the *platform, not the person*, so a **no-PIN** setup would let a
stolen, powered-off laptop **decrypt itself** on boot — defeating the point of full-disk
encryption. The TPM's hardware anti-hammering lets the PIN be short while still
resisting brute force. A **passphrase keyslot** (always) and a high-entropy
**recovery key** (in the password manager) are kept as fallbacks.

We bind to **PCR 7 only** — it enforces "Secure Boot on, with our keys" and is stable
across kernel and firmware updates. Combined with the signed UKI (fixed cmdline,
bundled initrd) from ADR-0002, this gives strong evil-maid resistance without the
brittleness of measuring the kernel/firmware directly.

## Considered Options

- **No PIN (platform-only TPM unlock)** — rejected. More convenient, but strictly
  weaker against laptop theft than even a plain passphrase; forfeits FDE's core
  "possess the powered-off device, get nothing" guarantee.
- **PCR 0 / 4 / 11 binding** — rejected for first config. PCR 0 breaks on every
  firmware update (frequent on Framework); PCR 4/11 break on most rebuilds unless a
  signed PCR policy is set up (deferred as a later enhancement).
- **Passphrase-only, no TPM** — rejected. The requirement explicitly wants TPM; PIN +
  TPM anti-hammering is more usable than a long passphrase and no weaker in practice.

## Consequences

- Re-enrolling Secure Boot keys, toggling Secure Boot, or an occasional firmware
  update that shifts PCR 7 will invalidate the TPM keyslot → unlock with the
  passphrase and re-run `systemd-cryptenroll`.
- `allowDiscards = true` (TRIM) is enabled: it leaks rough block-usage metadata to an
  attacker with repeated physical access, accepted for SSD longevity/performance.
- **Filesystem & swap:** btrfs subvolumes `/root`, `/home`, `/nix` (`/nix` never
  snapshotted); **zram-only swap, no disk swapfile**; **no hibernation, no suspend**
  (cold boot) — the strongest at-rest posture and the reason there is no `resume_offset`
  coupling into the signed UKI. `snapper` runs on `/home` for data rollback (system
  rollback is handled by NixOS generations). These are recorded here for context but
  are individually low-risk and easily reversible.
