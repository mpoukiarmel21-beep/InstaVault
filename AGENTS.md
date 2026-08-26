# killer-saas — Repo rules

## Absolute rule
No direct coding. Every feature goes through the killer-saas pipeline, in order:

PRD → User Stories → Architecture (+ Design System) → then, per story: Research → Design → Plan → Execute → Review → Ship

No code is written before the story has a validated plan (`/ks-plan`). No feature ships before a passed review (`/ks-review`).

### Quick Fix mode — exception to the pipeline

`Quick Fix` is the explicit exception for a small, local, well-understood, and
easily reversible adjustment. It applies only when the user explicitly requests
a Quick Fix. The primary agent implements it directly, without the full
killer-saas pipeline and without mandatory TDD. It must not delegate
implementation to a subagent; a subagent may be used only for read-only
investigation or optional review.

Typical Quick Fixes include:

- changing a color, spacing, radius, font size, or button style;
- correcting short UI copy or a translation;
- making a small layout alignment or responsive adjustment;
- restoring or adjusting an already-existing presentation affordance;
- another similarly narrow change with no architectural or business impact.

Quick Fix mode does **not** apply to a new feature, shared-component redesign,
data model or migration, API or contract change, authorization, security,
business rules, persistence, cross-cutting refactor, dependency change, or any
change whose impact is uncertain. If the requested Quick Fix is too large or
investigation reveals one of these, the primary agent must stop Quick Fix mode,
recommend using the normal pipeline, and must not continue coding until the work
has passed the appropriate pipeline stages.

The primary agent must announce Quick Fix mode and its exact scope before
editing, keep the diff minimal, preserve existing abstractions, and perform a
proportionate verification (at minimum a focused lint, typecheck, existing test,
or visual browser check when applicable). TDD and subagent review are optional,
not forbidden. Quick Fix work must still happen on the currently authorized
branch/worktree. Before editing, the primary agent must verify that no other
agent is editing the same files or targets. If work overlaps, coordinate
ownership or stop; never make concurrent edits to the same targets.

## Pipeline (commands)
- `/ks-prd`        frames the kill: target SaaS, kill mode, perimeter (WHAT + WHY)
- `/ks-stories`    breaks it down into shippable user stories
- `/ks-stories-review`  reviews the breakdown against the PRD perimeter (stories-reviewer subagent)
- `/ks-architect`  sets the technical HOW + the conventions
- `/ks-design-system`  captures the global design system (docs/design-system.md)
- `/ks-research`   explores the story's real context (current code, APIs, traps)
- `/ks-design`     derives a story's screen from the design system (UI stories)
- `/ks-plan`       breaks a story into sequenced tasks
- `/ks-execute`    implements the story in TDD (implementer subagent)
- `/ks-review`     anti-hallucination review + gate (reviewer subagent)
- `/ks-ship`       opens the PR; merge/deploy per the ship strategy (manual by default)

Utilities:
- `/ks-orchestrator`  runs a story's full cycle with human checkpoints (plan validation, ship confirmation)
- `/ks-help`          prints the pipeline map (French, user-facing cheat sheet)
- `/ks-status`        derives the project's pipeline state from the files (framing, per-story progress, next command)

One feature = one Research → Design → Plan → Execute → Review → Ship cycle = one branch = one PR (Design only when the story has UI).

## Story ids and branches
- Every story has an id: `s<number>-<short-slug>` (e.g. `s01-submit-testimonial`). It is assigned in docs/stories.md and reused verbatim everywhere: `docs/research/<id>.md`, `docs/plans/<id>.md`, `docs/reviews/<id>.md`, branch `feature/<id>`.
- All work on a story happens on `feature/<id>`, branched from the default branch. Never commit story work to the default branch.
- The story diff = `git diff <default-branch>...feature/<id>`. That is what the review judges.
- A command that receives a fuzzy story name resolves it against docs/stories.md; if there is no unambiguous match, it lists the available stories and stops.

## Gate (mechanical)
- The review report `docs/reviews/<id>.md` must end with the exact lines `Max severity: <critical|major|minor|none>` and `Ship allowed: <yes|no>`. A single critical = no.
- `/ks-ship` refuses to run unless that file exists and contains the line `Ship allowed: yes`. No file, no line, or `no` → ship blocked. No exceptions.
- After a blocked review, `/ks-execute` runs in fix mode: the review findings are fed to the implementer and fixed before anything else.
- A plan executes only if its frontmatter says `validated: yes` — set by the human validation checkpoint (/ks-plan or the orchestrator), never by the file merely existing. /ks-execute is fail-closed on it.

## Ship strategy
Merge mode: manual   (manual | auto — default: manual)
- manual: /ks-ship opens the PR and stops. Merging is a human decision (review on GitHub, protected branch, CI). After the merge, rerun /ks-ship to confirm the deployment and clean up the branch.
- auto: /ks-ship merges and deploys immediately after the gate. Only for solo flows where running /ks-ship IS the decision.

## Design
The global design system lives in `docs/design-system.md` (components + tokens, anchored to the boilerplate). Each story's design lives in `docs/designs/<id>.md` (+ a reference `.html` mockup).
- A story's design can be generated by the agent or produced in Claude Design / Gemini and brought back. Either way it builds on the design system.
- Inventing a component or token outside the design system is forbidden. Compose with what exists.
- The HTML mockup is a reference, not code: the implementation uses the boilerplate's real components.
- A need the system doesn't cover = a "design system gap" to report, never to fill freestyle.
- Stories without UI skip `/ks-design`.

## Data & docs lifecycle
All pipeline data lives in markdown files under docs/, versioned by git. No database, no state file: the pipeline state is derived from the files (a story is planned if docs/plans/<id>.md exists, shipped if its review says `Ship allowed: yes` and the branch is merged) — a derived state can't go stale.

- Framing docs — docs/prd.md, docs/stories.md, docs/reviews/stories.md, docs/architecture.md, docs/design-system.md: committed on the default branch at the end of their phase. (docs/reviews/stories.md reviews the breakdown, not a story: it is a framing doc, unlike docs/reviews/<id>.md which travels with its branch.)
- Story docs — docs/research/<id>.md, docs/designs/<id>* (brief, md, html), docs/plans/<id>.md, docs/reviews/<id>.md: committed on feature/<id>. The implementer's single story commit brings the research, the design and the plan; /ks-ship commits the review. Every PR carries its own research, design, plan and review.
- Task progress — the checkboxes in docs/plans/<id>.md: the implementer ticks each task as it lands, and they travel in the story's commit. The plan file is the live progress tracker, never a commit trigger.
- Commits — **one commit per story**, not one per plan task. A second commit only for something you would want to revert on its own (typically a migration). The branch's commits are squashed at merge, so the default branch gets one commit per story.
- Decisions — docs/decisions/NNN-<slug>.md (MADR format, @templates/adr.md): one file per structural decision, with the considered options and why they were rejected. Immutable: a change means a new ADR superseding the old one. Framing decisions commit on the default branch; story decisions travel with feature/<id>.

## Technical conventions
<< IP Mike: boilerplate structure, stack, patterns, naming, commit rules. >>

## Definition of Done (per feature)
- Single PR, structured description, readable diff
- Passing tests on business logic
- No regression on existing code
- Review passed (no open critical issue)
- Deployed to production
