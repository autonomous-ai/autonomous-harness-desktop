# Desktop terminal shell design QA

## Evidence

- Source visual truth:
  - `/var/folders/ct/7rts83zj1fbc0tsh73wpt4_80000gp/T/codex-clipboard-TGSZU4.png` — existing terminal desktop screen, 3586 × 2126 px.
  - `/var/folders/ct/7rts83zj1fbc0tsh73wpt4_80000gp/T/codex-clipboard-1vyvm7.png` — account-menu placement reference, 590 × 636 px.
- Implementation:
  - `/tmp/autonomous-desktop-account-menu-final.png` — final account-menu state, 3600 × 2134 px.
  - `/tmp/autonomous-desktop-settings-final.png` — final Settings state, 3600 × 2134 px.
  - `/tmp/autonomous-desktop-resized.png` — responsive terminal state, 2600 × 1700 px.
- Combined full-view comparison: `/tmp/autonomous-desktop-design-qa-comparison.png`.
- Focused menu comparison: `/tmp/autonomous-desktop-menu-focused-qa.png`.
- Viewport: 1800 × 1067 logical px at macOS 2× density; responsive check at 1300 × 850 logical px.
- Normalization: source and implementation full views were scaled to the same 1800 × 1067 logical frame before the combined comparison. The account-menu source remained at native size for the focused comparison.
- State: local Backend + local Harness CLI, encrypted terminal attached to an existing OpenCode tmux session; profile menu and Settings tested while the terminal remained visible.

## Full-view comparison

- Information architecture matches the requested composition: global terminal header, fixed Machines → Agents sidebar, uninterrupted terminal pane, and account controls anchored at the bottom-left.
- The former top-right Settings and Logout actions are gone; Reload remains in the global header.
- The 252–300 px sidebar keeps the terminal dominant at both checked window sizes. Machine scrolling and the account footer occupy separate layout regions.
- Opening the profile menu and Settings dims or overlays the shell without replacing the terminal session. The active engine and `CONTROLLING` state remain visible.

## Focused-region comparison

- The focused comparison was required because account-menu hierarchy and anchoring are too small to judge from the full view.
- The implementation preserves the reference relationship: account row fixed at the bottom, popover opens upward, identity appears first, Settings is a primary row, version/environment is secondary, and disconnect/sign-out is separated at the bottom.
- Dark monospace styling is an intentional adaptation of the light reference so the menu belongs to the terminal shell.

## Required fidelity surfaces

- Fonts and typography: Menlo is used across shell, machine tree, menu, and Settings; compact weights and labels remain legible at 2× density without clipping.
- Spacing and layout rhythm: 48 px global header, compact tree rows, 66 px account footer, small radii, and 1 px borders produce consistent terminal density. No persistent control is hidden at 1300 × 850.
- Colors and tokens: shared dark palette maps shell, sidebar, surfaces, borders, muted text, cyan accent, and green connection state consistently.
- Image quality and assets: the target contains no product raster imagery. Standard Material icons are used for terminal, Settings, account actions, status, and search; the avatar is a normal account-initial component.
- Copy and content: only implemented actions are shown. Invite, feedback, and update controls were deliberately omitted. Local manual mode uses `Local`, while production sessions use the authenticated email and selected environment.

## Comparison history

1. Initial pass found one P2 consistency issue: local footer said `LOCAL SESSION`, while the menu version row and Settings environment still said `Production`.
2. Fixed both surfaces to render `Local`/`LOCAL` whenever the guarded local-manual fixture is active.
3. Post-fix evidence in `autonomous-desktop-account-menu-final.png` and `autonomous-desktop-settings-final.png` confirms the mismatch is gone. No actionable P0/P1/P2 differences remain.

## Interaction and runtime checks

- Opened and closed the account menu.
- Opened Settings from the menu and confirmed the Backend URL and environment state.
- Resized the native window from 1800 × 1067 to 1300 × 850 and restored it.
- Confirmed the same terminal session stayed rendered and controlling through menu, dialog, and resize states.
- Flutter runtime log showed a successful macOS build and no UI exception during these checks.

## Follow-up polish

- P3: production can use `avatarUrl` later if the API starts returning a non-null image; the initials avatar is intentional for the current response.

final result: passed
