#!/usr/bin/env python3
# Rebuilds Spelling Bee's word lists (and, on request, its puzzle banks) from
# boggle.koplugin's dictionaries. Run from the monorepo root:
#
#   python3 spellingbee.koplugin/tools/build_words.py EN_FREQ FR_FREQ FR_LEXICON [--new-puzzles]
#
# EN_FREQ / FR_FREQ are the OpenSubtitles frequency lists en_50k.txt and
# fr_50k.txt from https://github.com/hermitdave/FrequencyWords (content/2018,
# CC-BY-SA 4.0) -- not vendored, they only decide which words are common.
# FR_LEXICON is lexique-grammalecte-fr-v7.7.txt, the Grammalecte / Dicollecte
# list of French inflected forms (MPL 2.0), from
# https://www.grammalecte.net/dic/lexique-grammalecte-fr-v7.7.zip -- not
# vendored either (55 MB); it only widens the French bonus words.
#
# words_<lang>.lua   -- every word some puzzle accepts, split in two blocks:
#                       "core" (common: a boggle.koplugin word in the frequency
#                       list's top FREQ_TOP) and "extra" (rare but valid: the
#                       other boggle.koplugin words, plus in French the
#                       lexicon's -- see lexicon_words). Only words of 4+
#                       letters, at most 7 distinct letters, no S (no puzzle
#                       uses S -- see below), and not in tools/blocklist_<lang>.
# puzzles_<lang>.lua -- the letter sets the game draws from, centre letter
#                       first, e.g. "NGIMOTU". Kept as they are unless
#                       --new-puzzles is given: the published banks were
#                       pruned by hand after generation (family blocklist,
#                       CHANGELOG 1.1.0 and 1.2.3), so regenerating them adds
#                       sets back and changes the Daily Challenge.
#                       With --new-puzzles, a set qualifies when, for that
#                       centre, its core answers number CORE_MIN..CORE_MAX, at
#                       least one core word uses all 7 letters (the pangram),
#                       the core score is at most SCORE_MAX and the rare
#                       boggle.koplugin extras number at most EXTRA_MAX (the
#                       lexicon's words are left out of that count).
#
# No set contains S, as in the NYT game: S turns every word into two (plurals,
# and in French most verb forms) and makes the list a chore.
import collections, itertools, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOGGLE = os.path.join(os.path.dirname(ROOT), "boggle.koplugin")
NAMES = {"en": "English", "fr": "French"}

FREQ_TOP = 30000
CORE_MIN, CORE_MAX = 20, 55
SCORE_MAX = 240
EXTRA_MAX = 120

# The lexicon filter is boggle.koplugin's, shared by every word game: tags,
# lemmas, and the family blocklists of all of them (tools/lexicon_fr.py).
sys.path.insert(0, os.path.join(BOGGLE, "tools"))
import lexicon_fr  # noqa: E402


def words_of(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"\[\[(.*?)\]\]", text, re.S)
    return [w.upper() for w in re.findall(r"[A-Za-z]+", m.group(1))]


normalize = lexicon_fr.normalize


def score(word):
    s = 1 if len(word) == 4 else len(word)
    return s + 7 if len(set(word)) == 7 else s


def wrap(words):
    lines, line = [], ""
    for w in words:
        if len(line) + len(w) + 1 > 96:
            lines.append(line)
            line = ""
        line += ("," if line else "") + w
    lines.append(line)
    return "\n".join(lines)


def playable(words):
    return {w for w in words if len(w) >= 4 and "S" not in w and len(set(w)) <= 7}


def by_letter_set(words):
    out = collections.defaultdict(list)
    for w in words:
        out[frozenset(w)].append(w)
    return out


def pool_of(by_letters, letters):
    pool = []
    ordered = sorted(letters)
    for k in range(1, 8):
        for sub in itertools.combinations(ordered, k):
            pool += by_letters.get(frozenset(sub), [])
    return pool


def new_puzzles(words, core):
    by_letters = by_letter_set(words)
    puzzles = []
    for letters in sorted(by_letters, key=lambda s: "".join(sorted(s))):
        if len(letters) != 7 or not any(w in core for w in by_letters[letters]):
            continue
        ordered = sorted(letters)
        pool = pool_of(by_letters, letters)
        for centre in ordered:
            answers = [w for w in pool if centre in w]
            core_answers = [w for w in answers if w in core]
            n_extra = len(answers) - len(core_answers)
            if (CORE_MIN <= len(core_answers) <= CORE_MAX
                    and sum(score(w) for w in core_answers) <= SCORE_MAX
                    and n_extra <= EXTRA_MAX):
                puzzles.append(centre + "".join(c for c in ordered if c != centre))
    return puzzles


def published_puzzles(lang):
    text = open(os.path.join(ROOT, f"puzzles_{lang}.lua"), encoding="utf-8").read()
    m = re.search(r"\[\[(.*?)\]\]", text, re.S)
    return re.findall(r"[A-Z]+", m.group(1))


def build(lang, freq_path, lexicon_path=None, regenerate=False):
    blocked = {
        l.strip() for l in open(os.path.join(ROOT, "tools", f"blocklist_{lang}.txt"), encoding="utf-8")
        if l.strip() and not l.startswith("#")
    }
    base = playable(words_of(os.path.join(BOGGLE, f"words_{lang}.lua"))) - blocked
    lexicon = (playable(lexicon_fr.lexicon_words(lexicon_path, lexicon_fr.family_blocklist())) - blocked
               if lexicon_path else set())

    freq = []
    for line in open(freq_path, encoding="utf-8"):
        parts = line.split()
        if parts:
            freq.append(normalize(parts[0]))
    core = {w for w in freq[:FREQ_TOP] if w} & base

    puzzles = new_puzzles(base, core) if regenerate else published_puzzles(lang)

    # Words no puzzle can ever ask for are dead weight on the device.
    words = base | lexicon
    by_letters = by_letter_set(words)
    used = set()
    for p in puzzles:
        used.update(w for w in pool_of(by_letters, p) if p[0] in w)
    core = core & used
    extra = (words - core) & used
    n_lexicon = len(extra - base)

    name = NAMES[lang]
    source = {
        "en": "boggle.koplugin/words_en.lua, i.e. ENABLE (Public Domain)",
        "fr": "boggle.koplugin/words_fr.lua, i.e. the CC0 Scrabble-valid list +\n"
              "-- an-array-of-french-words (MIT)",
    }[lang]
    lexicon_note = "" if not lexicon_path else f"""
--        {n_lexicon} of them come only from the Grammalecte lexicon of French
--        inflected forms v7.7 (Olivier R., Dicollecte, https://grammalecte.net,
--        Mozilla Public License 2.0), filtered by boggle.koplugin/tools/lexicon_fr.py:
--        no familiar, pejorative, slang or sexual word, symbol or acronym,
--        nor any form of a word the family blocklists carry."""
    with open(os.path.join(ROOT, f"words_{lang}.lua"), "w", encoding="utf-8") as f:
        f.write(f"""-- {name} word list for Spelling Bee (generated, do not edit).
-- Filtered from {source}; see
-- that file for the full credits. Kept: words of 4+ letters, at most 7
-- distinct letters, no S (no puzzle uses S), minus tools/blocklist_{lang}.txt,
-- and only words some puzzle accepts.
-- {len(core)} core + {len(extra)} extra words.
--
-- core:  common words -- in the top {FREQ_TOP} of the OpenSubtitles frequency list
--        (hermitdave/FrequencyWords, CC-BY-SA 4.0). They make up a puzzle's
--        answers: its score, its ranks, Queen Bee.
-- extra: every other valid word. Accepted as bonus words, worth no points.{lexicon_note}
-- Regenerate with tools/build_words.py (run from the monorepo root).
local core = [[
{wrap(sorted(core))}
]]
local extra = [[
{wrap(sorted(extra))}
]]
return {{ core = core, extra = extra }}
""")
    if regenerate:
        with open(os.path.join(ROOT, f"puzzles_{lang}.lua"), "w", encoding="utf-8") as f:
            f.write(f"""-- {name} puzzles for Spelling Bee (generated, do not edit).
-- One letter set per entry, centre letter first. Every set has {CORE_MIN}-{CORE_MAX} core
-- answers containing the centre letter, a core score of at most {SCORE_MAX}, at least
-- one core pangram and at most {EXTRA_MAX} rare bonus words. {len(puzzles)} puzzles.
-- Regenerate with tools/build_words.py (run from the monorepo root).
local raw = [[
{wrap(puzzles)}
]]
local puzzles = {{}}
for p in raw:gmatch("%u+") do puzzles[#puzzles + 1] = p end
return puzzles
""")
    print(lang, "core:", len(core), "extra:", len(extra), f"(lexicon only: {n_lexicon})",
          "puzzles:", len(puzzles), "(regenerated)" if regenerate else "(kept)")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--new-puzzles"]
    if len(args) != 3:
        sys.exit("usage: build_words.py EN_FREQ FR_FREQ FR_LEXICON [--new-puzzles]")
    regenerate = "--new-puzzles" in sys.argv[1:]
    build("en", args[0], regenerate=regenerate)
    build("fr", args[1], args[2], regenerate=regenerate)
