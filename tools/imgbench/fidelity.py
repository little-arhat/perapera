"""Does the model draw the characters we asked for?

Pure: probe definitions, and scoring of a transcription against its target. No
network, no files.

This is the fact the OpenRouter catalog cannot tell us. Price and discount are
published; whether a model can render ぐ rather than り is only knowable by
asking it to, looking at the result, and comparing.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Probe:
    """One thing to draw, and the exact text it must contain."""

    name: str
    prompt: str
    targets: tuple[str, ...]
    why: str


@dataclass(frozen=True)
class ProbeResult:
    """One probe against one model."""

    probe: str
    targets: tuple[str, ...]
    transcribed: tuple[str, ...]
    score: float
    cost: float | None = None
    notes: str = ""


@dataclass(frozen=True)
class ModelResult:
    """Every probe against one model."""

    model: str
    results: list[ProbeResult] = field(default_factory=list)

    @property
    def fidelity(self) -> float | None:
        if not self.results:
            return None
        return sum(r.score for r in self.results) / len(self.results)

    @property
    def cost(self) -> float:
        return sum(r.cost or 0.0 for r in self.results)


# The probe set targets what actually breaks, not what is easy to render.
#
# Every entry here comes from an observed failure or from the confusable pairs a
# learner misreads in the street. A benchmark of common words in a clean gothic
# face would pass every model and tell us nothing.
PROBES: tuple[Probe, ...] = (
    Probe(
        name="dakuten",
        prompt=(
            "A photograph of a Japanese train station exit sign: white enamel "
            "board with black text, mounted on a pole, slight angle, daylight. "
            "It reads exactly, horizontally: みなみぐち\n"
            "Below it, smaller: 南口\n"
            "Realistic photography. Every character correctly and completely formed."
        ),
        targets=("みなみぐち", "南口"),
        why=(
            "Dakuten are the first thing a weak model drops: ぐ becomes く or り. "
            "This exact prompt is what exposed gemini-2.5-flash-image, which drew "
            "みなみりぢち."
        ),
    ),
    Probe(
        name="katakana_confusables",
        prompt=(
            "A photograph of a Japanese shop window poster in bold katakana "
            "display type, angled view with slight glass reflection, daylight. "
            "The poster reads exactly, on two lines:\n"
            "アイスコーヒー\n"
            "レギュラーサイズ\n"
            "Realistic street photography. Every katakana character correctly "
            "and completely formed, including the long-vowel marks."
        ),
        targets=("アイスコーヒー", "レギュラーサイズ"),
        why=(
            "Long-vowel marks get dropped or fused with neighbours, and ギ loses "
            "its dakuten. Also exercises ス/ヌ and シ/ツ shapes at display size."
        ),
    ),
    Probe(
        name="handwritten_small_kana",
        prompt=(
            "A close-up photograph of a handwritten Japanese menu board, black "
            "marker on wood, natural everyday handwriting, warm interior light. "
            "It reads exactly, three lines:\n"
            "やきとり 250円\n"
            "えだまめ 400円\n"
            "おちゃ 150円\n"
            "Realistic photography. Every kana correctly formed, including the "
            "small ゃ and the dakuten on だ."
        ),
        targets=("やきとり", "えだまめ", "おちゃ"),
        why=(
            "Small kana (ゃゅょっ) drawn full size is a silent, plausible-looking "
            "error, and handwriting is where it is most likely."
        ),
    ),
    Probe(
        name="vertical_brush",
        prompt=(
            "A photograph of narrow wooden menu strips hanging on an izakaya "
            "wall, each with a dish written vertically in black brush pen, warm "
            "lantern light. The strips read exactly:\n"
            "とりから\n"
            "ひやしトマト\n"
            "れんこん\n"
            "Realistic photography. Every character correctly and completely formed."
        ),
        targets=("とりから", "ひやしトマト", "れんこん"),
        why=(
            "Vertical brush text is the hardest render and the most valuable "
            "drill. Also exercises れ/ね/わ, which differ by one loop."
        ),
    ),
)


def normalize(text: str) -> str:
    """Fold away what carries no meaning for this comparison.

    Whitespace and full-width/half-width forms differ between a render and a
    transcription without either being wrong. Nothing else is folded: kana
    identity, dakuten and vowel length are the whole point.
    """
    folded = unicodedata.normalize("NFKC", text)
    return "".join(ch for ch in folded if not ch.isspace())


def score_transcription(targets: tuple[str, ...], transcribed: str) -> float:
    """How much of what we asked for actually appeared. 0.0-1.0.

    Per target, all-or-nothing: a target string is either present in the
    transcription or it is not. Partial credit would reward みなみりぢち for
    sharing four characters with みなみぐち, and a nearly-right glyph is exactly
    the failure this benchmark exists to catch.

    The transcription may contain more than the targets — signs carry background
    text, and that is not a fault.
    """
    if not targets:
        return 0.0
    haystack = normalize(transcribed)
    hits = sum(1 for target in targets if normalize(target) in haystack)
    return hits / len(targets)


def missing(targets: tuple[str, ...], transcribed: str) -> list[str]:
    """Which targets did not appear — the useful half of a failure."""
    haystack = normalize(transcribed)
    return [t for t in targets if normalize(t) not in haystack]
