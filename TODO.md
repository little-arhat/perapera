# TODO

Outstanding work on the Fluent macOS app, as numbered tickets so they can be
referred to by name. Each says what, why it matters, and where in the code.

Priority is by **learner impact**, not by effort. `S`/`M`/`L` is rough size.

---

## Reported 2026-08-29 — working through these

### FL-22 — Translation on hover · M
Some sentences are hard enough that the meaning is the blocker, not the script.
Hovering a word already highlights it; showing a gloss there would be the
natural home. Needs a source of glosses — the generator could supply per-item
translations cheaply, since it already knows them.

### FL-23b — Kanji/script drills from fonts (Track A) · M
Track B shipped; this is the free half still outstanding. Render the same word
in brush, signage, rounded and textbook faces — 57 already installed — and drill
the confusable pairs (シ/ツ, ソ/ン, ね/れ/わ, ぬ/め, る/ろ). No network, no
verification, no cost, so it can appear in every lesson where photographs
cannot.

### FL-23 — Photographs (Track B) · DONE, see below



---

## Requested 2026-09-01 — building these

### FL-28a — Translation on hover · M
Hovering already highlights a word and clicking copies it. Showing its meaning
there needs a gloss source: the dictionary can answer for saved words at no
cost, but an arbitrary word in a passage cannot be looked up without either a
dictionary file or a call. Do the free half first — hover a word that is already
saved, see its gloss — and decide about the rest afterwards.

---

## Blocked on a decision

### FL-1 — Script recognition: pick a track · L
Reading kana on screen and reading it on a noren are different perceptual
tasks; the app currently trains only the first. Researched in full, with costs
measured: `docs/research/script-recognition.md`.

Two tracks, and the decision is whether to ship A alone first:

- **Track A — rendered.** Free, offline, exact, no new service, no verification.
  57 installed font families already span brush, signage, rounded and textbook.
  The natural home for the confusable pairs that actually break — シ/ツ, ソ/ン,
  ね/れ/わ, ぬ/め, る/ろ. Roughly two days.
- **Track B — photographic.** Generated and verified. Real transfer, and it
  doubles as menu-reading and price-parsing. Roughly a week, and it needs
  lesson assets, an OpenRouter path, and a verifier.

**Recommendation: ship A alone first.** It needs nothing the app does not
already have.

### FL-2 — Price discovery for image models · M
**First real run is done** (2026-08-29, `--probe dakuten`, $0.246), and it
reproduced the finding the tool exists to catch:

| model | $/image | fidelity | $/usable | verdict |
|---|---|---|---|---|
| `gemini-3.1-flash-image` | $0.0690 | 100% | $0.0690 | use |
| `gemini-3-pro-image` | $0.1378 | 100% | $0.1378 | use |
| `gemini-2.5-flash-image` | $0.0392 | 50% | $0.0783 | REJECT — drew みなみりぢち |

Note `gemini-3-pro-image` at **$0.1378** — double the flash model for the same
100%. Nothing in the catalog said so; it was only knowable by spending it.

**What is still missing is discovery.** Price is currently learned only by
paying for a generation, one model at a time:

- The catalog is not merely incomplete but wrong — it quotes $0.0000003 per
  token for a model that bills $0.0392 per image.
- `--discounts` reads `/models/{id}/endpoints`, but that has never been checked
  against a *measured* per-image price, so we do not know whether the endpoint
  data predicts the bill or is equally unrelated.
- Nothing notices when a price moves. `store.movement` exists and renders, but
  only across runs a human remembered to do.

Wanted: a cheap sweep that estimates per-image price without a full benchmark
(one probe per model, or endpoint data if it turns out to correlate), plus a
scheduled re-run so a price change is noticed rather than discovered in a bill.

### FL-3 — Move lesson generation off Opus · S
At five images the lesson JSON ($0.58, measured over 3 runs) costs *more than
the pictures*. Sonnet would be roughly a tenth of that. The open question is
whether generation quality holds — it is the call that shapes every lesson, so
it is worth an A/B rather than a blind switch. Grading cost has never been
measured at all.

---

## Next

### FL-7 — Tint particles by role · M
Word highlighting is in; colouring は/を/に/で distinctly is the other half, and
would make the particle drills readable at a glance. Needs the tokenizer to
classify, not just segment — `RubyCanvas.wordRange`.

### FL-8 — Better segmentation · M
`NLTokenizer` splits 新幹線 into 新+幹線 and まどぐち into まど+ぐち. Good enough
to hover, wrong often enough to notice. Blocks FL-7 from being trustworthy.

### FL-9 — Retry one exercise, not the whole lesson · M
A single malformed exercise currently costs a full regeneration. `LessonService`
already validates per-exercise (`Lesson.validate`), so the information needed to
retry precisely is there.

---

## Soon

### FL-10 — Generate several lessons at once · M
For stocking up before a flight. One button, N lessons, one progress indicator.
The offline path is already complete; this is the missing half of it.

### FL-11 — Theme and colour settings · M
Solarized light/dark follows the system with no override. Wants explicit
light/dark/auto, and ideally an alternate palette. `Theme.swift`.

### FL-12 — Progress dashboard · M
Streak and due count show on the home screen, but there is no accuracy trend or
mastery view. `/fluent-progress` in the terminal still does this better, which
is the wrong way round.

### FL-13 — Archive filters · S
Text search only. No filter by state or date. `ArchiveView`.

### FL-14 — Re-check lesson length · S
Baselines are 10 / 18 / 30 *items*; a medium run produced 13. Judge by how long
a sitting actually takes before changing anything.
`LessonService.exerciseTarget`.

---

## Known issues

### FL-15 — `LessonPlayerView` keeps its own copy of the record · M
It holds `@State var record` and pushes updates to `AppModel`. Two copies of one
identity. It works because only the player writes, but that is exactly the
identity/state braiding that causes bugs later — and it already caused one (see
the answer-leak entry below, which was the same shape). Should read through the
model.

### FL-16 — Generators sometimes accept a wrong answer · S
One run listed `お` alongside `を` in `acceptedAnswers`. Accepting a wrong
particle teaches the wrong thing. There is no cheap local check for semantics;
if it recurs, have the teacher audit accepted answers at grading time.

### FL-17 — Ruby cannot appear in Picker rows · S
A `Picker` cannot host ruby, so matching-menu labels are stripped of readings.
Replacing the Picker with a custom control would fix it. Low priority.

### FL-18 — Column measure is wider than ideal · S
Deliberate: at the default size a line runs ~89 latin characters against a
textbook 65–75. The narrower column left half a large display empty, which read
as a mistake. The principled fix is to stop treating the page as one column —
keep *prose* at a readable measure while letting exercise *cards* span wider,
since cards hold short lines that do not suffer from width. `TextScale.width`.

---

## Done

### Sidebar, pictures and the dictionary (2026-09-01)
- **FL-26 — a sidebar.** Practice / Pictures / Saved / Archive. The app was one
  screen with an enum, which two new areas would not have fitted. Sections are
  kept separate from screens: a debrief is somewhere you are *sent*, not a
  destination you pick, and folding them together would have put "debrief of
  lesson 7" in the sidebar.
- **FL-27 — pictures are kept and reused.** A Review mode (random photo, type
  what it says, graded exactly as in a lesson) and a contact sheet with
  transcriptions. Each picture cost about $0.07 and was previously seen once;
  nothing about a sign goes stale, so re-reading one later is free practice.
- **FL-28d/e/f — word drills.** 5-10 saved words with fields, in either
  direction. JA→EN tests recognition, EN→JA tests recall — harder, and the one
  that matters for speaking, so answering in Japanese uses the kana field rather
  than an IME candidate list. Example sentences are revealed *after* answering,
  never before, since seeing the word in use gives the answer away. Kanji
  entries follow the same furigana toggle as lessons.
- **FL-28g — the teacher stocks the dictionary.** `newVocabulary` already went
  to Fluent's scheduler; it now also lands in the word list, with a reading and
  an example, and the prompt asks for the words a *newly opened topic* needs
  next rather than only those already met. Existing entries are enriched, never
  overwritten — the learner's own note outranks a generated one.
- Drill order is three tiers: answered-wrong first, then never-tried, then
  always-right. Demonstrated failure is stronger evidence of need than no
  evidence, which a test caught me getting backwards.
- **Collapsible home sections** with summaries, so a folded panel still says
  what it holds.

### Track B — reading Japanese off photographs (2026-09-01)
- **`recognition` exercises**: the app generates a photograph, verifies it, and
  the learner reads the sign. Proven end to end — a lesson asking for one
  produced a weathered enamel 駐車場 plate that verified on the first attempt
  for $0.068.
- **Verification is mandatory, not optional.** A model asked for みなみぐち has
  been observed drawing みなみりぢち. An image ships only if a read-back finds
  every requested string; otherwise it is retried once, then the exercise is
  dropped. Losing one exercise is the cheapest of the three bad outcomes —
  showing an unanswerable question or a wrong letterform are both worse.
- **Spending is explicit.** Photographs default to zero and the control states
  the cost ("about $0.21, generated and checked"); it is the only number in the
  app that is money. Capped per lesson.
- **Images live beside the lesson JSON**, one directory per lesson, deleted with
  it. Not embedded as base64, which would make the record unreadable in an
  editor and undiffable — the archive outliving the app is the point.
- **`imgbench suggest`** tracks whether a cheaper model has become viable.

### Speech and controls (2026-09-01)
- **FL-4/5/6 — a Speech section in Settings**: voice picker labelled by quality,
  a slow-speed slider with the stored value, a preview button, and a warning
  when only the basic voice is installed — with the four-level System Settings
  path spelled out and a deep link, since nobody finds it otherwise. Without
  the warning the learner concludes the robotic reading is as good as it gets.
- **Tooltips on size and depth**, and the numbers in the labels, so "Varied"
  cannot be read as a mood.

### Reported 2026-08-29, fixed (2026-09-01)
- **FL-24 — a "Where you are" panel**, least finished first, from Fluent's own
  spaced-repetition data. It had tracked category and mastery all along;
  nothing read it. Bands rather than one bar, because "eight items, six new" is
  a different situation from "eight items, six nearly mastered" and a single
  percentage hides which. Tapping a topic aims the next lesson at it — writing
  it into the focus field rather than generating, since spending money on a
  click is the wrong kind of convenient. Partial progress counts: a half-learned
  topic must not read the same as an untouched one.
- **FL-19 — content overflowed the window**, clipping the instruction line. The
  Core Text view answered "how big would you like to be?" with its natural
  single-line width, which is right for a reorder token and wrong for anything
  that wraps. Hugging is now opt-in; wrapping text defers to its laid-out width.
- **FL-20 — answers were lost.** `advance()` restored the *revealed* flag from
  the saved answers but reset the draft, so a previously-answered exercise
  rendered its verdicts against an empty form — showing every item wrong with a
  blank field, for work that was right and still on disk. Draft and revealed
  state are now restored together. Also made the set-field resize
  non-destructive, gave each row's kana field its own identity, and seeded that
  field from its binding.
- **FL-21 — not a bug.** The lesson in question was generated `large + Varied`,
  and `light` *is* 3 items per set, so the app did what was asked. The fault was
  that "Varied" reads as a mood rather than a count. Depth labels now carry
  their number, the generator shows the concrete plan before spending
  ("8 exercises × 3 items ≈ 24 questions"), and the sizing moved into a shared
  `LessonPlan` so prompt and preview cannot disagree. One real shortfall did
  turn up alongside it: `large` asked for 8 exercises and the model returned 6
  and 4, so the prompt now states both numbers as requirements.
- **FL-25 — lesson rows show provenance**: question count, size and depth, how
  long ago it was generated, and state.

### Lesson labels (2026-08-29)
- **Name and note on a lesson**, set at generation time or added later via
  Rename. Kept on `LessonRecord` rather than `Lesson`: the generated lesson is
  an artifact that does not change, the label is the learner's and can be
  corrected at any point. Never sent to the model — `focus` is the instruction,
  the name is a label. Makes queuing several differently-configured lessons
  ahead of time actually usable.

Newest first. Kept because several exist only because a measurement contradicted
an assumption, and that is worth remembering.

### Layout and text rendering (2026-08-28 → 29)
- **Reorder tokens each took a full row.** `fittingSize` returned the width it
  was *offered* rather than the width used, and an unspecified proposal — what
  `FlowLayout` sends — fell through to a guessed 600pt. Now measures unbounded
  and returns used width: tokens 45–89pt, paragraphs still wrap.
- **Column too narrow on a wide display.** Widened ~50%, trading measure for a
  composed page. See FL-18.
- **Shrinking the text shrank the column**, cancelling the reason to shrink it.
  Width now never goes below its base.
- **Toggling readings reflowed the page.** The Core Text view was already
  stable; the preamble was rendering readings as 切符（きっぷ）parentheticals,
  which change the text's *length*. It now parses Markdown then applies real
  ruby — 272.0pt in both states, measured.
- **Selection only caught one fragment.** `RubyText` rendered one SwiftUI `Text`
  per segment, and selection cannot span separate `Text` views. Replaced with a
  Core Text view using `CTRubyAnnotation`. `NSTextView` was tried first and
  silently drops ruby.
- **Word highlighting on hover, click to copy**, via `NLTokenizer`.
- **Readings unreachable on set exercises** — the toggle keyed off `prompt`,
  which on a set is the English instruction. Now keys off everything displayed.
- **Hover did nothing**: a window does not deliver `mouseMoved` unless asked.
- **Text size control** (⌘+/⌘−/⌘0), one scale factor through the environment.
- **Window title bar restored** — `.hiddenTitleBar` cost double-click-to-zoom
  and the window menu for a slightly cleaner edge.

### Correctness (2026-08-26 → 28)
- **Study time was wall-clock.** A lesson left open overnight logged 1383
  minutes. Now accumulates active time, ignoring gaps over 5 minutes; old
  records fall back to a capped wall-clock. Corrupted totals repaired.
- **Answers leaked between exercises** — `KanaTextField` kept `@State` and
  SwiftUI reused the view, so text typed for one exercise would have been
  submitted for the next.
- **Correct Japanese marked wrong.** Cloze now accepts the blank-filled
  sentence, and grading has a third outcome: ambiguous answers go to the
  teacher. A reordering never defers — word order is what is being taught.
- **Grading was charged twice on a crash.** Feedback persists on arrival, in a
  `graded` state.
- **A finished lesson reopened at question 1.**
- **Listening exercises printed what was spoken** — a reading exercise in a
  costume. Generation rejects it.
- **Ambiguous prompts** — a gap with no instruction cannot say whether to type
  the fragment or the sentence. Generation rejects those too.
- **Blank matching row** from padded `pairs`.
- **Reorder answers rendered with spaces** — 京都 までの 切符.
- **Streak never started.** `update-db.py` keyed off `last_updated`, which
  `/fluent-setup` stamps at profile creation, so no learner's first session
  ever started a streak.

### Features (2026-08-26 → 28)
- Exercise **sets** — one instruction, numbered items, partial credit.
- **Breadth and depth** as separate controls.
- **Furigana**, **saved lists**, **comprehension passages**, **app icon**.
- **Kana input** with the IME bypassed, so production tests recall.
- **Japanese TTS**, unlocking listening practice.
- **Live streaming** of the model's output instead of a spinner.
- **`imgbench`** — picks an image model on fidelity, not price.

### Credentials
- The OpenRouter key is **`OPENROUTER_FLUENT`**, read from the environment or a
  gitignored `.env` at the repo root (`.env.example` shows the shape). Named per
  project rather than shared, so revoking it cannot break anything else.

### Measurements worth keeping
- Speech rate is non-linear: 0.375 → 4.6s vs 0.5 → 4.2s (inaudible); 0.3 → 5.6s.
- `isSpeaking` is false immediately after `speak()`; use the delegate.
- Image generation is flat per image regardless of prompt, content or
  resolution: **$0.069** for `gemini-3.1-flash-image`, **$0.138** for
  `gemini-3-pro-image`. Verification read-back is **$0.00059**. Lesson JSON on
  Opus is **$0.58**.
- `gemini-2.5-flash-image` is 43% cheaper and renders wrong kana (みなみりぢち
  for みなみぐち) — unusable at any price.
- macOS Vision OCR gives false negatives on vertical and angled Japanese; the
  vision-model read-back does not.
