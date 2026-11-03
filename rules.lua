-- rules.lua — the two rules texts, shown by ScreenBase:makeModeRulesButtonConfig
-- (the mode being played first, a button for the other one).

local _ = require("i18n")

local SOLO_EN = _([[
Spelling Bee — Rules

Make words from the seven letters of the hive.

• Words have at least 4 letters.
• Every word must contain the centre letter (the black one).
• Letters can be used more than once.
• Every puzzle has at least one pangram: a word using all seven letters.

Tap the letters to type, then Enter. Shuffle mixes the outer letters to help you see new words.

Scoring: a 4-letter word is worth 1 point, a longer word one point per letter, and a pangram 7 points more. Your rank climbs from Beginner to Genius as your score grows; Queen Bee means every word found.

The answers are common words. Rarer words the dictionary knows are accepted as bonus words: they appear in grey, lowercase, and score nothing. Hint first gives the start and length of a missing word, then reveals it (worth no points). Reveal answers ends the puzzle and shows the words you missed.

Daily Challenge gives everyone the same letters for the day.
]])

local SOLO_FR = [[
Spelling Bee — Règles

Formez des mots avec les sept lettres de la ruche.

• Les mots ont au moins 4 lettres.
• Chaque mot doit contenir la lettre centrale (la noire).
• Une lettre peut servir plusieurs fois.
• Chaque grille a au moins un pangramme : un mot qui utilise les sept lettres.

Touchez les lettres pour écrire, puis Entrée. Mélanger change la place des lettres extérieures pour aider à voir de nouveaux mots. Les accents sont ignorés : É s'écrit E.

Points : un mot de 4 lettres vaut 1 point, un mot plus long un point par lettre, et un pangramme 7 points de plus. Votre rang monte de Débutant à Génie avec le score ; Reine des abeilles veut dire tous les mots trouvés.

Les réponses sont des mots courants. Les mots plus rares du dictionnaire sont acceptés comme mots bonus : ils s'affichent en gris, en minuscules, et ne rapportent rien. Astuce donne d'abord le début et la longueur d'un mot manquant, puis le révèle (sans points). Voir les réponses termine la grille et montre les mots manqués.

Le Défi du jour donne les mêmes lettres à tout le monde pour la journée.
]]

local PARTY_EN = _([[
Spelling Bee · multiplayer — Rules

A pen-and-paper word hunt for 2 to 8 players around one reader laid in the middle of the table.

Setup
In the menu, choose Players (2–8) and type their Player names (remembered for next time), the number of Rounds (1–5), the Timer (off, or 3 to 10 min) and the Language. Everyone needs a sheet of paper and a pen.

A round
The reader shows the hive and the countdown. Until time is up, every player secretly writes words made from the seven letters:
• at least 4 letters,
• every word contains the centre letter (the black one),
• letters can be used more than once.
Shuffle moves the outer letters, Pause stops the clock, End round stops the round early (or ends it when there is no timer).
Pens down: the list of answers comes up, grouped by length, with the points of each length. Then the reader goes round the table: each player in turn taps the words of the list they wrote, then Next player; the last one taps Done. Words claimed by an earlier player show grey. Previous player goes back to fix a mistake.

Scoring
A word written by one player only scores for them: 1 point for 4 letters, otherwise one point per letter (5 letters = 5, 6 = 6…), and 7 more for a pangram — a word using all seven letters, marked +7 in the list. A word written by two players or more is cancelled for everyone. Words that are not on the list score nothing. The reader does the adding up: scored words in bold, cancelled ones struck through; tap a word to see who wrote it, Details lists each player's words.

End of the match
After the last round the reader shows the final scoreboard: the player with the most points wins. Players with the same score share their place; if several share the first place, it's a tie. New game starts a new match with the same players.
]])

local PARTY_FR = [[
Spelling Bee · à plusieurs — Règles

Une chasse aux mots sur papier pour 2 à 8 joueurs autour d'une liseuse posée au milieu de la table.

Préparation
Dans le menu, choisissez les Joueurs (2 à 8) et tapez leurs noms (Noms des joueurs, gardés pour la prochaine fois), le nombre de Manches (1 à 5), le Chrono (inactif, ou 3 à 10 min) et la Langue. Chacun prend une feuille et un stylo.

Une manche
La liseuse montre la ruche et le compte à rebours. Jusqu'à la fin du temps, chaque joueur écrit en secret des mots formés avec les sept lettres :
• au moins 4 lettres,
• chaque mot contient la lettre centrale (la noire),
• une lettre peut servir plusieurs fois.
Mélanger déplace les lettres extérieures, Pause arrête le chrono, Fin de manche termine la manche plus tôt (ou la termine quand il n'y a pas de chrono).
Stylos levés : la liste des réponses s'affiche, par longueur, avec les points de chaque longueur. La liseuse fait ensuite le tour de la table : chaque joueur à son tour touche les mots de la liste qu'il a écrits, puis Joueur suivant ; le dernier touche Terminé. Les mots déjà pris par un joueur précédent sont grisés. Joueur précédent revient en arrière pour corriger une erreur.

Points
Un mot écrit par un seul joueur lui rapporte 1 point s'il a 4 lettres, sinon un point par lettre (5 lettres = 5, 6 = 6…), et 7 de plus pour un pangramme — un mot qui utilise les sept lettres, marqué +7 dans la liste. Un mot écrit par deux joueurs ou plus est annulé pour tout le monde. Les mots absents de la liste ne rapportent rien. La liseuse fait les comptes : mots marqués en gras, mots annulés barrés ; touchez un mot pour voir qui l'a écrit, Détails liste les mots de chaque joueur.

Fin de partie
Après la dernière manche, la liseuse affiche le classement final : le joueur qui a le plus de points gagne. Des joueurs à égalité partagent leur place ; si plusieurs sont premiers ex aequo, c'est une égalité. Nouvelle partie relance une partie avec les mêmes joueurs.
]]

return {
    solo  = { SOLO_EN, SOLO_FR },
    party = { PARTY_EN, PARTY_FR },
}
