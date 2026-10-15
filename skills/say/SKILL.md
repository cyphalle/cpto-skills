---
name: say
description: "Speak an oral briefing of the previous answer, or of the content behind a link, out loud on macOS. Longer and more complete than a status line, with a context sentence first and the next action last. The spoken text is also shown on screen, word for word. Briefings from several parallel sessions wait in a shared queue instead of cutting each other off. Subcommands: /say, /say <angle>, /say <link>, /say queue, /say skip, /say flush, /say stop. Use when the user types /say, or asks to hear an answer, a thread, a page or a PR read out as a briefing."
---

# say

`/say` speaks a briefing of the **previous answer**, or of the **content behind a link**
given as argument. It is a one-off gesture: nothing stays on after it.

Requirements: macOS (`/usr/bin/say`). The queue script `say-queue.sh` sits next to this
file, in the base directory of the skill.

## Why

When five to ten agent sessions run in parallel, you cannot read every answer. You can
listen to them while you do something else. Two things break the naive version:

- **The listener has no context when the voice starts.** A briefing that opens on the
  substance makes them rebuild the subject during the first ten seconds, and they lose the
  start. So every briefing opens with one sentence that names the subject, and closes with
  one sentence that names the next action.
- **Parallel sessions cut each other off.** The obvious implementation kills any running
  `say` before it speaks. `pkill -x say` kills every `say` process on the machine, so three
  briefings launched in a row leave only the last one alive. Here, briefings go to a queue
  on disk and one elected reader plays them in order.

## Step 1: resolve the source

| Invocation | Source |
|---|---|
| `/say` | the last assistant answer, already in context |
| `/say <angle>` | same, framed on that aspect |
| `/say <link>` | the content behind the link, **not** the previous answer |
| `/say <link> <angle>` | the content behind the link, framed on that aspect |

Four arguments are orders to the queue, not subjects. Route them to "Queue commands" and
write nothing: `queue` (or `status`), `skip`, `flush`, `stop`.

Without a link: do not reread the conversation history, do not run a new analysis.

With a link: fetch it **before** writing, with the matching tool.

| Link | Fetch with |
|---|---|
| Slack thread | the Slack connector, if one is attached. Rebuild the timestamp from the `p…` path segment: drop the `p` and insert a dot six digits from the end (`p1785318960376619` → `1785318960.376619`). If the URL carries a parent thread parameter, read that one. |
| Notion page | the Notion connector |
| GitHub issue, PR, commit | `gh` |
| YouTube | the video transcript |
| any other URL | a web fetch |

If the fetch fails, say so and stop. Never brief on guessed content. If the link needs an
authentication that is missing, report it instead of working around it.

## Step 2: write the briefing

Write in the user's language. On fetched content, describe **what the source says**: who
says what, what is settled, what stays open.

Five beats, never announced:

1. **Anchor.** One sentence, fifteen words at most: the subject in plain words and where it
   comes from. "We are still on the two-level pricing card." "This is this morning's Slack
   thread about expiring cloud credits."
2. What was done or established.
3. The two or three points that matter.
4. What remains, or the question asked.
5. **Next.** One sentence, fifteen words at most: the next action and who carries it.
   "I am waiting for your call on the format." "Next I run the tests, nothing for you to
   do." "Nothing to decide, this is background."

Chain the beats as speech ("first", "then", "so", "on the other hand"), never as a flat
list. Be complete on substance and drop every implementation detail that changes nothing
for the listener.

### Length

| Size | Words | Use |
|---|---|---|
| Standard | 90 to 160 | the default, the vast majority |
| Extended | 160 to 280 | when the substance really overflows |
| Long | 280 to 430 | rare |

430 words is a hard ceiling. Above it, split into two framed `/say` calls.

Going past the standard size needs a countable reason in the source: three or more
independent decisions, a multi-voice thread whose positions diverge, work shipped in
several slices the listener has not seen, or a decision the listener must make (then the
options and their cost belong in the briefing). A long previous answer is not a reason, nor
is technical detail. Rewrite once at standard size before concluding it does not fit.

The queue is shared: ninety seconds here is ninety seconds of waiting for every other
session. On a long briefing, pass `--rate` with a slower pace for that one deposit.

### Forbidden in the spoken text

- URLs, paths, file names, extensions;
- function, variable, class or command names, code;
- markdown, emoji, version numbers, identifiers.

Translate instead of spelling. Numbers that matter are written out in words ("thirty-nine
milliseconds"). A technical name becomes what it does: not "the Stop hook" but "what runs
at the end of my answer".

## Step 3: speak

Replace `<<<BRIEFING>>>` with the text and run, with `<skill dir>` set to the base
directory of this skill:

```bash
"<skill dir>/say-queue.sh" add --label "$(basename "$PWD")" <<'BRIEFING_EOF'
<<<BRIEFING>>>
BRIEFING_EOF
```

The heredoc is quoted, so apostrophes, backticks and `$` pass through untouched. No line of
the briefing may equal `BRIEFING_EOF`.

`--label` only feeds `/say queue`, so the listener knows which work each waiting briefing
comes from. On a link, prefer a readable label (`--label "Slack cloud credits"`).

## Step 4: confirm and show the transcript

Print the confirmation line the script returns, as is, then the briefing as a block
quote, word for word. Nothing else.

```
🔊 137 words · ~41 s · default voice at 200 wpm

> We are still on the two-level pricing card. First, …
```

When another session is speaking, the script returns
`🔊 queued (2 waiting) · starts in ~1 min 10 · 137 words · ~41 s`. That is the expected
behaviour. Never offer to cut the current briefing to go first.

The transcript catches up with the voice: the briefing may be queued behind two others, a
number may be hard to hear, the sound may be off. It must be the exact spoken text, never a
summary of it and never enriched with the links or file names the spoken version forbids.
A transcript that differs from the voice is worse than none.

## Queue commands

```bash
"<skill dir>/say-queue.sh" status   # /say queue: who speaks, who waits, estimated wait
"<skill dir>/say-queue.sh" skip     # /say skip: cut the current briefing, play the next
"<skill dir>/say-queue.sh" flush    # /say flush: empty the queue, let the current one finish
"<skill dir>/say-queue.sh" stop     # /say stop: cut everything and empty the queue
```

How the queue works:

| Mechanism | Why |
|---|---|
| Reader elected with `mkdir` | the only atomic exclusion primitive POSIX guarantees |
| Job file named with a microsecond timestamp | lexical order equals arrival order, no shared counter |
| Write to a temp file, then `mv` | the reader never sees a half-written job |
| Reader PID stored in the lock | a dead reader is detected and replaced on the next deposit |
| Jobs older than 30 minutes purged | a killed session leaves no ghost briefing |

The reader stops by itself when the queue is empty. No daemon to install.

`--kind voice` exists for a per-turn hook that speaks a short summary after every answer: a
new `voice` job replaces the waiting and playing `voice` job of the same session, and never
touches a `/say` briefing or another session's summary.

## Configuration

Optional, in `~/.claude/say-config` (sourced as shell):

```sh
VOICE_NAME="Ava (Premium)"   # a voice listed by `say -v '?'`; empty = system voice
SAY_RATE=200                 # words per minute
VOICE_PITCH=                 # base pitch ([[pbas N]]), empty = the voice's own
```

`say` does not reject an unknown voice name: it falls back silently to the system voice.
Check the name against `say -v '?'` before writing it.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Nothing is spoken | `/say queue`: "Silent" with a non-empty queue means a stuck lock, see next line |
| `stuck reader lock` | a foreign file sits in `~/.claude/say-queue/.runner`; empty that folder by hand |
| The briefing does not start at once | another session is speaking; `/say queue` shows the wait |
| Wrong language | `VOICE_NAME` is invalid or speaks another language |
| "I do not know what this is about" | the anchor is missing or vague; it must name the subject |
| The briefing ends with no next step | the closing sentence is missing |
| The transcript differs from the voice | the text was reworded between deposit and display |
