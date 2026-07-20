# Secrets via sops-nix. The repo is public, so NOTHING secret is committed in plaintext:
# secrets live in `secrets/` as sops ciphertext and are decrypted at ACTIVATION, on the
# unlocked machine, into tmpfs under /run.
#
# Every secret is encrypted to two recipients — the Admin age key and the Host age key.
# What each one is, why their lifetimes differ, and which loss is recoverable are defined
# once in CONTEXT.md; that is the canonical statement and is deliberately not restated
# here. The recipient list itself lives in `.sops.yaml` — sops' own config, not a NixOS
# option.
#
# This file is the DECRYPTION half: how this machine gets at the secrets, and which
# secrets it declares. User-account policy lives with the account in default.nix.
{ lib, ... }:
let
  # How many age recipients the committed secret is actually encrypted to. The sops
  # format emits one `recipient:` line per age recipient, so counting them checks the
  # property we care about directly rather than through a proxy like grepping .sops.yaml
  # for a commented-out line.
  usersSecretRecipients = builtins.length (
    builtins.filter builtins.isList (
      builtins.split "recipient:" (builtins.readFile ../../secrets/users.yaml)
    )
  );
in
{
  # --- How this machine decrypts ---
  # sops-nix converts the ed25519 SSH host key into an age identity internally, so the
  # host needs no separate age keyfile to manage, back up, or leak. Set EXPLICITLY rather
  # than left to the module default, because that default derives from
  # `services.openssh.enable` — which this config never enables (ADR-0007).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # NO sshd, and the host key is created by hand in the installer rather than by an
  # activation script. Both halves of that decision, and the trade-off accepted (the host
  # age key sits outside declarative management), are recorded in ADR-0007.

  # The default file every `sops.secrets.<name>` below reads from unless it overrides
  # `sopsFile`. `sops.validateSopsFiles` is left at its default (true), so a build FAILS
  # loudly if this file is missing or is not actually sops-encrypted — the guard that
  # keeps a plaintext secret from ever silently passing for an encrypted one.
  sops.defaultSopsFile = ../../secrets/users.yaml;

  # --- Secret: drew's password hash ---
  # `neededForUsers` is load-bearing, not a hint: it moves this secret to
  # /run/secrets-for-users and decrypts it EARLY, before NixOS creates users, because
  # `users.users.drew.hashedPasswordFile` (default.nix) is read during user creation.
  # A plain `sops.secrets` here would decrypt too late and the account would end up with
  # no valid password. Such secrets must be root-owned, which is the module default.
  #
  # It is a HASH, never a password: what is encrypted here is yescrypt output from
  # `mkpasswd`, so even a future compromise of both age keys yields a hash to crack, not a
  # credential to use. Generating it is a human step — see docs/hardware-acceptance.md.
  sops.secrets.drew_password_hash = {
    neededForUsers = true;
  };

  # --- Guard: is the Host age key actually a recipient? ---
  # DISCHARGED TODAY, AND DELIBERATELY KEPT. It reads as satisfied — both recipients are
  # live — but it fires on any future RE-KEY, which is exactly when it matters most: a
  # reinstall generates a fresh host key, and editing `.sops.yaml` without running `sops
  # updatekeys` leaves the ciphertext encrypted to the OLD host.
  #
  # That gap is otherwise invisible. Eval and build both stay green with one recipient, and
  # the failure surfaces only at the first activation — precisely the case with no earlier
  # generation to roll back to, and with `users.mutableUsers = false` meaning no password
  # works at all. So it is a build-time warning that clears itself once the re-key is done.
  #
  # A warning and not an assertion on purpose: the one-recipient state is a legitimate
  # waypoint mid-ritual, and failing eval would block the very work that resolves it.
  #
  # Only users.yaml is checked — it is the secret whose absence locks Drew out. When #32
  # adds secrets/secureboot.yaml it should extend this rather than add a second copy.
  warnings = lib.optional (usersSecretRecipients < 2) ''
    secrets/users.yaml is encrypted to ${toString usersSecretRecipients} recipient(s), expected 2.
    The Host age key is not a recipient, so this machine CANNOT decrypt drew's password at
    activation — and with users.mutableUsers = false that means NO password works. Do not
    install or switch into this state.
    Fix (docs/hardware-acceptance.md, Phase B): generate the host key, ssh-to-age it, put it
    in .sops.yaml, then `sops updatekeys secrets/users.yaml` with the Admin age key.
  '';

  # --- Not yet a secret: the Secure Boot signing key (#32, ADR-0002) ---
  # `boot.lanzaboote.pkiBundle` points at the on-device sbctl bundle in /var/lib/sbctl, so
  # the Secure Boot signing key exists in exactly one place and does not survive the disk.
  # It is NOT a sops secret today. CONTEXT.md and ADR-0002 both describe this accurately;
  # #32 is the work to back it up here, and carries the intended shape and open questions.
}
