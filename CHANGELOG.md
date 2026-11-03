# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-11-03

### Changed
- No more repeated hives: the game remembers the letter sets already played
  and draws a new one each time. The same seven letters no longer come back
  with another centre letter until every set has been played (1,316 in
  English, 719 in French). Solo games and multiplayer matches share this
  memory, and a match never plays the same letters twice. The Daily
  Challenge is unchanged (the same letters for everyone) and counts as
  played.

## [1.1.0] - 2026-11-02

### Added
- A multiplayer mode, "Spelling Bee · multiplayer" under Tools → Games →
  Party & quiz (or "Mode: Multiplayer" in the game's menu). The reader lies
  on the table and shows the hive big with a countdown; everyone writes words
  on paper. When time is up the full answer list comes up, grouped by length
  with the points of each length, pangrams marked +7.
- Scoring as in Boggle Party, worked out by the reader: each player in turn
  taps the words they wrote (already claimed words show grey), then a word
  written by one player only scores for them with the solo game's points,
  and a word written by several players is cancelled. The results show the
  scored words in bold and the cancelled ones struck through; tap a word to
  see who wrote it, "Details" lists each player's words.
- Settings: players and their names (remembered), rounds per match (1 to 5),
  timer (off, 3 to 10 min) with Pause, End round. The match ends with the
  final scoreboard and "New game"; a match in progress is saved apart from
  the solo game and restored (a round in play comes back paused).
- Rules has two complete texts, solo and multiplayer: it opens the one of the
  mode being played, with a button to read the other.

### Changed
- Family-friendly words: `tools/blocklist_<lang>.txt` now covers vulgar,
  sexual, scatological, slur and drug-related words and their inflections --
  25 English and 35 French answers are no longer revealed or hinted (plus 18
  / 38 rare bonus words). 38 English and 29 French letter sets that lost
  their pangram or fell under 20 answers were dropped (5636 / 2217 left).

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- Spelling Bee: seven letters in a honeycomb, words of 4+ letters that must
  contain the centre letter, at least one pangram per puzzle.
- NYT scoring (1 point for 4 letters, length above, +7 for a pangram) and its
  rank ladder, Beginner to Genius, then Queen Bee.
- English and French puzzles (5,674 and 2,246), language following KOReader's.
  Answers are common words; rarer valid words count as bonus words.
- Daily Challenge, Hint (word start and length, then the word), Reveal
  answers, word list, auto-save.
