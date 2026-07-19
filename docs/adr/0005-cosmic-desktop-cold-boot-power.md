---
status: accepted
---

# COSMIC desktop, and power settings that enforce the cold-boot posture

The desktop is **COSMIC** (`services.desktopManager.cosmic.enable` +
`services.displayManager.cosmic-greeter.enable`), and the machine's power behaviour is
configured not for convenience but to keep ADR-0003's **cold-boot posture** ("keys never
linger in RAM") intact. These two are recorded together because the second only makes
sense in light of the first: COSMIC is where lid/idle/power-button actions are surfaced,
and the security requirement is what dictates them.

## Desktop: COSMIC over GNOME

The workflow requirement is a minimal, trackpad-first desktop where **tiling is available
to learn on but never the only way to move between windows** — the maintainer is
deliberately building keyboard/vim/tiling fluency without giving up the mouse. COSMIC fits
this natively: tiling is a **per-workspace toggle** (Super+Y) with **per-window float**
(Super+G), and it stays **mouse-first even in tiling mode** (drag tiles and borders,
right-click title bars) — unlike the rigid keyboard-only tiling of i3/Sway. It reached 1.0
and is a first-class NixOS module on 26.05.

This overrides the earlier leaning toward **GNOME**. GNOME remains the calmer, far
better-documented base — a real pull given ADR-0001 chose stable precisely for a calm base
while the maintainer is new to NixOS recovery — but it **cannot deliver the tiling goal**:
Pop Shell (the only real tiling for GNOME) is unmaintained by System76, who moved all
tiling effort into COSMIC's compositor, and it is broken on GNOME 48 (what 26.05 ships),
leaving only edge-snap. Choosing the tiling goal therefore means choosing COSMIC and
accepting its cost.

## Power settings enforce the cold-boot posture

ADR-0003 frames "no suspend, no hibernation" as a **security property**, not a comfort
preference. Security properties are enforced by making the bad state unreachable, so:

- **Sleep is hard-masked** — `systemd.targets.{sleep,suspend,hibernate,hybridSleep}.enable
  = false`. Suspend is *impossible* system-wide; no menu item, keybind, or package can put
  keys back into powered RAM.
- **Power button → clean poweroff** (`services.logind.powerKey = "poweroff"`): the
  deliberate "key out of RAM now" control.
- **Lid close → lock + screen off, keep running** (`services.logind.lidSwitch = "lock"`).
  Chosen for instant resume; the machine is never used clamshell/docked, so keeping it
  running lid-closed buys convenience only.
- **Idle → blank+lock at ~5 min, `IdleAction = "poweroff"` at ~20 min.** The idle-poweroff
  is the **compensating control** for lid=lock: it is what returns the machine to a cold
  state automatically when the maintainer walks away or bags it while it is still running.
- **Boot requires a cosmic-greeter login** (no autologin): defence-in-depth after the LUKS
  PIN, and the login password auto-unlocks the COSMIC keyring (avoiding stray secret
  prompts).

## Considered Options

- **GNOME (+ Pop Shell for tiling)** — rejected. Pop Shell is unmaintained and broken on
  GNOME 48; GNOME would satisfy "minimal + best gestures + best-documented" but forfeits
  the tiling learning goal, which is the point.
- **Pantheon** — rejected. No real tiling story and weaker Wayland gestures; nothing left
  to recommend it for these goals.
- **Lid close → poweroff** — rejected (though the *stronger* posture). It would enforce
  cold-boot mechanically even on transport, and there is no clamshell use to lose, but the
  maintainer preferred instant-resume; the ~20-min idle-poweroff recovers most of the
  guarantee.
- **Soft no-suspend (configure options, leave `suspend.target` reachable)** — rejected. A
  stray keybind or package could still suspend; the guarantee must be structural.
- **Autologin after LUKS** — rejected. Saves one prompt per boot but breaks keyring
  auto-unlock and can be flaky through cosmic-greeter on 26.05.

## Consequences

- **The cold-boot guarantee has a hole while the lid is shut.** lid=lock keeps the LUKS
  master key in RAM, so a laptop **bagged while still running** is a cold-boot/DMA target
  until the ~20-min idle-poweroff fires (or the maintainer hits the power button first).
  ADR-0003's "keys never linger in RAM" holds *fully* only via that timer or manual
  power-off before the machine leaves the maintainer's control. This is the accepted
  boundary of the posture.
- The poweroff-heavy behaviour (idle→off, power-button→off, no suspend) means **frequent
  boots**, each costing a LUKS PIN + greeter login.
- **Input**-idle drives the 20-min poweroff, so an unattended but silent long job (a large
  `nixos-rebuild`, a download) will be powered off at the timeout unless the machine is
  kept awake.
- COSMIC is the youngest of the candidate DEs with a shallower NixOS troubleshooting
  corpus — a standing tension with ADR-0001's calm-base rationale, accepted for the tiling
  goal.
- Individual power settings are trivially reversible (they are logind/systemd options);
  the DE choice is a config change plus a rebuild.
