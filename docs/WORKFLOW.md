# How the project is run

English · [Русский](WORKFLOW.ru.md)

The working method, not a description of the widget. Read once; in each session
`STATE.md` and the last `JOURNAL.md` entry are enough.

## Roles

**The main session runs the project.** It holds the intent, makes the decisions, writes
the journal and commits. It must not drown in details — that is what agents are for.

**Agents research and build.** Everything that takes digging through many files or
working out an unfamiliar API goes to an agent. It returns a **conclusion**, not dumps:
the main session gets an answer, not the contents of twenty files.

What to hand to agents:
- reconnaissance — "how is config/main.xml built in plasmoids", "which data sources are
  available in QML on Plasma 6", "how other plasmoids read /proc";
- independent pieces of the implementation — several at once, in parallel;
- checking someone else's work — a separate agent looks with fresh eyes.

What **not** to hand over:
- decisions about the project's direction;
- writing the journal and the state;
- commits.

## Journal and state are two different files

| File | What is in it | How it changes |
|---|---|---|
| **`STATE.md`** | where the project is **right now**: what works, what is in progress, open questions, the next step | **rewritten** in full |
| **`JOURNAL.md`** | how we got here: one entry per session | **appended only**, we do not touch the old entries |

Why two. `STATE.md` answers "what to do next" and must be readable in a minute — if you
append to it, it turns into a dump. `JOURNAL.md` answers "why it turned out this way"
and is valuable precisely for what it accumulates: it holds the dead ends and the
reversed decisions that you would otherwise walk into again.

⚠️ **Failures** go into the journal too: what we tried and why it did not work. The entry
"rewrote it through X, did not help, reason Y" is worth more than three entries about
successes — it saves a repeat attempt.

## Closing a session

It starts when the context is running out or the work has reached a sensible stopping
point. Anyone can initiate it: the user with the word «закрываем» ("closing"), or the session itself,
noticing that little context is left.

Step by step, skipping none:

1. **Check the state by running it**, not from memory: what actually works and what does not.
2. **Rewrite `STATE.md`** — the current position and a clear next step.
3. **Append an entry to `JOURNAL.md`** — the date, what was done, what was verified, what
   did not work out, where we stopped.
4. **Commit and push.** Uncommitted work does not exist for the next session.
5. **Say that the session is closed**, and briefly — what to continue with.

## Opening a session: «продолжаем»

The word «продолжаем» (or «продолжим») — "let's continue" — at the start of a session means
a full pick-up.
The order:

1. Read `STATE.md` — what we are doing.
2. Read the **last** `JOURNAL.md` entry — what we ran into last time.
3. Look at `git log --oneline -10` and `git status`.
4. **Check the state by running it** — `./install.sh --status` and whatever the task needs.
   The document may have fallen behind the facts; the facts win.
5. Report in a few lines: where the project is, what changed since the last entry, what
   is proposed to do — and start.

⚠️ Do not retell `STATE.md` in full — the user will read it themselves. The report is
there so that they can confirm the session picked up correctly.

## Writing rules

- **Language.** `STATE.md` and `JOURNAL.md` are the working log and stay in Russian.
  Everything written for readers of the repository — `README`, `CONTRIBUTING`, `GOTCHAS`,
  `DECISIONS`, this file — is English first, with a `FILE.ru.md` mirror kept in step in
  the same commit. Code comments are English.
- **Verified by running it**, not from memory. If a claim can be executed — execute it.
- **Short.** `STATE.md` — one screen at most. A journal entry — two screens at most.
- **No retelling the code.** Code is read in the code; the journal gets what is not
  visible in it: why it is this way, what was tried before, how that turned out.
