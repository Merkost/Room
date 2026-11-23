# Roadmap

Updated 24 November 2026. Order is the plan; dates are not promises.

## 1.1.0 (Store build 6): release what is on `main`

What it contains: the Overview and Developer redesign, one number format and one filled button per screen, the receipt and ledger safety fixes, the shared design tokens, onboarding v3, and the cleaned-up Developer start page.

Release checklist (owner steps need the Apple account):
1. Merge the two small open fixes: the sidebar button (#14) and removing "Greet me by name" (#13).
2. Run both editions' tests alone, then `scripts/build-store.sh` with the Store distribution identity, upload, and attach the build to 1.1.0.
3. Replace the store screenshots and preview with the new design (`scripts/store-media`), then submit for review.
4. When Apple approves: deploy the site on the redesign track (`SITE-V3-NOTES.md`, flip day), confirm the privacy page wording, and announce.

Not verified before release: signed Store archive, Increase Contrast, VoiceOver, light mode on a second Mac.

## 1.2.0: playful first run and agent storage

- Onboarding redesign: three graphic scenes, almost no text (branch `feat/onboarding-play`).
- More Codex and Claude storage: Claude desktop VM bundles, Claude Code and Codex history and runtime data, a "Review in Developer" note when agent worktrees are heavy (branch `feat/agent-storage`). All inspect-only unless clearly rebuildable.
- Brand design system on screen: Fraunces for display numbers, retuned kind colours, shared motion tokens (DS-5 to DS-14).
- Small fixes: the Developer start page offers saved folders, a clear error when a file is chosen as the projects folder, memory advice uses the same number format, `build-store.sh` and the design gate run on a clean machine.

## 1.3.0: on-device intelligence (optional, off by default)

Apple Foundation Models, on the Mac, no network. Advice only; the catalogue rules keep deciding what is safe.
1. "What is this?" for unknown large folders.
2. A one-line "what changed" on Overview.
3. Ask Room: a small question box over Room's own scan results.
4. Worktree triage hints, with Git facts still checked by Room.
Rules: names and sizes only, never contents; Hide masks names; the feature disappears where Apple Intelligence is unavailable; the privacy page gains one line.

## Later

- A VoiceOver and keyboard pass on every screen.
- Light-mode polish and a second brand accent review.
- Collapse the three route types into one; split the five engine files over 800 lines.
