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

**`google/gemini-3.1-flash-image`** — a handwritten izakaya menu board:
やきとり 250円 / えだまめ 400円 / おちゃ 150円. All three lines exact, natural
marker handwriting, correct dakuten on だ and correct small ゃ in おちゃ. Also
produced correct vertical tanzaku strips, a shop-window poster
(アイスコーヒー / レギュラーサイズ), a shrine board (お参りのしかた /
二礼二拍手一礼), a station sign (みなみぐち / 南口), and a weathered enamel
plate (でぐち).

**`google/gemini-2.5-flash-image` is cheaper and unusable.** At $0.0387 against
$0.0677 it looks attractive, but asked for みなみぐち it rendered
**みなみりぢち** — wrong kana, confidently drawn. Text accuracy is the entire
product here, so the cheaper model is not a saving; it is a defect generator.

CJK text rendering used to be the blocker for this idea. It is not any more —
but only above a certain model tier.

**Storage** is not a problem: 2.1 MB PNG → 194 KB JPEG at 1024 px, and 832 KB →
136 KB, both still fully legible. A lesson with five images costs well under a
megabyte.

### 2. Verification — must be the paid one

A malformed stroke in a recognition drill teaches a wrong letterform. That is
worse than not practising at all, so generated text must be verified, never
trusted.

**macOS Vision (`VNRecognizeTextRequest`, `ja-JP`) is not adequate.** An early
test on a flat, horizontal, printed menu was encouraging, and I wrongly
generalised from it. On the realistic cases it fails badly:

| Image | Intended | Local OCR read |
|---|---|---|
| Shop window poster | アイスコーヒー | アスコービー (dropped イ) |
| same | レギュラーサイズ | レキュラーサイズ (dropped the dakuten) |
| Vertical izakaya strips | とりから / ひやしトマト / れんこん | `っう` `い` `それかいん）` |
| Vertical shrine board | お参りのしかた … | `おがりを` `ありさで` `さむrす。` |

Those are **false negatives** — the images were correct. A pipeline gated on
local OCR would reject good images and regenerate them at full price, and would
be worst exactly where the exercise is most valuable. Vertical, angled and
weathered text is the point of the drill and the thing Vision cannot read.

**Vision-model read-back (`google/gemini-2.5-flash`) handles all of it.** On the
same four images it transcribed every line exactly, including vertical brush
calligraphy and the dakuten Vision dropped. Measured cost: **$0.00059 per image**
against a 1024 px JPEG — 0.9% of what the image itself costs.

So verification is a paid step, but a rounding error. Local OCR is worth keeping
only as a free fast path for flat horizontal text; it must never be the
gatekeeper.

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

## What it costs

Measured on this machine, not estimated:

| Item | Cost | Notes |
|---|---|---|
| Image (`gemini-3.1-flash-image`) | **$0.0677** | n=5, range $0.0672–0.0685 |
| Image (`gemini-2.5-flash-image`) | $0.0387 | **unusable** — renders wrong kana |
| Verification read-back | **$0.00059** | n=3, on a 1024 px JPEG |
| Lesson JSON (opus) | **$0.58** | n=3: $0.530 / $0.645 / $0.570 |
| Grading | not measured | assumed $0.40 below |

**Image cost is flat.** $0.067 whether the prompt is 54 tokens or 73, whether
the output is 1024×1024 or 1408×768, whether the scene is a bare enamel plate or
a crowded izakaya. Prompt tokens are noise. So *making the picture simpler or
smaller does not make it cheaper* — there is no saving on that axis.

Per lesson, assuming a 15% verification-reject rate (guessed, not measured):

| Shape | Recognition items | Total | Per item |
|---|---|---|---|
| 5 images, 1 item each | 5 | $1.37 | $0.274 |
| 8 images, 1 item each | 8 | $1.61 | $0.201 |
| 2 images, 4 items each | 8 | $1.14 | $0.142 |
| 3 images, 3 items each | 9 | $1.22 | $0.135 |
| 3 images, 3 items, **Sonnet** for the lesson text | 9 | **$0.70** | $0.077 |

At one lesson a day, the naive shape is roughly $41–48/month; the last row is
about $21.

### Where the savings actually are

1. **Several items per image.** A menu board carries three to six readable
   items; the izakaya photo already carries three. Eight recognition items from
   two images costs $0.16 in image generation instead of $0.62. This is also
   more realistic — you read a whole menu, not one word in isolation. It is the
   inverse of cropping tighter, and it is the reason cropping tighter is the
   wrong instinct for cost.
2. **Reuse.** An image is a durable asset, not lesson-scoped ephemera. Three
   images carrying nine items, each reviewed eight times over the following
   months, costs **$0.003 per exposure**. Recognition items are exactly the kind
   of thing spaced repetition should own; generating fresh images per session
   would be paying repeatedly for something that does not wear out.
3. **The text model, not the images.** At five images the lesson JSON ($0.58)
   costs *more than the pictures* ($0.39). Moving generation to Sonnet is worth
   more than any image-side optimisation.
4. **Font rendering for the letterform drill**, which is free — reserve
   photographs for the transfer test.

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
