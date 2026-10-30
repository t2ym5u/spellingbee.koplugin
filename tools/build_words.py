#!/usr/bin/env python3
# Rebuilds Spelling Bee's word and puzzle data from boggle.koplugin's
# dictionaries. Run from the monorepo root:
#
#   python3 spellingbee.koplugin/tools/build_words.py EN_FREQ FR_FREQ
#
# where EN_FREQ / FR_FREQ are the OpenSubtitles frequency lists en_50k.txt and
# fr_50k.txt from https://github.com/hermitdave/FrequencyWords (content/2018,
# CC-BY-SA 4.0) -- not vendored, they only decide which words are common.
#
# words_<lang>.lua   -- every dictionary word some puzzle accepts, split in
#                       two blocks: "core" (common: in the frequency list's top
#                       FREQ_TOP) and "extra" (rare but valid). Only words of 4+
#                       letters, at most 7 distinct letters, no S (no puzzle
#                       uses S -- see below), and not in tools/blocklist_<lang>.
# puzzles_<lang>.lua -- the letter sets the game draws from, centre letter
#                       first, e.g. "NGIMOTU". A set qualifies when, for that
#                       centre, its core answers number CORE_MIN..CORE_MAX, at
#                       least one core word uses all 7 letters (the pangram),
#                       the core score is at most SCORE_MAX and the rare extras
#                       number at most EXTRA_MAX.
#
# No set contains S, as in the NYT game: S turns every word into two (plurals,
# and in French most verb forms) and makes the list a chore.
import collections, itertools, os, re, sys, unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOGGLE = os.path.join(os.path.dirname(ROOT), "boggle.koplugin")
NAMES = {"en": "English", "fr": "French"}

FREQ_TOP = 30000
CORE_MIN, CORE_MAX = 20, 55
SCORE_MAX = 240
EXTRA_MAX = 120


def words_of(path):
    text = open(path, encoding="utf-8").read()
    m = re.search(r"\[\[(.*?)\]\]", text, re.S)
    return [w.upper() for w in re.findall(r"[A-Za-z]+", m.group(1))]


def normalize(word):
    # Same normalization as the dictionaries: accents stripped, ligatures
    # spelt out, anything left that is not a-z (apostrophes, hyphens) dropped.
    w = word.lower().replace("œ", "oe").replace("æ", "ae")
    w = "".join(c for c in unicodedata.normalize("NFD", w) if unicodedata.category(c) != "Mn")
    return w.upper() if re.fullmatch(r"[a-z]+", w) else None


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


def build(lang, freq_path):
    blocked = {
        l.strip() for l in open(os.path.join(ROOT, "tools", f"blocklist_{lang}.txt"), encoding="utf-8")
        if l.strip() and not l.startswith("#")
    }
    words = {
        w for w in words_of(os.path.join(BOGGLE, f"words_{lang}.lua"))
        if len(w) >= 4 and "S" not in w and len(set(w)) <= 7
    } - blocked

    freq = []
    for line in open(freq_path, encoding="utf-8"):
        parts = line.split()
        if parts:
            freq.append(normalize(parts[0]))
    core = {w for w in freq[:FREQ_TOP] if w} & words
    extra = words - core

    by_letters = collections.defaultdict(list)
    for w in words:
        by_letters[frozenset(w)].append(w)

    puzzles, used = [], set()
    for letters in sorted(by_letters, key=lambda s: "".join(sorted(s))):
        if len(letters) != 7 or not any(w in core for w in by_letters[letters]):
            continue
        ordered = sorted(letters)
        pool = []
        for k in range(1, 8):
            for sub in itertools.combinations(ordered, k):
                pool += by_letters.get(frozenset(sub), [])
        for centre in ordered:
            answers = [w for w in pool if centre in w]
            core_answers = [w for w in answers if w in core]
            n_extra = len(answers) - len(core_answers)
            if (CORE_MIN <= len(core_answers) <= CORE_MAX
                    and sum(score(w) for w in core_answers) <= SCORE_MAX
                    and n_extra <= EXTRA_MAX):
                puzzles.append(centre + "".join(c for c in ordered if c != centre))
                used.update(answers)

    # Words no puzzle can ever ask for are dead weight on the device.
    core, extra = core & used, extra & used

    name = NAMES[lang]
    source = {
        "en": "ENABLE (Public Domain)",
        "fr": "the CC0 Scrabble-valid list + an-array-of-french-words (MIT)",
    }[lang]
    with open(os.path.join(ROOT, f"words_{lang}.lua"), "w", encoding="utf-8") as f:
        f.write(f"""-- {name} word list for Spelling Bee (generated, do not edit).
-- Filtered from boggle.koplugin/words_{lang}.lua, i.e. {source}; see
-- that file for the full credits. Kept: words of 4+ letters, at most 7
-- distinct letters, no S (no puzzle uses S), minus tools/blocklist_{lang}.txt.
-- {len(core)} core + {len(extra)} extra words.
--
-- core:  common words -- in the top {FREQ_TOP} of the OpenSubtitles frequency list
--        (hermitdave/FrequencyWords, CC-BY-SA 4.0). They make up a puzzle's
--        answers: its score, its ranks, Queen Bee.
-- extra: every other valid word. Accepted as bonus words, worth no points.
-- Regenerate with tools/build_words.py (run from the monorepo root).
local core = [[
{wrap(sorted(core))}
]]
local extra = [[
{wrap(sorted(extra))}
]]
return {{ core = core, extra = extra }}
""")
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
    print(lang, "core:", len(core), "extra:", len(extra), "puzzles:", len(puzzles))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__ or "usage: build_words.py EN_FREQ FR_FREQ")
    build("en", sys.argv[1])
    build("fr", sys.argv[2])
