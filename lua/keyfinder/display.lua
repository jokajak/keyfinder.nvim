local config = require("keyfinder.config")
local Layout = require("keyfinder.layout")
local Keys = require("keyfinder.keys")
local Util = require("keyfinder.util")

local highlight = vim.api.nvim_buf_add_highlight

local highlight_links = {
  [""] = "Search",
  Prefix = "IncSearch",
}

local M = {}

M.mode = "n"
M.buf = nil
M.win = nil

function M.is_valid()
  return M.buf
    and M.win
    and vim.api.nvim_buf_is_valid(M.buf)
    and vim.api.nvim_buf_is_loaded(M.buf)
    and vim.api.nvim_win_is_valid(M.win)
end

local function set_highlights(layout, mappings)
  -- a list of mappings
  for keycap, mapping in pairs(mappings) do
    -- another list of mappings?
    local group = #mapping == 1 and "" or "Prefix"
    group = "Keyfinder" .. group
    local keycap_position = layout.keycap_positions[string.lower(keycap)]
    -- account for the header
    if keycap_position then
      local row = keycap_position.row + 2
      -- This fails because the positions are calculated as strings, not bytes
      highlight(M.buf, config.namespace, group, row, keycap_position.from, keycap_position.to)
    end
  end
end

function M.show()
  if M.is_valid() then
    return
  end

  -- get current dimensions
  local width = vim.o.columns
  local height = vim.o.lines

  -- configure the size
  local win_height = config.options.window.rows
  win_height = win_height + config.options.window.margin[1]
  win_height = win_height + config.options.window.margin[3]
  local win_width = config.options.window.columns
  win_width = win_width + config.options.window.margin[2]
  win_width = win_width + config.options.window.margin[4]

  -- calculate starting position
  local row = math.ceil((height - win_height) / 2 - 1)
  local col = math.ceil((width - win_width) / 2)

  local opts = {
    relative = "editor",
    style = "minimal",
    width = win_width,
    height = win_height,
    focusable = false,
    row = row,
    col = col,
    border = config.options.window.border,
    noautocmd = true,
  }

  M.buf = vim.api.nvim_create_buf(false, true) -- create new empty buffer

  M.win = vim.api.nvim_open_win(M.buf, true, opts)

  vim.api.nvim_buf_set_option(M.buf, "filetype", "keyfinder")
  vim.api.nvim_buf_set_option(M.buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(M.buf, "bufhidden", "wipe")

  local winhl = "NormalFloat:KeyfinderFloat"
  if vim.fn.hlexists("FloatBorder") == 1 then
    winhl = winhl .. ",FloatBorder:KeyfinderBorder"
  end
  vim.api.nvim_win_set_option(M.win, "winhighlight", winhl)
  vim.api.nvim_win_set_option(M.win, "foldmethod", "manual")
  vim.api.nvim_win_set_option(M.win, "sidescrolloff", 0)
  vim.api.nvim_win_set_option(M.win, "winblend", config.options.window.winblend)

  for k, v in pairs(highlight_links) do
    vim.api.nvim_set_hl(0, "Keyfinder" .. k, { link = v, default = true })
  end
end

function M.on_close()
  M.hide()
end

function M.hide()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
    M.buf = nil
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
  end
end

function M.update_prefix(prefix)
  M.open({
    mode = M.mode,
    prefix = prefix,
  })
end

local function extend_prefix()
  local col = vim.fn.col(".")
  local line = vim.fn.getline(".")
  local char = line:sub(col, col)
  M.update_prefix(M.prefix .. char)
end

function M.set_mappings()
  local keymap_options = {
    nowait = true,
    noremap = true,
    silent = true,
    buffer = M.buf,
  }

  local mappings = {
    q = ":lua require('keyfinder.display').hide()<CR>",
    ["<CR>"] = function()
      extend_prefix()
    end,
    ["<BS>"] = function()
      local prefix = M.prefix
      M.update_prefix(string.sub(prefix, 1, #prefix - 1))
    end,
  }

  for k, v in pairs(mappings) do
    vim.keymap.set("n", k, v, keymap_options)
  end
end

function M.open(opts)
  opts = opts or {}
  M.mode = opts.mode or Util.get_mode()
  M.prefix = opts.prefix or ""

  local buf = vim.api.nvim_get_current_buf()

  if M.is_enabled(buf) then
    if not M.is_valid() then
      M.show()
    end

    local mappings = Keys.get_mappings(M.mode, buf, M.prefix)
    --vim.notify(vim.inspect(mappings), vim.log.levels.DEBUG, { title = "Keyfinder" })
    local layout = Layout:new(opts)
    local _ = layout:calculate_layout()
    M.layout = layout

    M.render(layout, mappings)
    M:set_mappings()
    vim.api.nvim_win_set_cursor(M.win, { 4, 0 })
  end
end

function M.is_enabled(buf)
  local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
  for _, bt in ipairs(config.options.disable.buftypes) do
    if bt == buftype then
      return false
    end
  end

  local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
  for _, bt in ipairs(config.options.disable.filetypes) do
    if bt == filetype then
      return false
    end
  end

  return true
end

--- Utility to make the initial display buffer header
local function make_header(disp, width)
  width = width or vim.api.nvim_win_get_width(0)
  local pad_width = math.floor((width - string.len(config.options.window.title)) / 2.0)
  vim.api.nvim_buf_set_lines(disp.buf, 0, 1, true, {
    string.rep(" ", pad_width) .. config.options.window.title,
    " " .. string.rep(config.options.window.header_sym, width - 2),
  })
end

---@param layout Layout
function M.render(layout, mappings)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local text = layout.text
  local width = text.width

  local start_row = 0
  if config.options.window.show_title then
    make_header(M, width)
    start_row = config.options.window.header_lines
  end
  vim.api.nvim_buf_set_lines(M.buf, start_row, -1, false, text.lines)

  local height = #text.lines + start_row
  vim.api.nvim_win_set_height(M.win, height)
  vim.api.nvim_win_set_width(M.win, width)
  if vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_clear_namespace(M.buf, config.namespace, 0, -1)
  end

  set_highlights(layout, mappings)

  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)
end

return M