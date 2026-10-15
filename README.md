# cpto-skills

Claude Code skills from the operating model of a small product and engineering team
that ships most of its pull requests through agents.

These skills are extracted from daily use: several hundred pull requests a month,
reviewed by humans, opened and maintained by Claude Code sessions that run in parallel
on the same repository. Each rule in them exists because something broke without it,
and most of them cite the measurement that justified it.

They are opinionated. They assume GitHub, a project board with a Status field, and a
team where each domain has one named owner.

## The operating model in five rules

1. **Autonomy by default, the checkpoint comes after.** An agent decides how, writes the
   code, and opens the pull request. The domain owner decides on the diff. A diff is
   faster to judge than an intention.
2. **The decision level routes the work.** Code choices go straight to a PR, whatever
   their size. Architecture choices (would it deserve an ADR?) and methodology that does
   not exist yet get a sync before code.
3. **Ownership stays with humans.** Every issue has exactly one assignee. Every PR names
   its decisions, the alternative set aside, and the person who ratifies each one, with
   "ratify or correct".
4. **Two text surfaces.** What a human reads is capped and opens on the verdict. What an
   agent reads is generous and lives in a folded `<details>` block of the same artefact.
5. **Nothing lives only in a conversation.** Before a session ends, decisions go to git,
   the PR, the issue, or memory. Parallel sessions each work in their own worktree.

## Skills

| Skill | The problem it solves |
|---|---|
| [`spec`](skills/spec/SKILL.md) | Designs written before reading the code start from false premises. Writes product design and tech spec in one pass, then asks one question: autonomy or sync. |
| [`gate`](skills/gate/SKILL.md) | Weighted scores compensate and cannot be re-read. Ten ordered yes/no gates with early exit. It advises with a comment and a label, and decides nothing. |
| [`open-pr`](skills/open-pr/SKILL.md) | PRs opened by hand skip checks and land in nobody's queue. Layer checks first, numbered decisions with ratifiers, reviewer reading levels, a test plan runnable cold. |
| [`review-pr`](skills/review-pr/SKILL.md) | Agent reviews that list twelve nits and block on style. A materiality threshold, P0-P5, only verified P0/P1 block, subagents required on large diffs. |
| [`fix-review`](skills/fix-review/SKILL.md) | Review rounds that stall on conflicts and red CI. Merges the base on real conflicts only, gives back what it cannot resolve, one CI repair round. |
| [`wt-new`](skills/wt-new/SKILL.md) | Parallel sessions that corrupt each other in a shared checkout. Creates an isolated worktree first, then starts the work inside. |
| [`clearable`](skills/clearable/SKILL.md) | Context lost at `/clear`. Checks git, the PR, and unwritten decisions, then gives two verdicts: GO / NO-GO and v1 that holds / follow-up. |
| [`say`](skills/say/SKILL.md) | Ten parallel sessions and no time to read every answer. A spoken briefing that opens on the subject and closes on the next action, with the transcript on screen. Briefings from parallel sessions queue instead of cutting each other off. macOS only. |
| [`handoff`](skills/handoff/SKILL.md) | Delegation that makes the next person replay your iteration. A takeover file with "Decided" and "Yours to decide", and a status that names the act asked. |
| [`product-critique`](skills/product-critique/SKILL.md) | Self-review by the agent that wrote the thing. Simulated personas fed with real verbatims, blind judges, and a pre-mortem, all isolated, with a convergence rule. |
| [`headless-jobs`](skills/headless-jobs/SKILL.md) | Cloud routines cannot reach your local secrets and guardrails. Schedules `claude -p` with macOS `launchd`, paired with a fail-closed allowlist. |
| [`writing-voice`](skills/writing-voice/SKILL.md) | Agent prose that is 4.5 times longer than the message it answers. Caps by reply or deposit, a register indexed on the act asked, banned idioms with measured frequencies. |
| [`nope`](skills/nope/SKILL.md) | Banned-phrase lists that grow and stop working. A team register of irritants, promoted into positive, countable rules once two people hit the same one. |

| Output style | |
|---|---|
| [`simplified-technical-english`](output-styles/simplified-technical-english.md) | ASD-STE100 for every English sentence an agent writes: one meaning per word, active voice, 20 words per instruction, the project catalogues as vocabulary. |

## Install

As a Claude Code plugin:

```
/plugin marketplace add cyphalle/cpto-skills
/plugin install cpto-skills@cyphalle
```

Plugin skills are namespaced: `/cpto-skills:spec`, `/cpto-skills:open-pr`. The same
marketplace also offers [`agent-guardrails`](https://github.com/cyphalle/agent-guardrails).

Then fill in your team facts, whatever the install method:

```bash
mkdir -p ~/.claude/skills
curl -fsSL https://raw.githubusercontent.com/cyphalle/cpto-skills/main/config.example.md -o ~/.claude/skills/config.md
```

Without the plugin system, clone the repo and symlink the skills, unprefixed:

```bash
git clone https://github.com/cyphalle/cpto-skills ~/src/cpto-skills
cd ~/src/cpto-skills
./install.sh            # symlinks every skill into ~/.claude/skills
```

To install one skill only:

```bash
ln -s "$PWD/skills/spec" ~/.claude/skills/spec
```

To use the output style in one repository, copy it to `.claude/output-styles/` and select
it with `/output-style`.

## Configuration

The skills read team-specific facts (owners, handles, branch convention, board statuses,
check commands) from `~/.claude/skills/config.md`. See [`config.example.md`](config.example.md).
A skill never guesses a handle: when a value is missing, it stops and names it.

## Status

These skills run in production on a real team. The generic versions here drop
company-specific IDs and paths, so expect to adapt the checks and the board helpers to
your setup. Issues and pull requests are welcome.

## Author

Cyprien Hallé ([@cyphalle](https://github.com/cyphalle)), Chief Product and Technology Officer.

## License

MIT. See [LICENSE](LICENSE).
