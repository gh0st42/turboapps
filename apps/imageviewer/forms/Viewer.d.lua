---@meta
-- What Viewer.form.lua has in it, for a language server. Written by tlua
-- design each time the form is saved; changing it here changes nothing.

---@class forms.Viewer: gui.Form
---@field cnvFull gui.Canvas
---@field cnvImage gui.Canvas
---@field lblStatus gui.Label
---@field lstFiles gui.ListBox
---@field splMain gui.Splitter
