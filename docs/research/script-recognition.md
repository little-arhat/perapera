# Script recognition: reading kana in the wild

Research notes for a proposed exercise type. Every claim below was tested on
this machine; nothing here is from memory.

## The problem

Kana on screen and kana in the street are different perceptual tasks. A learner
who reads すし instantly in Hiragino may stall on the same word brushed on a
noren, hand-marked on a menu board, or set in a 1970s rounded display face. The
app currently only ever shows one typeface family, so it trains the easy half of
the skill and silently omits the hard half.

The specific failures worth targeting are the confusable pairs, which diverge
much further in display and handwritten faces than on screen:

| Pair | Why it breaks |
|---|---|
| シ / ツ | stroke angle only; brush faces exaggerate it, casual handwriting flattens it |
| ソ / ン | same |
| ね / れ / わ | differ in one loop |
| ぬ / め | differ in one loop |
| る / ろ | differ in one loop |
| コ / ユ | orientation |
| ー vs 一 vs ｜ | long-vowel mark vs kanji "one" vs a rule; identical in many faces |

## Three routes, tested

### 1. Generated photographs — works, and better than expected

OpenRouter exposes 11 image-output models. Two were tested with prompts
demanding exact Japanese text.

**`google/gemini-3-pro-image`** — a ramen shop entrance: brush-painted らーめん
on a worn navy noren, plus vertical 定食 on a wooden board. Every character
correctly formed, at an angle, weathered, with a small circular ラーメン logo
also correct.

**`google/gemini-3.1-flash-image`** (cheaper) — a handwritten izakaya menu
board: やきとり 250円 / えだまめ 400円 / おちゃ 150円. All three lines exact,
natural marker handwriting, correct dakuten on だ and correct small ゃ in おちゃ.

This is the real target skill, and the cheap model handled it. CJK text
rendering used to be the blocker for this idea; it is not any more.

**Storage** is not a problem: 2.1 MB PNG → 194 KB JPEG at 1024 px, and 832 KB →
136 KB, both still fully legible. A lesson with five images costs well under a
megabyte.

### 2. Verification — the part that makes it trustworthy

A malformed stroke in a recognition drill teaches a wrong letterform. That is
worse than not practising at all, so generated text must be verified, never
trusted. Two tiers were tested:

**macOS Vision (`VNRecognizeTextRequest`, `ja-JP`)** — free, offline,
deterministic, already on the machine. On the handwritten menu it read back all
three lines exactly. On the noren it read らーめん but missed the vertical 定食.

So local OCR is a **one-way filter**: a match confirms the render, a miss proves
nothing (vertical and heavily stylised text defeat it).

**Vision-model read-back (`google/gemini-2.5-flash`)** — read everything on both
images, including the vertical 定食 and the small circular logo.

That gives a cheap ladder: generate → local OCR → if it confirms, ship free; if
not, ask the vision model; if that still disagrees with the intended text,
regenerate. Only ambiguous cases cost anything.

### 3. Font rendering — free, exact, complementary

57 font families installed on this machine cover both kana and kanji. They span
the relevant styles:

| Style | Families |
|---|---|
| Brush / calligraphic | Kaiti, Xingkai, Weibei, Hannotate, Libian |
| Display mincho (signage) | Toppan Bunkyu Midashi Mincho, YuMincho, Hiragino Mincho |
| Rounded (shop signs) | Hiragino Maru Gothic, Tsukushi A/B Round Gothic, Yuppy |
| Textbook | YuKyokasho, Klee |
| Universal-design / transit | BIZ UDGothic, BIZ UDMincho |
| Plain screen (the baseline) | Hiragino Sans, YuGothic, Osaka |

[Google Fonts](https://fonts.google.com) adds OFL-licensed faces that fill the
remaining gaps — [Yomogi](https://fonts.google.com/specimen/Yomogi) (thin
handwriting), [Hachi Maru
Pop](https://fonts.google.com/specimen/Hachi+Maru+Pop) (1980s rounded
handwritten, 6,000+ kanji), Dela Gothic One (poster/packaging), DotGothic16
(dot-matrix, i.e. train displays).

Font rendering has one decisive advantage over generation: **the text is exact
by construction**, so it needs no verification at all. It is free, offline,
instant, and reproducible. What it cannot supply is real-world context — angle,
lighting, wear, the curve of fabric.

### 4. Corpora — the weakest option

- **Kuzushiji / KMNIST** ([CODH](https://codh.rois.ac.jp/kmnist/index.html.en),
  CC BY-SA 4.0, 270k images) is well-licensed and large, but it is 18th-century
  cursive literature script. Wrong target: it teaches reading historical
  manuscripts, not shop signs.
- Modern Japanese scene-text sets (JaWildText, SVTD/VTD142, NDLOCR) exist but
  are aimed at *training OCR models*, are frequently research-only, and often
  need registration. They also come without the pedagogy — no readings, no
  glosses, no difficulty grading.

Not worth pursuing for a first version. Revisit only if generated images prove
unrealistic in a way that matters.

## Recommendation: two tracks, one exercise kind

**Track A — rendered (the drill).** Free, offline, exact. Show a known word in
an unfamiliar face; the learner types the reading. Cheap enough to appear in
every session, and the natural home for confusable-pair work: render シ and ツ
in six faces and make the learner discriminate.

**Track B — photographic (the transfer test).** Generated and verified. Fewer
per lesson, higher value: a menu board, a station sign, a noren. This is where
the skill actually transfers, and it doubles as reading-comprehension and
price-parsing practice.

Both produce the same new exercise kind, differing only in how the stimulus is
produced. Grading reuses the existing text grader unchanged — the learner types
a reading, which is already a solved problem.

## What this needs that the app does not yet have

1. **Lesson assets.** Lessons are currently a single JSON file. Images need to
   live beside them (`lessons/<id>/` with the JSON plus JPEGs), and
   `LessonStore` needs to manage the directory rather than one file.
2. **An image-generation path.** Today the app shells `claude -p`. Image
   generation needs OpenRouter directly, with `OPENROUTER_KB` from the
   environment — a second, differently-shaped external dependency, and the first
   time the app would talk to a non-Anthropic service.
3. **A verifier.** `VNRecognizeTextRequest` wrapper plus the read-back fallback.
4. **A font renderer.** Core Text into a bitmap; pure, testable, no network.
5. **Generation-time rejection.** A recognition exercise whose stimulus fails
   verification must never reach the learner.

## Open questions for the next session

- Per-image cost is not yet measured (OpenRouter's `image` price field is
  unpopulated for the flash models). Worth one metered run before committing.
- Should Track A ship first on its own? It is free, needs no network, no new
  service, and no verification — perhaps two days of work against a week for
  Track B.
- How should the confusable-pair drill be scheduled? These are perceptual
  discriminations, not vocabulary; SM-2 may not be the right model for them.
