---
name: nope
description: "Record, in three seconds, something a model wrote that irritated you into a shared team register. Read the register, or promote an entry that enough people reported into a positive, countable rule. Use when the user types /nope, or says a model output annoys them: a turn of phrase, a tic, a formatting habit, a behaviour such as tagging people on the wrong topics."
---

# nope

Catch an irritant at the moment it irritates. That moment lasts a few seconds, and it is
the only moment where you remember the exact wording that bothered you.

The register lives in `.agents/irritants.md` of the repository. It is a queue. Entries
wait there until enough people hit the same thing. Then they are promoted into a rule that
actually applies, and they leave the queue.

## Why a queue and not a list of bans

A list of forbidden phrasings that only grows works against itself. Telling a model to
avoid forty specific formulas raises their salience and prescribes nothing in their place,
and a list nobody prunes reaches eighty contradictory entries within months.

The rules that hold are positive and countable: one meaning per word, active voice, twenty
words per instruction (see the Simplified Technical English output style in this
repository). The register exists to feed rules of that kind.

## Record an entry

`/nope "<what bothered you>"`, or `/nope` alone to take what just appeared.

1. **Normalise it.** "That thing it always does with dashes" is not actionable. Turn it
   into a named pattern with one real example, taken from the conversation where you can.
2. **Look for it in the register first.** The same pattern under different words is the
   common case. Add one more `reported by` line to the existing entry, even when the
   reporter is already listed: the count of those lines decides promotion, so splitting an
   entry in two hides the signal.
3. **Show the entry and ask before you push it.** The `example` field is verbatim text from
   your conversation, and the branch is shared with the whole team. It can carry a customer
   name, a figure, a path or a secret. Show the entry, offer to trim it, and push only on an
   explicit yes. On a no, keep the entry local and say so.
4. **Write the entry**, then commit and push to a long-lived shared branch (for example
   `chore/irritants`).

   **Write from a dedicated worktree.** `/nope` fires mid-session,
   so the current branch almost always carries work in progress. Checking a shared branch
   out there, or stashing to make room, risks that work for a three-line commit.

   ```bash
   REPO=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
   WT="${REPO}-worktrees/chore-irritants"
   git -C "$REPO" fetch origin --prune
   [ -d "$WT" ] || git -C "$REPO" worktree add "$WT" chore/irritants 2>/dev/null \
     || git -C "$REPO" worktree add -b chore/irritants "$WT" origin/<base>
   git -C "$WT" pull --ff-only
   ```

   Every later command reads `git -C "$WT"`, and the file you edit is
   `$WT/.agents/irritants.md`. If the push is rejected, pull with rebase, re-read the
   register, fold your entry into one that arrived if it is the same pattern, and push
   again. Never force-push this branch: you would drop somebody else's irritant.
5. **Say whether the threshold is reached**, and stop. Promoting is a separate act.

```markdown
### <pattern name>
- reported by: <login> (<date>)
- reported by: <login> (<date>)
- language: <language>
- kind: wording | behaviour
- example: "<the actual text that irritated>"
- instead: <what to do in its place, if known>
- note: <a boundary a reporter drew, if any>
- status: <waiting | at threshold + where it should go>
```

`instead` is the field that matters most and the one people skip. An entry without it can
only be promoted into a ban, which is the weak form. Ask for it when the reporter has an
opinion. Leave it empty rather than inventing one.

## Read the register

`/nope --list` prints the register grouped by state:

1. **At threshold**, with the target file for each.
2. **Waiting**, with the report count.
3. **The cap**: active entries out of twenty, and the candidates to drop.

Write nothing back on a `--list`.

## Promote an entry

An entry is ready when **two different people reported it, or one person reported it three
times**. One person irritated once is a preference. The same thing hitting two people is a
team convention waiting to be written.

**One narrow exception.** A `behaviour` entry reported by the person who carries its cost
is ready on a single report. Over-tagging someone is visible to that person alone, so a
second reporter would be someone it costs nothing, and waiting for one waits forever.

Where it goes:

- **English wording**: a rule in the output style.
- **Wording in another language**: the writing conventions file for that language.
- **Behaviour**: wherever that behaviour is decided. Being tagged on the wrong topics
  belongs with the reviewer rules.

Never create a target file as a side effect of a promotion. A rules file born from one
entry has nobody behind it.

## Turn a negative into a positive

This step decides whether promotion is worth anything. "Do not write X" flipped into
"avoid X" is still a ban wearing a different hat.

**Name what the phrasing was trying to do.** Nobody writes a tic out of malice. The
seesaw "it's not X, it's Y" is someone reaching for a contrast. The em dash is someone
avoiding a choice between a comma, a colon and a full stop. Padding is someone unsure
which part matters. The positive rule tells them how to do that same thing well, which is
why it holds where a ban does not.

**Write it as an instruction you can follow while writing.** "Be elegant" cannot be
followed. "Choose the punctuation that names the relation: a colon explains, a full stop
breaks, a comma joins" can.

**Make it checkable**: a number, a closed list, or a question with one answer.

**Test it on someone who never saw the irritant.** If the rule only makes sense to people
who know the forbidden phrasing, it is still a ban.

| Irritant | The intent behind it | The rule that replaces it |
| --- | --- | --- |
| "it's not X, it's Y" | mark a contrast | State the option you keep and why. Name the discarded one only when it was plausible. |
| em dash in prose | avoid choosing a punctuation | Choose the mark that names the relation: colon explains, full stop breaks, comma joins. |
| prose that stays long | unsure what matters | Give a character count. Count, and rewrite before showing. |
| tagged on the wrong topics | unsure who owns what | Tag each owner on their listed domains, and on any question a human asked them. Nothing else. |

**When you cannot find the intent, do not promote.** A phrasing that irritates one person
and serves no purpose anyone can name is a preference. This test keeps the standard from
filling with personal taste.

## Keep the register small

Twenty active entries at most. Past that, the register has stopped being a queue. Promote
what is ready, and drop what one person reported once and nobody hit again. An irritant
that never recurs was a bad day.

## Side effects

- Creates or reuses a worktree on the shared `chore/irritants` branch.
- Commits and pushes the register entry, after your explicit yes in step 3.
- `--list` writes nothing.
