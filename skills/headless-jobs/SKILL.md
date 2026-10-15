---
name: headless-jobs
description: "Create, list or remove a local macOS launchd job that runs `claude -p` headless on a schedule (for example `/headless-jobs \"/briefing\" every weekday at 9`). Runs on your machine with your secrets and your guardrail hooks, unlike cloud routines. Subcommands: --list, --remove <slug>."
---

# headless-jobs

Manage local `launchd` jobs that run `claude` headless on a schedule. Local, so the job
reads your `.env` files, your CLIs, and your hooks (a local `claude` reads
`~/.claude/settings.json`). The trade-off: the machine must be awake. If it sleeps at the
scheduled time, `launchd` runs the job on wake.

A good pattern is one always-on machine (an old laptop on a shelf) that holds every
scheduled job, while your main machine stays free.

## Constants

- **The real `claude` binary.** Your shell `claude` is often an alias that does not exist
  under `launchd`. Resolve it with `zsh -ic 'unalias claude 2>/dev/null; command -v claude'`
  and use the absolute path.
- **Jobs folder**: `~/Library/LaunchAgents/`
- **Label**: `com.<you>.claude.<slug>`
- **Logs**: `~/Library/Logs/claude-<slug>.log`
- **Domain**: `gui/$(id -u)`

## Pair it with a guardrail

A headless job has no human in front of it. Set the environment variable
`CLAUDE_GUARD_SCHEDULED_JOB=<slug>` in the plist, the name the
[`agent-guardrails`](https://github.com/cyphalle/agent-guardrails) hooks read. A PreToolUse
hook reads it and allows only the irreversible actions listed for that slug in an
allowlist, fail-closed: a slug missing from the allowlist is a deny.

The variable is a label, not a proof. Any session can launch a child process with it set,
so a hook must not trust it alone. `agent-guardrails` ignores it when a `claude` process is
an ancestor of the one that carries it, which is the case of a session that launches
another `claude` itself. A hook of your own must make the same check.

## Permissions

The plist below runs the job with the permission rules of your settings. Nobody can answer
a prompt, so any tool call those rules do not allow is refused. Allow the exact tools the
job needs, in `permissions.allow` of the job's settings or with `--allowedTools`.

`--dangerously-skip-permissions` is opt-in. It lets the job run any tool call, including
one requested by content the job reads: an email, an issue, a web page. Add it only for a
job whose inputs you control, and only with a PreToolUse guardrail installed.

## Create

1. **Parse**: the job is the quoted text (a slash command or a free prompt). The rest is
   the schedule in natural language. Slug from the command name, or from the first 3-4
   words. Suffix `-2` on collision. Working directory: the current one, or `--cwd`.
2. **Map the schedule** to plist keys, in local wall-clock time:

   | Natural language | Plist key |
   |---|---|
   | every day at 9 | `StartCalendarInterval` `{Hour:9, Minute:0}`, no Weekday |
   | weekdays at 9 | an array of 5 dicts, `Weekday` 1 to 5 |
   | Monday at 8 | `{Weekday:1, Hour:8, Minute:0}` |
   | every hour | `{Minute:0}` |
   | every 15 min | `StartInterval: 900` |
   | at 9 and 18 | an array of two dicts |

   `Weekday` takes one integer. A range is invalid: Monday to Friday is five entries. 0 or 7 is
   Sunday. If the schedule is ambiguous, ask. Do not guess.

3. **Generate the plist.** Escape `&`, `<`, `>` in the job text.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.YOU.claude.SLUG</string>
    <key>ProgramArguments</key>
    <array>
        <string>/ABSOLUTE/PATH/TO/claude</string>
        <!-- Opt-in, see "Permissions": the job then runs any tool call, including one
             requested by content it reads. Only with a PreToolUse guardrail installed.
        <string>--dangerously-skip-permissions</string>
        -->
        <string>-p</string>
        <string>JOB</string>
    </array>
    <key>WorkingDirectory</key><string>CWD</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key><string>/Users/YOU</string>
        <key>PATH</key><string>/Users/YOU/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>CLAUDE_GUARD_SCHEDULED_JOB</key><string>SLUG</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
    <key>StandardOutPath</key><string>/Users/YOU/Library/Logs/claude-SLUG.log</string>
    <key>StandardErrorPath</key><string>/Users/YOU/Library/Logs/claude-SLUG.log</string>
    <key>RunAtLoad</key><false/>
</dict>
</plist>
```

4. **Dry run, then confirm.** Show the path, the XML, and a plain summary: "Runs `<job>`
   <schedule> in `<cwd>`. Logs in `<log>`." Write nothing before an explicit yes. Add
   `--dangerously-skip-permissions` only when the user asks for it, and repeat its risk in
   the summary.
5. **Write and load.**

```bash
launchctl bootout gui/$(id -u)/com.YOU.claude.SLUG 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.YOU.claude.SLUG.plist
launchctl print gui/$(id -u)/com.YOU.claude.SLUG | grep -E "state|program"
```

6. **Offer a test now** with `launchctl kickstart -k gui/$(id -u)/<label>`, then show the
   end of the log. The first run is where you see whether the slash command runs, and
   whether auth and hooks pass.

## List

Read every `com.YOU.claude.*.plist`. Three shapes of `ProgramArguments` exist, and looking
for `-p` on all of them shows an empty job for two:

- `[claude, -p, "<prompt>"]`, with or without `--dangerously-skip-permissions`: the job is
  the `-p` value. Flag the jobs that carry it in the table.
- `[run-job.sh, <slug>, "<prompt>"]`: the job is the third argument.
- `[<script>.sh]`: the job is the script. A bash trigger can decide on its own whether
  there is anything to do before it spends a `claude` run.

Show a table: slug, job, schedule, cwd, loaded state, log.

## Remove

Ask first, then bootout and delete the plist. Keep the log.

## Pitfalls

- A new plist synced to another machine by git is not loaded there by itself. Run the
  install step on that machine and check `launchctl list | grep <label>`.
- Never pipe a long test run into `head`: SIGPIPE kills the producer silently and the log
  looks green.
- A job that posts somewhere must post a verdict in its first line. A parent message that
  only says "exit 0, 18 min" buries good content where nobody reads it.

## Side effects

- Create writes and loads a plist only after an explicit yes. Remove deletes one only after
  an explicit yes.
- Once loaded, the job runs on its schedule with nobody in front of it, with your secrets,
  and posts or writes whatever its prompt tells it to.
