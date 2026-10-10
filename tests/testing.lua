-- A small test runner: test(name, fn) runs fn and reports, eq and ok check,
-- and done() prints a summary and exits with a status make understands.

local M = { passed = 0, failed = 0 }

function M.eq(got, want, what)
  if got ~= want then
    error(("%s: got %s, want %s"):format(what or "value", ("%q"):format(tostring(got)), ("%q"):format(tostring(want))), 2)
  end
end

function M.ok(cond, what)
  if not cond then error((what or "condition") .. " is not true", 2) end
end

function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
  else
    M.failed = M.failed + 1
    print("FAIL " .. name .. "\n     " .. tostring(err))
  end
end

function M.done(suite)
  print(("%s: %d passed, %d failed"):format(suite, M.passed, M.failed))
  os.exit(M.failed == 0 and 0 or 1)
end

return M
