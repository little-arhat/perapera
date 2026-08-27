# TODO

Running list for the Fluent macOS app. Newest requests at the top of each
section; move items to **Done** with a one-line note on what actually changed.

## Next

### Speech
- [ ] **Better voices.** macOS ships only `.default`-quality voices out of the
      box (all 9 Japanese ones are quality 1). Higher-quality voices download
      via System Settings → Accessibility → Spoken Content → System Voice →
      Manage Voices; Kyoko (Enhanced/Premium) is the one worth getting.
      `Speech.bestVoice(for:)` already picks the highest installed quality, so
      the app improves the moment one is added — but it should *tell* the
      learner when only a default-quality voice is present rather than leaving
      them to wonder why it sounds robotic.
- [ ] **Voice picker in Settings.** `Speech.voices(for:)` already returns every
      installed voice sorted best-first; needs a control and a stored
      preference. Kyoko vs Otoya are noticeably different to listen to daily.
- [ ] **Speed slider** instead of two fixed buttons. Measured: the rate scale is
      badly non-linear — 0.375 reads a sentence in 4.6 s against 0.5's 4.2 s,
      which is inaudible; 0.3 takes 5.6 s and is clearly slower. A slider from
      0.25 to 0.55 with the value remembered beats guessing at two presets.
- [ ] **Per-word playback** for listening exercises: tap a word in the
      transcript to hear just that word. The failure mode being practiced is
      parsing はっぴゃく mid-sentence, and a replay of the whole sentence is a
      blunt instrument for that.

### Settings & appearance
- [ ] **Settings page for theme and colours.** Solarized light/dark currently
      follows the system appearance with no override. Wants: explicit
      light/dark/auto, and ideally an alternate palette for anyone who doesn't
      love Solarized.
- [ ] **Font size control.** Sizes are hardcoded per view (22pt prompts, 18pt
      options). Should be one scale factor applied through the environment, not
      a hunt through every view.
### Lessons
- [ ] **Re-check lesson length now that sets exist.** Baselines are 10 / 18 / 30
      *items*; a medium run produced 13. Judge by how long a sitting actually
      takes before raising further.
- [ ] **Generate several lessons at once**, for stocking up before a flight.
      One button, N lessons, one progress indicator.
- [ ] **Retry a single exercise** rather than the whole lesson when one comes
      back malformed.

## Known issues
- [ ] `LessonPlayerView` holds its own `@State` copy of the record and pushes
      updates to `AppModel`. Two copies of one identity — it works because only
      the player writes, but it is exactly the state/identity braiding that
      causes bugs later. Should read through the model.
- [ ] The archive has no filter by state or date, just a text search.
- [ ] No dashboard yet: streak and due count show on the home screen, but there
      is no accuracy trend or mastery view (`/fluent-progress` still does this
      better).

- [ ] A generator sometimes lists a genuinely wrong variant in
      `acceptedAnswers` — one run offered `お` alongside `を`. Accepting a wrong
      particle teaches the wrong thing, but there is no cheap way to validate
      semantics locally. Watch it; if it recurs, have the teacher audit accepted
      answers at grading time.

## Done
- [x] **Study time was wall-clock, not study time.** A lesson opened one night
      and finished the next evening logged **1383 minutes** into Fluent's
      totals. Now accumulates active time between interactions, ignoring gaps
      over 5 minutes; older records fall back to a wall-clock capped at 3× the
      lesson estimate. Corrupted totals repaired (1417 → 49 min). (2026-08-26)
- [x] **A finished lesson reopened at question 1.** Tapping it meant clicking
      through every exercise again to reach Finish. It now opens on the finish
      screen. (2026-08-26)
- [x] **Grading was charged twice on a crash.** Feedback is persisted the moment
      it arrives, in a new `graded` state, so a failure between grading and the
      database write retries only the write. (2026-08-26)
- [x] **A 40-second wait showed only a spinner.** Now streams the model's output
      live with phase, elapsed time, and the answer as it is written. (2026-08-26)
- [x] **Breadth and depth split.** "How much" (how many points) and "Repetition"
      (items per set) are separate controls; nearly every exercise is now a set.
      (2026-08-26)
- [x] **Answers leaked between exercises.** `KanaTextField` kept `@State`
      internally and SwiftUI reused the view across questions, so text typed for
      one exercise reappeared as — and would have been submitted as — the answer
      to the next. Fixed with `.id(exercise.id)` on the input. (2026-08-26)
- [x] **Correct Japanese marked wrong.** Writing the full sentence for a
      fill-in-the-blank was failed on a formatting technicality. Cloze now also
      accepts the blank-filled sentence, and grading gained a third outcome:
      genuinely ambiguous answers go to the teacher instead of being guessed at.
      A reordering never defers — word order is the thing being taught.
      (2026-08-26)
- [x] **Exercise sets.** New `set` kind: one instruction, numbered items with
      hints, graded item by item with partial credit. Lesson size now counts
      items, not exercises. (2026-08-26)
- [x] **Ambiguous prompts.** A gap with no instruction cannot tell the learner
      whether to type the fragment or the whole sentence; generation now rejects
      those. (2026-08-26)
- [x] **Furigana**, **saved lists**, **comprehension passages**, **app icon**.
- [x] **Dropped the hiragana/katakana selector** — the learner's own IME handles
      script switching, and kana passes through the converter untouched.
- [x] **Speech speed had no audible effect.** The two presets were
      `default × 0.75` and `default` — an 8% difference. Slow is now 0.30, a
      measured ~32% longer reading. (2026-08-26)
- [x] **`isSpeaking` never became true.** It was polled immediately after
      `speak()`, but synthesis starts asynchronously, so the poll always saw
      "finished". Now driven by `AVSpeechSynthesizerDelegate`. (2026-08-26)
- [x] **Blank matching row.** A generated lesson padded `pairs` with an empty
      entry, which rendered as an unanswerable row. Schema now sets `minLength`
      on every answer-bearing string and the decoder rejects blank entries, so
      the client retries instead of showing it. (2026-08-26)
- [x] **Reorder answers rendered with spaces** — "京都 までの 切符". Now joined
      without spaces for unspaced scripts, decided from the text rather than a
      configured language. (2026-08-26)
- [x] Kana input with the IME bypassed, so production exercises test recall.
- [x] Japanese TTS, unlocking listening practice.
- [x] Streak bug in `update-db.py` — it keyed off `last_updated`, which setup
      stamps at profile creation, so no learner's first session ever started a
      streak.
