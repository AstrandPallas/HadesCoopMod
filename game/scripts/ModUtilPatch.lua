--
-- Copyright (c) Uladzislau Nikalayevich <thenormalnij@gmail.com>. All rights reserved.
-- Licensed under the MIT license. See LICENSE file in the project root for details.
--
-- ModUtil ships a metatable-respecting `table.concat` override at lines
-- 224-235 of its main file. The override caches a temp table in `wt` for
-- reuse across calls:
--
--   local t = rawnext( wt ) or { }    -- BUG: rawnext returns (key, value);
--   rawset( wt, 1, t )                -- only the KEY is checked by `or`,
--   ...                               -- so once wt has an entry at key 1,
--                                     -- subsequent calls get t = 1 (the key).
--   rawset( t, k, ... )               -- crashes: "bad argument #1 to
--                                     -- 'rawset' (table expected, got number)".
--
-- This patch replaces the global `table.concat` with a non-cached version.
-- It only protects callers that look up `table.concat` through the global
-- table at call time — vanilla scripts that captured `local table = table`
-- or `local concat = table.concat` before this patch loaded will still hit
-- ModUtil's broken closure. So this is a best-effort safety net, not a
-- complete fix.
--

local rawconcat = table.rawconcat or table.concat

function table.concat(tbl, sep, i, j)
    i = i or 1
    j = j or tbl.n or #tbl
    if i > j then return "" end
    sep = sep or ""

    local t = {}
    for k = i, j, 1 do
        t[k] = tostring(tbl[k])
    end
    return rawconcat(t, sep, i, j)
end

return {}
