-- Family-friendly words: the game is also played at a family table, so no
-- answer it reveals or hints at may be one of tools/blocklist_<lang>.txt's
-- vulgar, sexual, scatological, slur or drug-related words.
-- tools/build_words.py drops them; this checks the generated files really are
-- clean, and that every puzzle still has a pangram without them.
package.path = "./?.lua;./common/?.lua;" .. package.path

local Board = dofile("board.lua")

local function blocklist(lang)
    local set, n = {}, 0
    for line in io.lines("tools/blocklist_" .. lang .. ".txt") do
        local w = line:match("^(%u+)%s*$")
        if w then set[w] = true; n = n + 1 end
    end
    return set, n
end

describe("family-friendly word data", function()
    for _, lang in ipairs({ "en", "fr" }) do
        it("the " .. lang .. " lists have no blocklisted word", function()
            local blocked, n = blocklist(lang)
            assert.is_true(n > 250)
            local lists = Board.loadLang(lang)
            assert.is_true(#lists.core > 1000)
            for _, key in ipairs({ "core", "extra" }) do
                for _, w in ipairs(lists[key]) do
                    assert.is_false(blocked[w] == true, w)
                end
            end
        end)

        it("every " .. lang .. " puzzle still has a pangram", function()
            local lists = Board.loadLang(lang)
            for _, spec in ipairs(lists.puzzles) do
                local b = Board:new{ lang = lang, empty = true }
                b:setPuzzle(spec)
                local pangram = false
                for _, w in ipairs(b.answers) do
                    if Board.isPangram(w) then pangram = true break end
                end
                assert.is_true(pangram, spec)
            end
        end)
    end
end)
