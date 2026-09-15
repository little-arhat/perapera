"""Derives the bundled word data from JMdict.

    python3 tools/words/build.py JMdict_e.gz Sources/PeraperaApp/Resources/Words

JMdict comes from http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz and changes
daily, so a rebuild is not byte-identical to the last one; the counts it prints
should move by a handful of entries, not thousands. What each file holds, and
the licence it carries, is described in LICENCE.md beside the output.

Standard library only, like everything else the app ships.
"""

import collections
import gzip
import json
import os
import sys
import xml.etree.ElementTree as ET

# JMdict's misc markers for words a learner should not be drilled on.
UNDRILLABLE = {"archaism", "obsolete term", "rare term", "obscure term",
               "vulgar expression", "slang", "derogatory", "colloquialism"}
# The subset that also keeps a form out of the lookup index: a learner who
# clicks a slang word still deserves its meaning.
UNINDEXABLE = {"archaism", "obsolete term", "rare term", "obscure term"}
# Kanji forms JMdict marks as not the ordinary way to write the word.
IRREGULAR_KANJI = {"word containing irregular kanji usage",
                   "word containing out-dated kanji or kanji usage",
                   "rarely used kanji form", "search-only kanji form"}
TIER_1 = {"ichi1", "news1", "spec1", "gai1"}
TIER_2 = {"ichi2", "news2", "spec2", "gai2"}


def script_of(text):
    if all(0x3041 <= ord(c) <= 0x3096 or c == "ー" for c in text):
        return "h"
    if all(0x30A1 <= ord(c) <= 0x30FA or c == "ー" for c in text):
        return "k"
    return None


def tier(priorities):
    if TIER_1 & priorities:
        return 1
    if TIER_2 & priorities:
        return 2
    return 3


def priorities(element):
    return [p.text for p in element.findall("ke_pri") + element.findall("re_pri") if p.text]


def newspaper_rank(entry):
    """The best nf bucket any form carries; 0 when none does.

    The bucket usually sits on the kanji form, so a reading-only look would
    leave most words unranked.
    """
    ranks = [int(p[2:]) for element in entry.findall("k_ele") + entry.findall("r_ele")
             for p in priorities(element) if p.startswith("nf")]
    return min(ranks) if ranks else 0


def has_kanji(text):
    return any(0x4E00 <= ord(c) <= 0x9FFF or 0x3400 <= ord(c) <= 0x4DBF or c == "々"
               for c in text)


def kanji_form(entry, reading):
    """The ordinary written form of this reading, or None.

    A reading marked `re_nokanji` is not a reading of the kanji at all (a
    loanword listed beside a kanji spelling), and one with `re_restr` belongs
    only to the forms it names. Irregular and search-only kanji forms are what
    JMdict says nobody would write. A headword without a kanji in it (４０ for
    よんじゅう, Ｔシャツ) is a spelling, not a kanji form.
    """
    if reading.find("re_nokanji") is not None:
        return None
    allowed = {r.text for r in reading.findall("re_restr") if r.text}
    for k in entry.findall("k_ele"):
        keb = k.findtext("keb")
        if not keb or (allowed and keb not in allowed) or not has_kanji(keb):
            continue
        if {i.text for i in k.findall("ke_inf")} & IRREGULAR_KANJI:
            continue
        return keb
    return None


def drill_word(entry, seen):
    sense = entry.find("sense")
    if sense is None or ({m.text for m in sense.findall("misc")} & UNDRILLABLE):
        return None
    gloss = sense.findtext("gloss")
    if not gloss or len(gloss) > 40:
        return None
    rank = newspaper_rank(entry)
    for reading in entry.findall("r_ele"):
        reb = reading.findtext("reb") or ""
        pris = set(priorities(reading))
        script = script_of(reb)
        if not pris or reb in seen or not script or not (2 <= len(reb) <= 6):
            continue
        seen.add(reb)
        word = {"w": reb, "g": gloss, "s": script, "t": tier(pris), "f": rank}
        kanji = kanji_form(entry, reading)
        if kanji:
            word["k"] = kanji
        return word
    return None


def index_forms(entry, index):
    sense = entry.find("sense")
    if sense is None or ({m.text for m in sense.findall("misc")} & UNINDEXABLE):
        return
    glosses = [g.text for g in sense.findall("gloss") if g.text][:2]
    readings = [r.findtext("reb") for r in entry.findall("r_ele") if r.findtext("reb")]
    if not glosses or not readings:
        return
    # Only entries the corpus considers common, or the index is 200k rows of
    # words nobody clicks.
    if not any(priorities(e) for e in entry.findall("k_ele") + entry.findall("r_ele")):
        return
    gloss = "; ".join(glosses)[:48]
    reading = readings[0]
    forms = [k.findtext("keb") for k in entry.findall("k_ele") if k.findtext("keb")] + readings
    for form in forms:
        if form and form not in index:
            # A kana form is its own reading; storing it twice is 40% of the file.
            index[form] = {"g": gloss} if form == reading else {"r": reading, "g": gloss}


def build(source):
    words, seen, index = [], set(), {}
    for _, element in ET.iterparse(gzip.open(source, "rb"), events=("end",)):
        if element.tag != "entry":
            continue
        word = drill_word(element, seen)
        if word:
            words.append(word)
        index_forms(element, index)
        element.clear()
    words.sort(key=lambda w: (w["f"] or 999, w["t"]))
    return words, index


def main(source, out_dir):
    words, index = build(source)
    with open(os.path.join(out_dir, "kana-words.json"), "w") as f:
        json.dump(words, f, ensure_ascii=False)
    with open(os.path.join(out_dir, "lookup.json"), "w") as f:
        json.dump(index, f, ensure_ascii=False, separators=(",", ":"))
    by_script = collections.Counter(w["s"] for w in words)
    print(f"kana-words.json: {len(words)} words "
          f"({by_script['h']} hiragana, {by_script['k']} katakana, "
          f"{sum(1 for w in words if 'k' in w)} with a kanji form, "
          f"{sum(1 for w in words if w['f'])} ranked)")
    print(f"lookup.json: {len(index)} forms")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
