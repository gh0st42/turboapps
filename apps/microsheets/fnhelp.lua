-- The help for formulas: every function, what it does, its parameters and
-- examples, and pages about formulas in general. The examples are worked
-- out on the sample sheet below, in cell E1, and the tests check that each
-- gives the result written here.
--
-- A parameter is { name, what it is }, with optional = true when it can be
-- left out (default says what it is then), and more = true when any
-- number of them can follow.

local M = {}

-- sample is the sheet the examples use, A1:C6.
M.sample = {
  { "Item", "Qty", "Price" },
  { "apple", "3", "0.5" },
  { "pear", "5", "0.75" },
  { "apple", "7", "0.5" },
  { "fig", "", "2" },
  { "Kiwi Fruit", "-2.5", "TRUE" },
}

M.categories = { "Math", "Statistics", "Conditions", "Logic", "Text", "Lookup", "Information" }

local function p(name, what, extra)
  local t = { name, what }
  if extra then for k, v in pairs(extra) do t[k] = v end end
  return t
end
local OPT = function(default) return { optional = true, default = default } end
local MORE = { optional = true, more = true }

M.functions = {
  ---------------------------------------------------------------- math
  { name = "SUM", cat = "Math", does = "Adds numbers up. In a range only numbers count; text and empty cells are passed over.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=SUM(B2:B6)", "12.5" }, { "=SUM(B2,B3,10)", "18" } } },
  { name = "PRODUCT", cat = "Math", does = "Multiplies numbers together. In a range only numbers count.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=PRODUCT(B2:B3)", "15" }, { "=PRODUCT(2,3,4)", "24" } } },
  { name = "SUMPRODUCT", cat = "Math", does = "Multiplies ranges of the same shape cell by cell, and adds the products up. Cells that are not numbers count as 0.",
    params = { p("range1", "the first range"), p("range2", "more ranges of the same size", MORE) },
    examples = { { "=SUMPRODUCT(B2:B4,C2:C4)", "8.75" } } },
  { name = "ABS", cat = "Math", does = "The number without its sign.",
    params = { p("number", "any number") }, examples = { { "=ABS(-4)", "4" }, { "=ABS(B6)", "2.5" } } },
  { name = "SIGN", cat = "Math", does = "1 for a number above 0, -1 for one below, and 0 for 0.",
    params = { p("number", "any number") }, examples = { { "=SIGN(B6)", "-1" } } },
  { name = "INT", cat = "Math", does = "Rounds down to a whole number: towards minus infinity, so INT(-2.5) is -3.",
    params = { p("number", "any number") }, examples = { { "=INT(7.9)", "7" }, { "=INT(-2.5)", "-3" } } },
  { name = "TRUNC", cat = "Math", does = "Cuts the digits after so many decimals off, towards 0.",
    params = { p("number", "any number"), p("digits", "how many decimals to keep", OPT("0")) },
    examples = { { "=TRUNC(-2.57)", "-2" }, { "=TRUNC(3.14159,2)", "3.14" } } },
  { name = "ROUND", cat = "Math", does = "Rounds to so many decimals, halves away from 0. Negative digits round to tens, hundreds and so on.",
    params = { p("number", "any number"), p("digits", "how many decimals", OPT("0")) },
    examples = { { "=ROUND(2.5)", "3" }, { "=ROUND(3.14159,2)", "3.14" }, { "=ROUND(1234,-2)", "1200" } } },
  { name = "ROUNDUP", cat = "Math", does = "Rounds away from 0, to so many decimals.",
    params = { p("number", "any number"), p("digits", "how many decimals", OPT("0")) },
    examples = { { "=ROUNDUP(1.01,1)", "1.1" }, { "=ROUNDUP(-1.2)", "-2" } } },
  { name = "ROUNDDOWN", cat = "Math", does = "Rounds towards 0, to so many decimals.",
    params = { p("number", "any number"), p("digits", "how many decimals", OPT("0")) },
    examples = { { "=ROUNDDOWN(1.99,1)", "1.9" } } },
  { name = "CEILING", cat = "Math", does = "Rounds up to a multiple of significance.",
    params = { p("number", "any number"), p("significance", "the multiple", OPT("1")) },
    examples = { { "=CEILING(4.2)", "5" }, { "=CEILING(23,5)", "25" } } },
  { name = "FLOOR", cat = "Math", does = "Rounds down to a multiple of significance.",
    params = { p("number", "any number"), p("significance", "the multiple", OPT("1")) },
    examples = { { "=FLOOR(4.8)", "4" }, { "=FLOOR(23,5)", "20" } } },
  { name = "MOD", cat = "Math", does = "The remainder of dividing, with the divisor's sign.",
    params = { p("number", "what is divided"), p("divisor", "what it is divided by; not 0") },
    examples = { { "=MOD(10,3)", "1" }, { "=MOD(-3,5)", "2" }, { "=MOD(1,0)", "#DIV/0!" } } },
  { name = "POWER", cat = "Math", does = "A number raised to a power: the same as base^exponent.",
    params = { p("base", "the number"), p("exponent", "the power") },
    examples = { { "=POWER(2,10)", "1024" }, { "=POWER(9,0.5)", "3" } } },
  { name = "SQRT", cat = "Math", does = "The square root. A number below 0 has none: #NUM!.",
    params = { p("number", "0 or more") }, examples = { { "=SQRT(16)", "4" }, { "=SQRT(-1)", "#NUM!" } } },
  { name = "EXP", cat = "Math", does = "e raised to a power.",
    params = { p("number", "the power") }, examples = { { "=EXP(1)", "2.718281828" } } },
  { name = "LN", cat = "Math", does = "The natural logarithm, to base e.",
    params = { p("number", "above 0") }, examples = { { "=LN(EXP(2))", "2" } } },
  { name = "LOG", cat = "Math", does = "The logarithm to a base.",
    params = { p("number", "above 0"), p("base", "above 0, not 1", OPT("10")) },
    examples = { { "=LOG(1000)", "3" }, { "=LOG(8,2)", "3" } } },
  { name = "LOG10", cat = "Math", does = "The logarithm to base 10.",
    params = { p("number", "above 0") }, examples = { { "=LOG10(100)", "2" } } },
  { name = "PI", cat = "Math", does = "π, to the 15 digits a number holds.",
    params = {}, examples = { { "=PI()", "3.141592654" } } },

  ---------------------------------------------------------------- statistics
  { name = "AVERAGE", cat = "Statistics", also = "AVG", does = "The mean of the numbers: their sum over how many there are. In a range only numbers count. None at all is #DIV/0!.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=AVERAGE(B2:B4)", "5" }, { "=AVG(C2:C5)", "0.9375" } } },
  { name = "AVG", cat = "Statistics", alias = "AVERAGE" },
  { name = "MEDIAN", cat = "Statistics", does = "The middle number once they are in order; with an even count, the mean of the middle two.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=MEDIAN(B2:B4)", "5" }, { "=MEDIAN(1,5,2,8)", "3.5" } } },
  { name = "MAX", cat = "Statistics", does = "The largest number, or 0 when there are none.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=MAX(B2:B6)", "7" }, { "=MAX(C2:C5,10)", "10" } } },
  { name = "MIN", cat = "Statistics", does = "The smallest number, or 0 when there are none.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=MIN(B2:B6)", "-2.5" } } },
  { name = "COUNT", cat = "Statistics", does = "How many numbers there are. In a range, only cells holding numbers count.",
    params = { p("value1", "a value, a cell or a range"), p("value2", "more of them", MORE) },
    examples = { { "=COUNT(A1:C6)", "8" }, { "=COUNT(B2:B6)", "4" } } },
  { name = "COUNTA", cat = "Statistics", does = "How many cells are not empty, whatever they hold.",
    params = { p("value1", "a value, a cell or a range"), p("value2", "more of them", MORE) },
    examples = { { "=COUNTA(A1:C6)", "17" } } },
  { name = "COUNTBLANK", cat = "Statistics", does = "How many cells of a range are empty.",
    params = { p("range", "the cells to look at") }, examples = { { "=COUNTBLANK(A1:C6)", "1" } } },
  { name = "STDEV", cat = "Statistics", does = "The standard deviation of a sample: how far the numbers spread from their mean.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=STDEV(2,4,4,4,5,5,7,9)", "2.138089935" } } },
  { name = "VAR", cat = "Statistics", does = "The variance of a sample: STDEV squared.",
    params = { p("number1", "a number, a cell or a range"), p("number2", "more of them", MORE) },
    examples = { { "=VAR(1,2,3,4)", "1.666666667" } } },

  ---------------------------------------------------------------- conditions
  { name = "SUMIF", cat = "Conditions", does = "Adds up the cells that meet a condition. With sum_range, the cells beside them are added instead, cell for cell.",
    params = { p("range", "the cells the condition is tested on"), p("criterion", "the condition (see Conditions)"),
      p("sum_range", "the cells to add, the same shape as range", OPT("range itself")) },
    examples = { { "=SUMIF(A2:A6,\"apple\",B2:B6)", "10" }, { "=SUMIF(B2:B6,\">4\")", "12" } } },
  { name = "COUNTIF", cat = "Conditions", does = "How many cells of a range meet a condition.",
    params = { p("range", "the cells to test"), p("criterion", "the condition (see Conditions)") },
    examples = { { "=COUNTIF(A2:A6,\"apple\")", "2" }, { "=COUNTIF(A2:A6,\"*i*\")", "2" }, { "=COUNTIF(C2:C5,\"<1\")", "3" } } },
  { name = "AVERAGEIF", cat = "Conditions", does = "The mean of the cells that meet a condition, or of the cells beside them in average_range.",
    params = { p("range", "the cells the condition is tested on"), p("criterion", "the condition (see Conditions)"),
      p("average_range", "the cells to average, the same shape as range", OPT("range itself")) },
    examples = { { "=AVERAGEIF(A2:A6,\"<>pear\",C2:C6)", "1" } } },

  ---------------------------------------------------------------- logic
  { name = "IF", cat = "Logic", does = "One value when a condition is true, another when it is not. Only the one chosen is worked out, so the other may be an error.",
    params = { p("condition", "a comparison or anything true or false"), p("value_if_true", "the result when it is true"),
      p("value_if_false", "the result when it is not", OPT("FALSE")) },
    examples = { { "=IF(B2>4,\"many\",\"few\")", "few" }, { "=IF(B3>4,\"many\")", "many" }, { "=IF(B5=0,0,1/B5)", "0" } } },
  { name = "IFERROR", cat = "Logic", does = "A value, or another one when it is an error of any kind.",
    params = { p("value", "what to try"), p("value_if_error", "the result when it is an error", OPT("empty")) },
    examples = { { "=IFERROR(1/0,\"none\")", "none" }, { "=IFERROR(B2*2,0)", "6" } } },
  { name = "IFNA", cat = "Logic", does = "A value, or another one when it is #N/A: what lookups give when they find nothing.",
    params = { p("value", "what to try"), p("value_if_na", "the result when it is #N/A", OPT("empty")) },
    examples = { { "=IFNA(VLOOKUP(\"plum\",A2:C6,2,FALSE),\"no plums\")", "no plums" } } },
  { name = "AND", cat = "Logic", does = "TRUE when all of its values are true.",
    params = { p("logical1", "a truth value, a comparison or a range of them"), p("logical2", "more of them", MORE) },
    examples = { { "=AND(B2>0,B3>0)", "TRUE" }, { "=AND(B2>0,B6>0)", "FALSE" } } },
  { name = "OR", cat = "Logic", does = "TRUE when any of its values is true.",
    params = { p("logical1", "a truth value, a comparison or a range of them"), p("logical2", "more of them", MORE) },
    examples = { { "=OR(B2>5,B4>5)", "TRUE" } } },
  { name = "XOR", cat = "Logic", does = "TRUE when an odd number of its values are true.",
    params = { p("logical1", "a truth value, a comparison or a range of them"), p("logical2", "more of them", MORE) },
    examples = { { "=XOR(TRUE,FALSE)", "TRUE" }, { "=XOR(TRUE,TRUE)", "FALSE" } } },
  { name = "NOT", cat = "Logic", does = "The opposite truth value.",
    params = { p("logical", "a truth value or a comparison") }, examples = { { "=NOT(B2>4)", "TRUE" } } },
  { name = "TRUE", cat = "Logic", does = "The truth value TRUE. Writing TRUE alone does the same.",
    params = {}, examples = { { "=TRUE()", "TRUE" } } },
  { name = "FALSE", cat = "Logic", does = "The truth value FALSE. Writing FALSE alone does the same.",
    params = {}, examples = { { "=FALSE()", "FALSE" } } },
  { name = "CHOOSE", cat = "Logic", does = "Picks a value by its place in the list: 1 for the first.",
    params = { p("index", "which one, from 1"), p("value1", "the first to choose from"), p("value2", "more of them", MORE) },
    examples = { { "=CHOOSE(2,\"red\",\"green\",\"blue\")", "green" } } },

  ---------------------------------------------------------------- text
  { name = "CONCAT", cat = "Text", also = "CONCATENATE", does = "Joins text together, and the values of ranges, cell by cell. The & operator joins two values too.",
    params = { p("text1", "text, a value, a cell or a range"), p("text2", "more of them", MORE) },
    examples = { { "=CONCAT(A2,\" x \",B2)", "apple x 3" }, { "=CONCAT(B2:B4)", "357" } } },
  { name = "CONCATENATE", cat = "Text", alias = "CONCAT" },
  { name = "TEXTJOIN", cat = "Text", does = "Joins text with a delimiter between, leaving empty cells out if asked.",
    params = { p("delimiter", "what goes between, such as \", \""), p("ignore_empty", "TRUE to leave empty values out"),
      p("text1", "text, a value, a cell or a range"), p("text2", "more of them", MORE) },
    examples = { { "=TEXTJOIN(\", \",TRUE,A2:A5)", "apple, pear, apple, fig" } } },
  { name = "LEN", cat = "Text", does = "How many characters the text has (counted in bytes, so a letter such as é counts as 2).",
    params = { p("text", "any text") }, examples = { { "=LEN(A6)", "10" } } },
  { name = "UPPER", cat = "Text", does = "The text in capitals.",
    params = { p("text", "any text") }, examples = { { "=UPPER(A2)", "APPLE" } } },
  { name = "LOWER", cat = "Text", does = "The text in small letters.",
    params = { p("text", "any text") }, examples = { { "=LOWER(A6)", "kiwi fruit" } } },
  { name = "PROPER", cat = "Text", does = "The text with each word's first letter a capital and the rest small.",
    params = { p("text", "any text") }, examples = { { "=PROPER(\"hello wORLD\")", "Hello World" } } },
  { name = "TRIM", cat = "Text", does = "The text without spaces at its ends, and with one space wherever there were several.",
    params = { p("text", "any text") }, examples = { { "=TRIM(\"  a   b \")", "a b" } } },
  { name = "LEFT", cat = "Text", does = "The first characters of the text.",
    params = { p("text", "any text"), p("count", "how many", OPT("1")) },
    examples = { { "=LEFT(A6,4)", "Kiwi" }, { "=LEFT(A2)", "a" } } },
  { name = "RIGHT", cat = "Text", does = "The last characters of the text.",
    params = { p("text", "any text"), p("count", "how many", OPT("1")) },
    examples = { { "=RIGHT(A6,5)", "Fruit" } } },
  { name = "MID", cat = "Text", does = "Characters from the middle of the text.",
    params = { p("text", "any text"), p("start", "where to start, 1 for the first character"), p("count", "how many") },
    examples = { { "=MID(A6,6,3)", "Fru" } } },
  { name = "REPT", cat = "Text", does = "The text so many times over.",
    params = { p("text", "any text"), p("times", "how many times") },
    examples = { { "=REPT(\"ab\",3)", "ababab" }, { "=REPT(\"|\",B2)", "|||" } } },
  { name = "SUBSTITUTE", cat = "Text", does = "The text with every old piece of it replaced by new.",
    params = { p("text", "any text"), p("old", "what to replace"), p("new", "what to put instead") },
    examples = { { "=SUBSTITUTE(A6,\" \",\"-\")", "Kiwi-Fruit" } } },
  { name = "FIND", cat = "Text", does = "Where one text starts within another, from 1, telling capitals from small letters. Not found is #VALUE!.",
    params = { p("find_text", "what to look for"), p("within_text", "where to look"), p("start", "where to start looking", OPT("1")) },
    examples = { { "=FIND(\"F\",A6)", "6" }, { "=FIND(\"f\",A6)", "#VALUE!" } } },
  { name = "SEARCH", cat = "Text", does = "Where one text starts within another, from 1, without regard to case. Not found is #VALUE!.",
    params = { p("find_text", "what to look for"), p("within_text", "where to look"), p("start", "where to start looking", OPT("1")) },
    examples = { { "=SEARCH(\"f\",A6)", "6" } } },
  { name = "EXACT", cat = "Text", does = "TRUE when two texts are the same, capitals and all.",
    params = { p("text1", "a text"), p("text2", "another") },
    examples = { { "=EXACT(A2,\"apple\")", "TRUE" }, { "=EXACT(A2,\"Apple\")", "FALSE" } } },
  { name = "VALUE", cat = "Text", does = "Reads text as a number. Text that is not one is #VALUE!.",
    params = { p("text", "text with a number in it") },
    examples = { { "=VALUE(\"12.5\")+1", "13.5" }, { "=VALUE(\"50%\")", "0.5" } } },
  { name = "FIXED", cat = "Text", does = "Writes a number as text with so many decimals, and with commas between the thousands unless no_commas is TRUE.",
    params = { p("number", "any number"), p("decimals", "how many decimals", OPT("2")), p("no_commas", "TRUE to leave the commas out", OPT("FALSE")) },
    examples = { { "=FIXED(1234.567)", "1,234.57" }, { "=FIXED(1234.567,1,TRUE)", "1234.6" } } },

  ---------------------------------------------------------------- lookup
  { name = "VLOOKUP", cat = "Lookup", does = "Looks a value up in the first column of a table, and gives the cell from another column of the row it is in. With approximate (the default), the first column must be sorted, and the last row not above the value is taken.",
    params = { p("value", "what to look for"), p("table", "the range to look in, its first column searched"),
      p("column_index", "which column's value to give, 1 for the first"), p("approximate", "FALSE to find the value exactly", OPT("TRUE")) },
    examples = { { "=VLOOKUP(\"pear\",A2:C6,3,FALSE)", "0.75" }, { "=VLOOKUP(\"plum\",A2:C6,2,FALSE)", "#N/A" } } },
  { name = "HLOOKUP", cat = "Lookup", does = "VLOOKUP turned on its side: looks along the first row, and gives the cell from another row of that column.",
    params = { p("value", "what to look for"), p("table", "the range to look in, its first row searched"),
      p("row_index", "which row's value to give, 1 for the first"), p("approximate", "FALSE to find the value exactly", OPT("TRUE")) },
    examples = { { "=HLOOKUP(\"Price\",A1:C6,3,FALSE)", "0.75" } } },
  { name = "INDEX", cat = "Lookup", does = "The cell at a row and column of a range, counted from 1. A range of one row takes a single number as the column.",
    params = { p("range", "the cells"), p("row", "which row, from 1"), p("column", "which column, from 1", OPT("1")) },
    examples = { { "=INDEX(A2:C6,2,3)", "0.75" }, { "=INDEX(A1:C1,2)", "Qty" } } },
  { name = "MATCH", cat = "Lookup", does = "Where a value is in a row or column of cells, from 1. match_type 0 finds it exactly (text without regard to case, with * and ? as wildcards); 1 finds the last value not above it, in a list sorted up; -1 the last not below it, in one sorted down.",
    params = { p("value", "what to look for"), p("range", "one row or one column"), p("match_type", "0, 1 or -1", OPT("1")) },
    examples = { { "=MATCH(\"fig\",A2:A6,0)", "4" }, { "=INDEX(C2:C6,MATCH(\"fig\",A2:A6,0))", "2" } } },
  { name = "ROW", cat = "Lookup", does = "The row number of a reference, or of the formula's own cell.",
    params = { p("reference", "a cell or a range", OPT("the formula's own cell")) },
    examples = { { "=ROW(C5)", "5" }, { "=ROW()", "1" } } },
  { name = "COLUMN", cat = "Lookup", does = "The column number of a reference (A is 1), or of the formula's own cell.",
    params = { p("reference", "a cell or a range", OPT("the formula's own cell")) },
    examples = { { "=COLUMN(C5)", "3" }, { "=COLUMN()", "5" } } },
  { name = "ROWS", cat = "Lookup", does = "How many rows a range has.",
    params = { p("range", "a range") }, examples = { { "=ROWS(A2:C6)", "5" } } },
  { name = "COLUMNS", cat = "Lookup", does = "How many columns a range has.",
    params = { p("range", "a range") }, examples = { { "=COLUMNS(A2:C6)", "3" } } },

  ---------------------------------------------------------------- information
  { name = "ISBLANK", cat = "Information", does = "TRUE when the cell is empty.",
    params = { p("value", "a cell") }, examples = { { "=ISBLANK(B5)", "TRUE" }, { "=ISBLANK(B4)", "FALSE" } } },
  { name = "ISNUMBER", cat = "Information", does = "TRUE when the value is a number.",
    params = { p("value", "anything") }, examples = { { "=ISNUMBER(B2)", "TRUE" }, { "=ISNUMBER(A2)", "FALSE" } } },
  { name = "ISTEXT", cat = "Information", does = "TRUE when the value is text.",
    params = { p("value", "anything") }, examples = { { "=ISTEXT(A2)", "TRUE" } } },
  { name = "ISERROR", cat = "Information", does = "TRUE when the value is an error of any kind.",
    params = { p("value", "anything") }, examples = { { "=ISERROR(1/0)", "TRUE" } } },
  { name = "ISNA", cat = "Information", does = "TRUE when the value is #N/A.",
    params = { p("value", "anything") }, examples = { { "=ISNA(MATCH(\"plum\",A2:A6,0))", "TRUE" } } },
  { name = "NA", cat = "Information", does = "The error #N/A: a value not there, which charts and sums pass over by IFNA.",
    params = {}, examples = { { "=NA()", "#N/A" } } },
}

M.byName = {}
for _, f in ipairs(M.functions) do M.byName[f.name] = f end

-- doc gives a function's help, following an alias to what it stands for.
function M.doc(name)
  local f = M.byName[(name or ""):upper()]
  if f and f.alias then
    local target = M.byName[f.alias]
    local copy = {}
    for k, v in pairs(target) do copy[k] = v end
    copy.name, copy.aliasOf = f.name, target.name
    return copy
  end
  return f
end

-- syntax writes how a function is called: SUMIF(range, criterion, [sum_range]).
function M.syntax(f, current)
  local parts = {}
  for i, prm in ipairs(f.params or {}) do
    local name = prm[1]
    if i == current then name = name:upper() end
    if prm.more then
      parts[#parts + 1] = "[" .. name .. "], ..."
    elseif prm.optional then
      parts[#parts + 1] = "[" .. name .. "]"
    else
      parts[#parts + 1] = name
    end
  end
  return f.name .. "(" .. table.concat(parts, ", ") .. ")"
end

-- param is the parameter the n'th argument fills: the last repeats.
function M.param(f, n)
  local params = f.params or {}
  if n <= #params then return params[n] end
  local last = params[#params]
  if last and last.more then return last end
end

local WIDTH = 60 -- what a page's lines are wrapped at

-- wrap breaks text into lines of at most width, the first starting with
-- first and the rest with indent.
local function wrap(text, first, indent, width)
  width = width or WIDTH
  local lines, line = {}, first
  for word in text:gmatch("%S+") do
    if #line + #word + 1 > width and line ~= first and line ~= indent then
      lines[#lines + 1] = line
      line = indent .. word
    elseif line == first or line == indent then
      line = line .. word
    else
      line = line .. " " .. word
    end
  end
  lines[#lines + 1] = line
  return table.concat(lines, "\n")
end

-- page writes a function's help as text.
function M.page(name)
  local f = M.doc(name)
  if not f then return nil end
  local out = { M.syntax(f), "" }
  if f.aliasOf then out[#out + 1] = f.name .. " is another name for " .. f.aliasOf .. "." out[#out + 1] = "" end
  if f.also then out[#out + 1] = "Also written " .. f.also .. "." out[#out + 1] = "" end
  out[#out + 1] = wrap(f.does, "", "")
  if #(f.params or {}) > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "Parameters"
    for _, prm in ipairs(f.params) do
      local note = prm[2]
      if prm.more then note = note .. "; as many as you like"
      elseif prm.optional then note = note .. "; can be left out" .. (prm.default and (", when it is " .. prm.default) or "") end
      out[#out + 1] = wrap(note, ("  %-14s "):format(prm[1]), (" "):rep(17))
    end
  else
    out[#out + 1] = ""
    out[#out + 1] = "No parameters: write the parentheses empty."
  end
  out[#out + 1] = ""
  out[#out + 1] = "Examples (on the sample sheet, in cell E1)"
  for _, ex in ipairs(f.examples or {}) do
    out[#out + 1] = ("  %-40s %s"):format(ex[1], ex[2])
  end
  out[#out + 1] = ""
  out[#out + 1] = M.sampleText()
  return table.concat(out, "\n")
end

-- sampleText draws the sample sheet as text.
function M.sampleText()
  local widths = { 12, 6, 7 }
  local out = { "The sample sheet:", ("     %-12s %-6s %-7s"):format("A", "B", "C") }
  for r, row in ipairs(M.sample) do
    local cells = {}
    for c = 1, 3 do cells[c] = ("%-" .. widths[c] .. "s"):format(row[c] or "") end
    out[#out + 1] = ("  %d  %s"):format(r, table.concat(cells, " "))
  end
  return table.concat(out, "\n")
end

---------------------------------------------------------------- while typing

-- callAt finds the function a formula being typed is in at caret (bytes
-- before it), and which of its arguments the caret is in, from 1.
function M.callAt(text, caret)
  local s = text:sub(1, caret)
  if s:sub(1, 1) ~= "=" then return nil end
  local stack = {}
  local i = 2
  while i <= #s do
    local ch = s:sub(i, i)
    if ch == '"' or ch == "'" then
      local j = s:find(ch, i + 1, true)
      if not j then break end -- the caret is inside the text
      i = j
    elseif ch:find("[%a_]") then
      local word = s:match("^[%w_%.%$]+", i)
      local after = i + #word
      if s:sub(after, after) == "(" then
        stack[#stack + 1] = { name = word:upper(), arg = 1 }
        i = after
      else
        i = after - 1
      end
    elseif ch == "(" then
      stack[#stack + 1] = { arg = 1 }
    elseif ch == ")" then
      stack[#stack] = nil
    elseif (ch == "," or ch == ";") and #stack > 0 then
      stack[#stack].arg = stack[#stack].arg + 1
    end
    i = i + 1
  end
  for k = #stack, 1, -1 do
    if stack[k].name then return stack[k].name, stack[k].arg end
  end
end

-- hint is a line about the function being typed: its syntax with the
-- parameter at the caret in capitals, and what that parameter is.
function M.hint(text, caret)
  local name, arg = M.callAt(text, caret)
  local f = name and M.doc(name)
  if not f then
    if name then return name .. " is not a function: F1 lists them" end
    return nil
  end
  local line = M.syntax(f, arg)
  local prm = M.param(f, arg)
  if prm then
    line = line .. "     " .. prm[1] .. ": " .. prm[2]
  elseif #(f.params or {}) == 0 then
    line = line .. "     no parameters"
  else
    line = line .. "     too many arguments"
  end
  return line .. "     (F1 for help)"
end

---------------------------------------------------------------- pages

-- topics are pages about formulas in general, shown before the functions.
M.topics = {
  { name = "Formulas", text = [[
A formula starts with =, and works out a value from numbers, text, cells
and functions. It is worked out again whenever a cell it reads changes.

  =B2*C2                the cells' values multiplied
  =SUM(B2:B9)           a function, given a range
  =IF(B2>4,"many","few")
  ="Total: "&SUM(B2:B9) text joined to a number

While you type one, after = ( , or an operator, the arrow keys and the
mouse point at cells and put their references in; Shift with them makes a
range. F4 cycles the reference at the caret through A1, $A$1, A$1 and $A1.
The status bar shows the function you are in and the parameter you are at,
and F1 opens its help. Parentheses left open at the end are closed for you.

A number, TRUE or FALSE typed without = is that value; anything else is
text. Start with ' to keep something text: '007.]] },
  { name = "References", text = [[
  B2            one cell
  B2:D9         a range, from one corner to the other
  B:B           a whole column; B:D, several
  Sheet2!B2     a cell on another sheet
  'Q1 Sales'!B2 a sheet whose name has spaces in it: in single quotes

Copying a formula, filling it down or across, or sorting rows moves its
references with it: =A1*2 copied one row down is =A2*2. A $ keeps the part
after it from moving: $A$1 always, A$1 its row, $A1 its column.

Putting rows or columns in, or taking them out, keeps references pointing
at the same cells. A reference to cells taken out becomes #REF!.]] },
  { name = "Operators", text = [[
In the order they are worked out, first to last:

  -        minus, before a value: -A1
  %        per cent, after one: 50% is 0.5
  ^        power: 2^10 is 1024
  * /      multiply, divide
  + -      add, subtract
  &        join as text: "a"&1 is a1
  = <> < > <= >=   compare, giving TRUE or FALSE

Parentheses change the order: (1+2)*3 is 9. Comparing puts numbers before
text and text before TRUE and FALSE; text compares without regard to case,
so "abc"="ABC" is TRUE. Text that reads as a number counts as one in
arithmetic: "3"+1 is 4.]] },
  { name = "Conditions", text = [[
SUMIF, COUNTIF and AVERAGEIF take a condition, written as text:

  "apple"     the same text, without regard to case
  "a*"        * matches any text, ? any one character
  "<>pear"    anything but pear
  ">4"        a number above 4; also <, <=, >=, = and <>
  "="         an empty cell
  4           a number: the same number

A condition can be put together from a cell: ">"&B2.]] },
  { name = "Errors", text = [[
  #DIV/0!   dividing by 0, or averaging nothing
  #VALUE!   the wrong kind of value: text where a number is needed
  #REF!     a reference to cells that were deleted, or to no sheet
  #NAME?    a function there is no such one of
  #N/A      a lookup that found nothing; NA() makes one
  #NUM!     no such number: SQRT(-1), or one too big
  #CIRC!    a formula that reads its own cell, through others or not
  #ERROR!   a formula that does not read: a missing ) or operator

An error in a cell passes on to the formulas that read it. IFERROR and
IFNA put something else in its place.]] },
}

return M
