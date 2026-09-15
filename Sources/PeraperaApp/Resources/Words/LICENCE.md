# kana-words.json, lookup.json

Derived from **JMdict**, the Japanese-Multilingual Dictionary, © the
[Electronic Dictionary Research and Development Group](https://www.edrdg.org/),
used under a **Creative Commons Attribution-ShareAlike 4.0** licence.

<https://www.edrdg.org/edrdg/licence.html>

## What was taken

`lookup.json` is a dictionary index: every form (written and read) of every
entry the corpus marks common, mapped to its reading and first two glosses.
67,874 forms. It exists so clicking a word answers instantly and offline instead
of waiting on a model call.

`kana-words.json` is the word list behind the reading drill and the pictures
made from the dictionary.

Entries with a frequency marker whose reading is written entirely in one kana
script and is two to six characters long, excluding those marked archaic,
obsolete, rare, vulgar, slang, derogatory or colloquial. One record per distinct
reading, carrying the reading, the first English gloss, the script, and a tier
derived from JMdict's own priority markers: 1 for `ichi1`/`news1`/`spec1`/`gai1`,
2 for the `2` variants, 3 otherwise; and JMdict's `nfXX` newspaper-frequency
bucket where the entry has one, which is 500 words wide — `nf01` is the five
hundred most frequent, and 0 means unranked. Where the entry has an ordinary
kanji spelling of that reading (not one JMdict marks irregular, outdated, rare or
search-only, and not a reading it marks as belonging to no kanji), the record
carries it as `k`: it is what a sign would actually say.

Both files are produced by `tools/words/build.py`, which states the rules above
in code. JMdict changes daily, so a rebuild differs from the shipped files by a
handful of entries.

## What this means for you

The dictionary data in this file stays under CC BY-SA 4.0 and carries the
attribution above. The rest of this repository is MIT; the two do not mix, and
this file is the boundary. A derivative of this data must keep the same licence.
