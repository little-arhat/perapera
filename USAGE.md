# Usage

## The loop

Pick a **mode**, a **size**, a **depth** and optionally a **focus**, then press Generate.

- **Mode** — `lesson` teaches new material, `review` drills what spaced repetition says is
  due today.
- **Size** — small, medium or large. Size sets how many distinct points the lesson covers.
- **Depth** — Varied, Balanced or Drill. Depth sets how many items each exercise set
  repeats. Size × depth is the real length, and the home screen prints the arithmetic
  before you commit: `6 exercises × 3 items ≈ 18 questions, about 22 min`.
- **Focus** — free text. Leave it empty and the teacher picks from your error patterns,
  your due items, and what it wrote in `focus_next_session` after your last lesson.

Generation takes 30–60 seconds and streams as it goes, so you can watch the lesson being
written rather than a spinner.

Answer one exercise at a time. Answers are saved on every keystroke, so closing the window
mid-lesson loses nothing. Press **Finish lesson** when done.

## How grading works

The app grades locally and offline wherever it can. There are three outcomes, not two:

- **Decided** — multiple choice, reordering, matching, cloze and digit entry get an instant
  verdict with no network.
- **Needs the teacher, by design** — translation and free response are judgement calls.
- **Needs the teacher, close call** — an answer that overlaps an accepted one enough to be
  arguable. A reordering never defers: word order is the skill being tested.

Finishing sends only the open questions to Claude, along with what the app already decided.
One lesson becomes one Fluent session, written through `update-db.py`.

## Working offline

Generation and grading need the network. Everything between them does not. Generate several
lessons before a flight, do them in the air, and press Finish when you land. A completed
lesson waits in `completed` state until it can be sent.

Grading is charged once. If the write to Fluent fails after the teacher has graded, the
feedback is saved first and reused on retry rather than being paid for twice.

## Reading Japanese

Readings are hidden by default, because seeing furigana every time means never learning the
kanji. Toggle them per lesson. The ruby is real Core Text ruby, so selection spans the whole
line and toggling readings does not reflow the page.

Type Japanese directly. The app bypasses the system IME, so kana stay kana: typing tests
recall rather than recognition.

Text size is adjustable and persists. Word highlighting underlines the word under the
pointer and copies it on click, which is a genuine reading aid in a language without spaces.
Click a word for its meaning, to add it to your saved list, to copy it, or to open Jisho.

Playback speed is a stored value rather than a preset because the scale is badly
non-linear. Measured on one Japanese sentence: 0.5 takes 4.2 s, 0.375 takes 4.6 s and is
indistinguishable, 0.30 takes 5.6 s and is clearly slow. The default is 0.30.

## Saved words and drills

Star anything during a lesson. Saved items enter spaced repetition through the same path as
everything else when you finish the lesson, so there is one schedule rather than two. The
teacher also stocks the list: vocabulary it introduces is added automatically, and your own
note on an entry outranks a generated one.

Drill saved words in either direction, weakest first. Drill results feed the same schedule.

## Pictures

Recognition exercises use real generated photographs of Japanese text: a station sign, a
menu, a ticket window. Every image is read back by a second model before you see it, and
dropped if the writing came out wrong. A model asked for みなみぐち has been observed
drawing みなみりぢち, confidently, in an otherwise convincing sign, and a wrong glyph in a
reading drill teaches a wrong letterform.

You can also make one on demand from the Pictures screen and choose which scripts it may
use. Images cost about $0.069 each, so the per-lesson budget is yours to set, not the
model's. A lesson takes at most eight.

## What it costs

Every paid call is recorded with its model and purpose, and shown in the footer. Measured:
about $0.069 per image, $0.58 for a five-image lesson on Opus, and $0.67 to grade one
lesson. Moving generation to Sonnet in Settings is the main lever, and every call carries a
`--max-budget-usd` ceiling.

## The archive

Every lesson is one JSON file that accretes answers and then feedback, never overwritten, so
the archive shows what actually happened. Filter by grade, rename a lesson, annotate it, or
delete it with its images. The files are readable without the app and outlive it.

## Your own text

The **Scratch** pane takes any Japanese you paste and puts readings over the kanji.
Click a word for its meaning, to save it, or to look it up, the same as in a lesson.
A lesson is text the app chose; this is a menu you photographed, a line from a manga,
a sign you could not read.

Readings come from the system tokenizer, so this costs nothing and works offline. It
occasionally splits a compound in the wrong place (新幹線 comes back as 新 + 幹線), so
the readings are right more often than the word boundaries are. The pane says so.

What you paste is kept with the profile, not with the Mac, so it follows you when you
switch profiles.

## Profiles

A profile is one learner and one target language, with its own schedule, archive,
vocabulary and spending. Switch from the menu at the top of the sidebar; **New profile…**
creates one. Switching swaps everything together, so nothing from the previous learner
stays on screen.

There is no delete. Removing a profile removes a whole history, so **Reveal in Finder**
puts that decision where you can reconsider it.

## Terminal sessions

Fluent's skills still work, and do things the app does not:

```bash
cd fluent
claude
> /fluent-progress    # accuracy trends, mastery, streak
> /fluent-review      # today's spaced repetition
> /fluent-setup       # create or update a profile
```

The app and a tutor session write the same six databases through the same script, and it
takes a lock, so the second waits rather than quietly overwriting the first. If something
has held it for twenty seconds you are told which process, rather than left waiting.
