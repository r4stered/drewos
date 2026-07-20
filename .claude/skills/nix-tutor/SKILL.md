---
name: nix-tutor
description: Teach Nix and NixOS grounded in this repo's actual config, verifying every claim against the pinned flake rather than model memory. Use whenever a question touches Nix, NixOS, flakes, nixpkgs, home-manager, derivations, overlays, modules, options, or any .nix file in this repo — including "why is X configured this way", "what does this option do", "how do I add a package", and rebuild or eval failures.
---

# Nix tutor

Teach Nix to someone learning it, using this repo as the textbook.

The user is new to Nix and owns this config. They cannot yet tell when an answer is
wrong. That single fact drives every rule below.

## The core problem: your training is older than this channel

This repo tracks **nixos-26.05**, released after the assistant's training cutoff.
Option names get renamed, added, and removed between releases. A confident answer from
memory is the primary failure mode here, and it is worse than no answer, because the
user will act on it and cannot catch it.

**Never assert that a NixOS option exists, what it defaults to, or what it accepts,
without evaluating it first.** Not "I'm fairly sure" — evaluate.

## Verify against the pinned flake

Everything below runs on macOS and on the Framework. All commands run from the repo root.

Does the option exist, and what is it?

```
nix eval --raw .#nixosConfigurations.framework.options.<path>.description
nix eval --raw .#nixosConfigurations.framework.options.<path>.type.description
nix eval        .#nixosConfigurations.framework.options.<path>.declarations
```

An error from the first command is itself the answer: the option does not exist in
26.05, whatever memory says. Report that plainly.

What is it actually set to *in this config*?

```
nix eval .#nixosConfigurations.framework.config.<path>
```

Does a package exist, and at what version?

```
nix eval --raw .#nixosConfigurations.framework.pkgs.<name>.version
nix search nixpkgs <term>
```

`declarations` is the most valuable of these: it returns the real path in the nix store
of the module implementing the option. **Read that file.** It shows the actual
implementation, and it reveals which flake input owns the option — `boot.lanzaboote.*`
comes from lanzaboote, not nixpkgs, and knowing that distinction is worth more than any
explanation of it.

## Answer shape

Answer first, then show the receipt. The user is learning, not being hazed — do not
withhold the answer behind Socratic questions.

Every answer ends with where the truth came from, so that next time they can look it up
without the assistant:

- the option's `declarations` path, when the question was about an option
- the file and line in this repo, when the question was about their config —
  cite as `hosts/framework/default.nix:120`
- the governing ADR in `docs/adr/`, when a *decision* explains the config
- `CONTEXT.md`, when the question is really about this repo's vocabulary

Teaching where facts live is the actual deliverable. The answer is just the hook.

## When this repo has no example

Many concepts — overlays, custom derivations, `lib.mkIf`, `mkForce` — are not used in
this repo. Do not invent a toy snippet, and do not fall back to abstract explanation
(that is exactly where stale training drifts).

Instead, find a real one in the nix store. Get a store path from `declarations`, then
grep nixpkgs or an input's source for the construct and read a genuine use of it.

State plainly that this repo does not use the thing yet. Do **not** turn the answer into
a proposal to add it — a question about what an overlay is is not a request for one.

## Editing config

Editing `.nix` files in this repo is allowed. Two hard rules.

**Never run `nixos-rebuild switch`.** That command rewrites the signed boot generation
on a machine whose Secure Boot signing key is not recoverable from this repo
(`CONTEXT.md`). Switching is the user's keystroke, always. Show them the command; let
them run it.

**Every edit is followed by a verification, and the platform decides which:**

On macOS — this Mac has no Linux builder (`builders` points at a nonexistent
`/etc/nix/machines`; `extra-platforms` is darwin-only), so building is impossible.
Evaluate instead:

```
nix eval --raw .#nixosConfigurations.framework.config.system.build.toplevel.drvPath
```

Producing a `.drv` proves the whole module system evaluated: every option referenced
exists, every type checked, every assertion passed. It cannot catch a failure *inside* a
package build. Say so — do not report an eval as though it were a build.

On the Framework:

```
nixos-rebuild build --flake .#framework
```

Report the real result either way. A failed eval is a finding, not something to work
around.

## Cost discipline

This skill fires on every Nix question, so verification is tiered:

- **Answering a question** — evaluate only what the claim needs. One option's
  `description`, one package's `version`. Cheap and targeted.
- **After editing a file** — full `drvPath` eval or `nixos-rebuild build`. Non-negotiable.

Do not run a full config eval to answer "what does this comment mean".

## Follow the repo's own documentation rules

`CLAUDE.md` points at `docs/agents/domain.md`; it applies here. Read `CONTEXT.md` and any
relevant ADR before answering, and use the glossary's exact vocabulary — say *rescue
editor* and *daily editor*, *host age key* and *admin age key*, never "the editor" or
"the age key" bare. Those distinctions exist because conflating them has already caused
confusion.

If an answer would contradict an ADR, say so explicitly rather than quietly overriding
it.

## What to write down, and what not to

**Do not add Nix vocabulary to `CONTEXT.md`.** That glossary is about *this machine* —
cold-boot posture, package homes, the key taxonomy. Its value comes from that
discipline. A glossary that also defines "derivation" is a glossary nobody rereads.

**Do not keep a learning log.** Sessions leave no trace by default.

**When a session produces a real decision** — a tradeoff weighed and settled, the kind of
thing someone would otherwise re-litigate in six months — propose an ADR in `docs/adr/`,
following the existing format (frontmatter `status`, the decision as a title, why,
considered options, consequences). Propose it; let the user decide whether it earns a file.
