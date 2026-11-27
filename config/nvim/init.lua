-- ~/.config/nvim/init.lua
-- Rust / Zig / Python Neovim config (Neovim 0.11+)
--
-- Build/run keys (picked automatically from the file / project):
--            Rust (Cargo.toml)       Zig (build.zig)                  Zig (single file)        Python
--   F5 build cargo build --release   zig build -Doptimize=ReleaseFast  zig build-exe -O ReleaseFast  run file
--   F6 run   cargo run --release     zig build run -Doptimize=...      zig run -O ReleaseFast    run file
--   F7 test  cargo test              zig build test                    zig test                  pytest
--   F8 lint  cargo clippy            zig fmt --check .                 zig ast-check             ruff check
--   q        (in the output window) close it
--
-- Getting around files:
--   <space><space> / <space>ff  fuzzy-find a file in the project    <space>fr  recent files
--   <space>fg  grep the project      <space>/  search this file     <space>,   open buffers
--   <space>e   sidebar file tree     -  oil (edit the folder like text; g? for help)
--   <space>h   pin file (harpoon)    <space>1..5  jump to pinned    <space>H   pin menu
--   Shift+h / Shift+l  prev/next buffer   <space>bd close buffer    s  flash-jump on screen
--   gd / gR / gI / gy  definition / references / implementation / type     <C-o> / <C-i> jump back / forward
-- Debug: <space>db breakpoint, <space>dc start/continue    Tests: <space>tt nearest, <space>tf file
-- Press <space> and wait to see everything.
--
-- Machine-only plugins can go in lua/local_plugins.lua (returns a list of lazy.nvim specs).

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.g.zig_fmt_autosave = 0     -- zls formats on save instead (avoids double formatting)

local o = vim.opt
o.number = true
o.relativenumber = true
o.mouse = "a"
o.clipboard = "unnamedplus"   -- uses wl-clipboard on Wayland
o.termguicolors = true
o.signcolumn = "yes"
o.cursorline = true
o.scrolloff = 8
o.tabstop = 4
o.shiftwidth = 4
o.expandtab = true
o.smartindent = true
o.wrap = false
o.ignorecase = true
o.smartcase = true
o.undofile = true
o.splitright = true
o.splitbelow = true
o.updatetime = 250
o.timeoutlen = 400
o.showmode = false            -- lualine shows the mode
o.autoread = true             -- pick up files changed on disk by other programs

---------------------------------------------------------------------------
-- General keymaps
---------------------------------------------------------------------------
local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Leave terminal mode" })
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit" })
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Reload buffers changed outside Neovim (formatters, git, other tools)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  command = "silent! checktime",
})

-- Diagnostics: gl shows the full message (also ]d / [d to jump)
map("n", "gl", vim.diagnostic.open_float, { desc = "Line diagnostic" })

-- Buffers: open files show in the top bar; Shift+h / Shift+l to flip between them
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bb", "<cmd>e #<CR>", { desc = "Alternate buffer" })
map("n", "<leader>bo", function()                -- close every buffer except this one
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= vim.api.nvim_get_current_buf() and vim.bo[b].buflisted and not vim.bo[b].modified then
      vim.api.nvim_buf_delete(b, {})
    end
  end
end, { desc = "Close other buffers" })

-- Reopen files at the line you left them
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Project root for the current buffer (falls back to the cwd)
local function project_root()
  return vim.fs.root(0, { ".git", "Cargo.toml", "build.zig", "pyproject.toml", "setup.py" })
    or vim.fn.getcwd()
end

-- Python interpreter for a project: active $VIRTUAL_ENV, then .venv / venv, then system
local PY_ROOT_MARKERS = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".venv", "venv", ".git" }
local function python_path(root)
  if vim.env.VIRTUAL_ENV then return vim.env.VIRTUAL_ENV .. "/bin/python" end
  root = root or vim.fs.root(0, PY_ROOT_MARKERS) or vim.fn.getcwd()
  for _, venv in ipairs({ ".venv", "venv" }) do
    local py = root .. "/" .. venv .. "/bin/python"
    if vim.fn.executable(py) == 1 then return py end
  end
  return "python3"
end

---------------------------------------------------------------------------
-- Build / run / test runner (F5-F8)
---------------------------------------------------------------------------
local function zig_project(root)
  return root, {
    build = { "zig", "build", "-Doptimize=ReleaseFast" },
    run   = { "zig", "build", "run", "-Doptimize=ReleaseFast" },
    test  = { "zig", "build", "test" },
    lint  = { "zig", "fmt", "--check", "." },
  }
end

local function cargo_project(root)
  return root, {
    build = { "cargo", "build", "--release" },
    run   = { "cargo", "run", "--release" },
    test  = { "cargo", "test" },
    lint  = { "cargo", "clippy" },
  }
end

-- Returns: working directory, table of commands
local function detect_tasks()
  local file = vim.api.nvim_buf_get_name(0)
  local dir = vim.fs.dirname(file)
  local ft = vim.bo.filetype

  if ft == "python" then
    local root = vim.fs.root(0, PY_ROOT_MARKERS) or dir
    local py = python_path(root)                    -- project venv if there is one
    return root, {
      build = { py, file },
      run   = { py, file },
      test  = { py, "-m", "pytest" },
      lint  = { "ruff", "check", "." },
      interactive_build = true,
    }
  end

  if ft == "zig" then
    local root = vim.fs.root(0, "build.zig")
    if root then return zig_project(root) end
    return dir, {                                   -- lone .zig file, no build.zig
      build = { "zig", "build-exe", file, "-O", "ReleaseFast" },
      run   = { "zig", "run", file, "-O", "ReleaseFast" },
      test  = { "zig", "test", file },
      lint  = { "zig", "ast-check", file },
    }
  end

  -- Rust files, Cargo.toml, or anything else inside a project
  local root = vim.fs.root(0, "Cargo.toml")
  if root then return cargo_project(root) end
  root = vim.fs.root(0, "build.zig")
  if root then return zig_project(root) end
  return nil
end

local runner_buf

local function run_task(kind)
  vim.cmd("silent! wall")
  local root, tasks = detect_tasks()
  if not root then
    vim.notify("No Rust/Zig/Python project found for this file", vim.log.levels.WARN)
    return
  end

  -- close the previous output window so they don't pile up
  if runner_buf and vim.api.nvim_buf_is_valid(runner_buf) then
    vim.api.nvim_buf_delete(runner_buf, { force = true })
  end

  local code_win = vim.api.nvim_get_current_win()
  vim.cmd("botright 15new")
  runner_buf = vim.api.nvim_get_current_buf()
  vim.fn.jobstart(tasks[kind], { cwd = root, term = true })
  vim.bo[runner_buf].bufhidden = "wipe"
  map("n", "q", "<cmd>bd!<CR>", { buffer = runner_buf, desc = "Close output" })

  -- programs that might read input keep focus in the terminal
  if kind == "run" or (kind == "build" and tasks.interactive_build) then
    vim.cmd("startinsert")
  else
    vim.api.nvim_set_current_win(code_win)
  end
end

map("n", "<F5>", function() run_task("build") end, { desc = "Build (release)" })
map("n", "<F6>", function() run_task("run") end, { desc = "Run (release)" })
map("n", "<F7>", function() run_task("test") end, { desc = "Test" })
map("n", "<F8>", function() run_task("lint") end, { desc = "Lint" })

---------------------------------------------------------------------------
-- Plugin manager (lazy.nvim, installs itself on first launch)
---------------------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local plugins = {
  -- Colorscheme
  {
    "slugbyte/lackluster.nvim", -- monochrome / greyscale theme
    lazy = false,
    priority = 1000,
    config = function()
      require("lackluster").setup({
        -- transparent: let Ghostty's translucent, blurred background show through
        tweak_background = { normal = "none", telescope = "none" },
      })
      vim.cmd.colorscheme("lackluster-night")

      -- "oxide": rust palette on top of the greyscale base (same colours as the desktop).
      -- Warm metals for the language itself, cooler oxides for types/lifetimes so
      -- Rust code stays easy to scan. One hue per kind of thing.
      local c = {
        rust    = "#e8732a", -- keywords (fn, let, match, impl), UI accent
        orange  = "#f2913d", -- self, builtins
        gold    = "#f7c862", -- functions / methods
        amber   = "#f5ad42", -- warnings, current search
        ember   = "#f2603f", -- macros (println!, vec!)
        copper  = "#c98a5e", -- attributes #[derive], escapes
        olive   = "#b5bd68", -- strings
        patina  = "#78bfa8", -- types, structs, enums, traits
        steel   = "#8fb2c9", -- lifetimes, modules / crates
        rose    = "#d690ad", -- numbers, booleans, constants, enum variants
        sand    = "#d4bfa4", -- parameters, fields
        text    = "#ecdfcc", -- variables
        ash     = "#b39b84", -- operators
        dust    = "#8a7563", -- punctuation
        rustbrown = "#7d6656", -- comments
        red     = "#e0463a", -- errors
      }
      local set = function(group, opts) vim.api.nvim_set_hl(0, group, opts) end
      for group, opts in pairs({
        Normal = { fg = c.text },
        Keyword = { fg = c.rust, bold = true }, Statement = { fg = c.rust, bold = true },
        Conditional = { fg = c.rust, bold = true }, Repeat = { fg = c.rust, bold = true },
        Exception = { fg = c.rust, bold = true }, StorageClass = { fg = c.rust },
        ["@keyword"] = { fg = c.rust, bold = true }, ["@keyword.return"] = { fg = c.rust, bold = true },
        ["@keyword.function"] = { fg = c.rust, bold = true }, ["@keyword.import"] = { fg = c.rust },
        ["@keyword.operator"] = { fg = c.rust }, ["@keyword.modifier"] = { fg = c.rust },
        ["@keyword.repeat"] = { fg = c.rust, bold = true }, ["@keyword.conditional"] = { fg = c.rust, bold = true },
        ["@keyword.exception"] = { fg = c.rust, bold = true }, ["@keyword.type"] = { fg = c.rust, bold = true },
        String = { fg = c.olive }, ["@string"] = { fg = c.olive },
        Character = { fg = c.olive }, ["@character"] = { fg = c.olive },
        ["@string.escape"] = { fg = c.copper, bold = true }, ["@string.special"] = { fg = c.copper },
        ["@string.regexp"] = { fg = c.copper },
        Function = { fg = c.gold, bold = true }, ["@function"] = { fg = c.gold, bold = true },
        ["@function.call"] = { fg = c.gold }, ["@function.method"] = { fg = c.gold, bold = true },
        ["@function.method.call"] = { fg = c.gold }, ["@constructor"] = { fg = c.patina },
        ["@function.builtin"] = { fg = c.orange }, ["@function.macro"] = { fg = c.ember, bold = true },
        Macro = { fg = c.ember, bold = true }, PreProc = { fg = c.copper },
        Type = { fg = c.patina }, ["@type"] = { fg = c.patina }, ["@type.builtin"] = { fg = c.patina, italic = true },
        ["@type.definition"] = { fg = c.patina, bold = true },
        Number = { fg = c.rose }, Float = { fg = c.rose }, ["@number"] = { fg = c.rose },
        ["@number.float"] = { fg = c.rose },
        Boolean = { fg = c.rose }, ["@boolean"] = { fg = c.rose },
        Constant = { fg = c.rose }, ["@constant"] = { fg = c.rose },
        ["@constant.builtin"] = { fg = c.rose, italic = true },
        ["@variable"] = { fg = c.text }, ["@variable.builtin"] = { fg = c.orange, italic = true }, -- self
        ["@variable.parameter"] = { fg = c.sand }, ["@variable.member"] = { fg = c.sand },
        ["@property"] = { fg = c.sand }, ["@field"] = { fg = c.sand },
        ["@module"] = { fg = c.steel }, ["@label"] = { fg = c.steel, italic = true }, -- 'a lifetimes
        ["@attribute"] = { fg = c.copper }, ["@attribute.builtin"] = { fg = c.copper },
        Operator = { fg = c.ash }, ["@operator"] = { fg = c.ash },
        ["@punctuation"] = { fg = c.dust }, ["@punctuation.bracket"] = { fg = c.dust },
        ["@punctuation.delimiter"] = { fg = c.dust }, ["@punctuation.special"] = { fg = c.copper },
        Comment = { fg = c.rustbrown, italic = true }, ["@comment"] = { fg = c.rustbrown, italic = true },
        ["@comment.documentation"] = { fg = "#9c8470", italic = true }, -- /// doc comments a bit brighter
        ["@comment.todo"] = { fg = "#0e0b09", bg = c.amber, bold = true },
        ["@comment.error"] = { fg = "#0e0b09", bg = c.red, bold = true },
        ["@comment.warning"] = { fg = "#0e0b09", bg = c.amber, bold = true },
        ["@comment.note"] = { fg = "#0e0b09", bg = c.steel, bold = true },
        Todo = { fg = "#0e0b09", bg = c.amber, bold = true },
        ["@markup.heading"] = { fg = c.rust, bold = true }, ["@markup.link"] = { fg = c.steel, underline = true },
        ["@markup.raw"] = { fg = c.olive }, ["@markup.strong"] = { bold = true },
        ["@markup.italic"] = { italic = true }, ["@markup.list"] = { fg = c.copper },

        -- rust-analyzer semantic tokens (these win over tree-sitter when the LSP is running)
        ["@lsp.type.lifetime"] = { fg = c.steel, italic = true },
        ["@lsp.type.macro"] = { fg = c.ember, bold = true },
        ["@lsp.type.derive"] = { fg = c.copper },
        ["@lsp.type.attribute"] = { fg = c.copper },
        ["@lsp.type.decorator"] = { fg = c.copper },
        ["@lsp.type.interface"] = { fg = c.patina, italic = true },         -- traits
        ["@lsp.type.struct"] = { fg = c.patina },
        ["@lsp.type.enum"] = { fg = c.patina },
        ["@lsp.type.enumMember"] = { fg = c.rose },                         -- Some, None, Ok, Err
        ["@lsp.type.typeParameter"] = { fg = c.patina, italic = true },     -- <T>
        ["@lsp.type.typeAlias"] = { fg = c.patina },
        ["@lsp.type.builtinType"] = { fg = c.patina, italic = true },       -- u32, str
        ["@lsp.type.selfKeyword"] = { fg = c.orange, italic = true },
        ["@lsp.type.selfTypeKeyword"] = { fg = c.patina, italic = true },   -- Self
        ["@lsp.type.namespace"] = { fg = c.steel },
        ["@lsp.type.crateRoot"] = { fg = c.steel, italic = true },
        ["@lsp.type.parameter"] = { fg = c.sand },
        ["@lsp.type.property"] = { fg = c.sand },
        ["@lsp.type.const"] = { fg = c.rose },
        ["@lsp.type.static"] = { fg = c.rose, italic = true },
        ["@lsp.type.formatSpecifier"] = { fg = c.copper, bold = true },     -- {} {:?} inside format!
        ["@lsp.type.escapeSequence"] = { fg = c.copper, bold = true },
        ["@lsp.type.unresolvedReference"] = { undercurl = true, sp = c.red },
        ["@lsp.mod.mutable"] = { underline = true },                        -- let mut x: x is underlined
        ["@lsp.mod.unsafe"] = { fg = c.red, bold = true },                  -- unsafe fn / unsafe ops
        ["@lsp.typemod.keyword.unsafe"] = { fg = c.red, bold = true },
        ["@lsp.mod.consuming"] = { italic = true },                         -- self moved into the call
        ["@lsp.typemod.function.unsafe"] = { fg = c.red, bold = true },
        ["@lsp.typemod.method.unsafe"] = { fg = c.red, bold = true },

        -- UI
        CursorLineNr = { fg = c.rust, bold = true }, LineNr = { fg = "#4e3f33" },
        CursorLine = { bg = "#1a1410" }, ColorColumn = { bg = "#1a1410" },
        -- selection: deep rust background, clearly visible against the dark editor
        Visual = { bg = "#6b3415" }, VisualNOS = { bg = "#6b3415" },
        Search = { fg = "#0e0b09", bg = c.gold }, IncSearch = { fg = "#0e0b09", bg = c.rust, bold = true },
        CurSearch = { fg = "#0e0b09", bg = c.rust, bold = true }, Substitute = { fg = "#0e0b09", bg = c.ember },
        MatchParen = { fg = c.amber, bg = "#3a2a1e", bold = true },
        Directory = { fg = c.rust }, Title = { fg = c.rust, bold = true },
        Pmenu = { fg = c.text, bg = "#1a1410" }, PmenuSel = { fg = "#0e0b09", bg = c.rust, bold = true },
        PmenuSbar = { bg = "#2a2019" }, PmenuThumb = { bg = c.rust },
        FloatBorder = { fg = c.rust }, FloatTitle = { fg = c.rust, bold = true },
        WinSeparator = { fg = "#3a2c22" }, NonText = { fg = "#4e3f33" }, Whitespace = { fg = "#3a2c22" },
        Cursor = { fg = "#0e0b09", bg = c.rust },
        StatusLine = { fg = c.sand }, StatusLineNC = { fg = c.dust },
        WildMenu = { fg = "#0e0b09", bg = c.rust },
        TelescopeSelection = { fg = c.text, bg = "#4a2610", bold = true },
        TelescopeSelectionCaret = { fg = c.rust, bg = "#4a2610", bold = true },
        TelescopeMatching = { fg = c.amber, bold = true },
        TelescopeBorder = { fg = c.rust }, TelescopePromptBorder = { fg = c.rust },
        TelescopePromptPrefix = { fg = c.rust }, TelescopeTitle = { fg = c.rust, bold = true },
        BlinkCmpMenuSelection = { fg = "#0e0b09", bg = c.rust, bold = true },
        BlinkCmpLabelMatch = { fg = c.amber, bold = true },
        BlinkCmpMenuBorder = { fg = c.rust }, BlinkCmpDocBorder = { fg = c.rust },
        WhichKey = { fg = c.rust }, WhichKeyGroup = { fg = c.patina }, WhichKeyDesc = { fg = c.text },
        OilDir = { fg = c.rust, bold = true },
        FlashLabel = { fg = "#0e0b09", bg = c.ember, bold = true },
        FlashMatch = { fg = c.amber }, FlashCurrent = { fg = c.gold, bold = true },
        FlashBackdrop = { fg = "#5a4838" },
        TreesitterContext = { bg = "#1a1410" }, TreesitterContextBottom = { underline = true, sp = "#3a2c22" },
        SnacksIndent = { fg = "#2a2019" }, SnacksIndentScope = { fg = "#5a4030" },
        SnacksPickerDir = { fg = c.dust }, SnacksPickerTree = { fg = "#3a2c22" },
        SnacksPickerMatch = { fg = c.amber, bold = true },
        SnacksPickerListCursorLine = { bg = "#4a2610" },
        DapUIScope = { fg = c.rust }, DapUIType = { fg = c.patina },
        LspInlayHint = { fg = "#7d6656", bg = "#16110d", italic = true },
        LspReferenceText = { bg = "#2e2219" }, LspReferenceRead = { bg = "#2e2219" },
        LspReferenceWrite = { bg = "#3d2a1c", underline = true },
        -- Diagnostics / git
        DiagnosticError = { fg = c.red }, DiagnosticWarn = { fg = c.amber },
        DiagnosticInfo = { fg = c.steel }, DiagnosticHint = { fg = c.patina },
        DiagnosticOk = { fg = c.olive },
        DiagnosticUnderlineError = { undercurl = true, sp = c.red },
        DiagnosticUnderlineWarn = { undercurl = true, sp = c.amber },
        DiagnosticUnderlineInfo = { undercurl = true, sp = c.steel },
        DiagnosticUnderlineHint = { undercurl = true, sp = c.patina },
        DiagnosticVirtualTextError = { fg = c.red, bg = "#2a1310" },
        DiagnosticVirtualTextWarn = { fg = c.amber, bg = "#2a1f10" },
        DiagnosticVirtualTextInfo = { fg = c.steel, bg = "#121a20" },
        DiagnosticVirtualTextHint = { fg = c.patina, bg = "#10201b" },
        DiffAdd = { fg = c.olive }, Added = { fg = c.olive }, GitSignsAdd = { fg = c.olive },
        DiffChange = { fg = c.amber }, Changed = { fg = c.amber }, GitSignsChange = { fg = c.amber },
        DiffDelete = { fg = c.red }, Removed = { fg = c.red }, GitSignsDelete = { fg = c.red },
        -- crates.nvim (Cargo.toml)
        CratesNvimVersion = { fg = c.rustbrown }, CratesNvimUpgrade = { fg = c.amber },
        CratesNvimError = { fg = c.red }, CratesNvimLoading = { fg = c.dust },
      }) do set(group, opts) end

      -- transparency: clear the backgrounds that would otherwise paint solid black
      -- (the completion popup keeps its background so it stays readable over code)
      for _, group in ipairs({
        "Normal", "NormalNC", "NormalFloat", "FloatBorder", "FloatTitle", "SignColumn",
        "LineNr", "CursorLineNr", "FoldColumn", "EndOfBuffer", "WinSeparator", "StatusLine",
        "StatusLineNC", "TabLine", "TabLineFill", "MsgArea",
        "TelescopeNormal", "TelescopeBorder", "TelescopePromptNormal", "TelescopePromptBorder",
        "TelescopeResultsNormal", "TelescopePreviewNormal", "WhichKeyNormal", "WhichKeyBorder",
        "GitSignsAdd", "GitSignsChange", "GitSignsDelete", "DiagnosticSignError",
        "DiagnosticSignWarn", "DiagnosticSignInfo", "DiagnosticSignHint",
      }) do
        local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
        hl.bg = nil
        hl.ctermbg = nil
        vim.api.nvim_set_hl(0, group, hl)
      end
    end,
  },

  -- Statusline
  { "nvim-lualine/lualine.nvim", opts = function()
    -- oxide colours: mode block changes colour per mode, middle stays transparent
    local bg, fg, dim = "#1a1410", "#ecdfcc", "#8a7563"
    local function mode(col)
      return {
        a = { fg = "#0e0b09", bg = col, gui = "bold" },
        b = { fg = col, bg = bg },
        c = { fg = fg, bg = "NONE" },
      }
    end
    local theme = {
      normal   = mode("#e8732a"),  -- rust
      insert   = mode("#b5bd68"),  -- olive
      visual   = mode("#f7c862"),  -- gold
      replace  = mode("#e0463a"),  -- red
      command  = mode("#78bfa8"),  -- patina
      terminal = mode("#8fb2c9"),  -- steel
      inactive = { a = { fg = dim, bg = bg }, b = { fg = dim, bg = bg }, c = { fg = dim, bg = "NONE" } },
    }
    return {
      options = { theme = theme, globalstatus = true,
                  section_separators = "", component_separators = "│" },
      sections = {
        lualine_c = { { "filename", path = 1 } },   -- path relative to the project
        lualine_x = { "diagnostics", "filetype" },
      },
      -- top bar: open buffers (Shift+h / Shift+l to switch)
      tabline = {
        lualine_a = { { "buffers", mode = 0, symbols = { alternate_file = "" },
                        buffers_color = { active = { fg = "#0e0b09", bg = "#e8732a", gui = "bold" },
                                          inactive = { fg = dim, bg = "NONE" } } } },
      },
    }
  end },

  -- Icons (your terminal has a Nerd Font)
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- Keybinding hints (press <space> and wait)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>b", group = "buffers" },
        { "<leader>c", group = "code" },
        { "<leader>d", group = "debug" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>t", group = "tests" },
        { "<leader>u", group = "toggles" },
        { "<leader>x", group = "diagnostics list" },
      },
    },
  },

  -- snacks: sidebar file tree, indent guides, buffer close that keeps the window layout
  {
    "folke/snacks.nvim",
    lazy = false,
    priority = 900,
    opts = {
      explorer = { replace_netrw = false },     -- oil stays the directory handler
      picker = {
        sources = {
          explorer = {
            hidden = true,                          -- show dotfiles
            layout = { layout = { position = "left", width = 32 } },
          },
        },
      },
      indent = { enabled = true, animate = { enabled = false } },
      bufdelete = { enabled = true },
    },
    keys = {
      { "<leader>e", function() Snacks.explorer() end, desc = "File tree (toggle)" },
      { "<leader>bd", function() Snacks.bufdelete() end, desc = "Close buffer" },
      { "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit (if installed)" },
    },
  },

  -- Harpoon: pin the 4-5 files you're working in, jump to them instantly
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function() require("harpoon"):setup() end,
    keys = {
      { "<leader>h", function() require("harpoon"):list():add() end, desc = "Harpoon: pin file" },
      { "<leader>H", function() local h = require("harpoon"); h.ui:toggle_quick_menu(h:list()) end, desc = "Harpoon: menu" },
      { "<leader>1", function() require("harpoon"):list():select(1) end, desc = "Harpoon file 1" },
      { "<leader>2", function() require("harpoon"):list():select(2) end, desc = "Harpoon file 2" },
      { "<leader>3", function() require("harpoon"):list():select(3) end, desc = "Harpoon file 3" },
      { "<leader>4", function() require("harpoon"):list():select(4) end, desc = "Harpoon file 4" },
      { "<leader>5", function() require("harpoon"):list():select(5) end, desc = "Harpoon file 5" },
    },
  },

  -- Jump anywhere on screen: press s, type 2 chars, press the label
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = { modes = { search = { enabled = false } } },
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash jump" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash select node" },
    },
  },

  -- Project-wide diagnostics / references / symbol outline list
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = {},
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", desc = "Project diagnostics" },
      { "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Buffer diagnostics" },
      { "<leader>cs", "<cmd>Trouble symbols toggle focus=false<CR>", desc = "Symbol outline" },
      { "<leader>cr", "<cmd>Trouble lsp toggle focus=false win.position=right<CR>", desc = "LSP refs/defs list" },
      { "<leader>xq", "<cmd>Trouble qflist toggle<CR>", desc = "Quickfix list" },
    },
  },

  -- TODO/FIXME/HACK highlighting + search
  {
    "folke/todo-comments.nvim",
    event = "BufReadPost",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = { signs = false },
    keys = {
      { "<leader>ft", "<cmd>TodoTelescope<CR>", desc = "Find TODOs" },
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next TODO" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Previous TODO" },
    },
  },

  -- Git signs in the gutter
  {
    "lewis6991/gitsigns.nvim",
    opts = {},
    keys = {
      { "]h", "<cmd>Gitsigns next_hunk<CR>", desc = "Next git hunk" },
      { "[h", "<cmd>Gitsigns prev_hunk<CR>", desc = "Previous git hunk" },
      { "<leader>gp", "<cmd>Gitsigns preview_hunk<CR>", desc = "Preview hunk" },
      { "<leader>gr", "<cmd>Gitsigns reset_hunk<CR>", desc = "Reset hunk" },
      { "<leader>gb", "<cmd>Gitsigns blame_line<CR>", desc = "Blame line" },
    },
  },

  -- Auto-close brackets/quotes
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

  -- File manager: "-" opens the file's folder as an editable buffer
  -- (rename/delete/create files by editing text, then :w). g? shows all oil keys.
  {
    "stevearc/oil.nvim",
    lazy = false,
    opts = {
      columns = { "icon" },
      view_options = { show_hidden = true },
      skip_confirm_for_simple_edits = true,
      watch_for_changes = true,
      keymaps = {
        -- oil's defaults steal <C-h>/<C-l>; give them back to window movement
        ["<C-h>"] = false,
        ["<C-l>"] = false,
        ["<C-x>"] = { "actions.select", opts = { horizontal = true }, desc = "Open in horizontal split" },
        ["<C-s>"] = { "actions.select", opts = { vertical = true }, desc = "Open in vertical split" },
        ["<C-r>"] = "actions.refresh",
        ["<BS>"] = "actions.parent",
        ["q"] = "actions.close",
      },
      float = { padding = 4, max_width = 100, border = "single" },
    },
    keys = {
      { "-", "<cmd>Oil<CR>", desc = "Open parent directory" },
      { "<leader>-", function() require("oil").toggle_float() end, desc = "Oil (floating)" },
    },
  },

  -- Fuzzy finder (fzf-native makes it much faster and gives fzf-style matching)
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    cmd = "Telescope",
    config = function()
      local actions = require("telescope.actions")
      require("telescope").setup({
        defaults = {
          path_display = { "filename_first" },     -- "main.py  src/app" instead of long paths
          layout_config = { prompt_position = "top" },
          sorting_strategy = "ascending",
          file_ignore_patterns = { "^.git/", "__pycache__/", "%.zig%-cache/", "zig%-out/", "^target/" },
          mappings = {
            i = {
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<Esc>"] = actions.close,
            },
          },
        },
        pickers = {
          find_files = { hidden = true },           -- dotfiles too (still respects .gitignore)
          buffers = { sort_mru = true, ignore_current_buffer = true,
                      mappings = { i = { ["<C-d>"] = actions.delete_buffer } } },
        },
      })
      pcall(require("telescope").load_extension, "fzf")
    end,
    keys = {
      { "<leader><leader>", function() require("telescope.builtin").find_files({ cwd = project_root() }) end, desc = "Find files (project)" },
      { "<leader>ff", function() require("telescope.builtin").find_files({ cwd = project_root() }) end, desc = "Find files (project)" },
      { "<leader>fF", "<cmd>Telescope find_files<CR>", desc = "Find files (cwd)" },
      { "<leader>fr", function() require("telescope.builtin").oldfiles({ only_cwd = false }) end, desc = "Recent files" },
      { "<leader>fg", function() require("telescope.builtin").live_grep({ cwd = project_root() }) end, desc = "Grep in project" },
      { "<leader>fw", function() require("telescope.builtin").grep_string({ cwd = project_root() }) end, desc = "Grep word under cursor", mode = { "n", "v" } },
      { "<leader>/", "<cmd>Telescope current_buffer_fuzzy_find<CR>", desc = "Search in this file" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
      { "<leader>,", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
      { "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Diagnostics" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", desc = "Symbols (file)" },
      { "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<CR>", desc = "Symbols (project)" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help" },
      { "<leader>fk", "<cmd>Telescope keymaps<CR>", desc = "Keymaps" },
      { "<leader>f.", "<cmd>Telescope resume<CR>", desc = "Resume last search" },
      { "<leader>fc", function() require("telescope.builtin").find_files({ cwd = vim.fn.stdpath("config"), follow = true }) end, desc = "Neovim config" },
      { "gR", "<cmd>Telescope lsp_references<CR>", desc = "References (picker)" },
    },
  },

  -- Syntax highlighting (needs tree-sitter-cli + a C compiler)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local langs = {
        "rust", "zig", "python", "toml", "lua", "vim", "vimdoc", "markdown", "markdown_inline",
        "json", "yaml", "bash", "regex", "query", "diff", "gitcommit", "c", "rst",
      }
      local ok, ts = pcall(require, "nvim-treesitter")
      if ok then ts.install(langs) end
      local fts = {}
      for _, lang in ipairs(langs) do
        vim.list_extend(fts, vim.treesitter.language.get_filetypes(lang))
      end
      vim.api.nvim_create_autocmd("FileType", {
        pattern = fts,
        callback = function()
          if pcall(vim.treesitter.start) then
            -- tree-sitter folds (zc / zo / za), all open by default
            vim.wo.foldmethod = "expr"
            vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
            vim.wo.foldlevel = 99
            -- tree-sitter indent (much better than regex indent for Python)
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- Show the current function/class at the top when you scroll past its header
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "BufReadPost",
    opts = { max_lines = 3 },
    keys = { { "<leader>uc", "<cmd>TSContext toggle<CR>", desc = "Toggle sticky context" } },
  },

  -- Formatting on save: ruff (sort imports + format), zig fmt, rustfmt
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    opts = {
      formatters_by_ft = {
        python = { "ruff_organize_imports", "ruff_format" },
        zig = { "zigfmt" },
        rust = { "rustfmt" },
      },
      default_format_opts = { lsp_format = "fallback" },
      format_on_save = function()
        if vim.g.disable_autoformat then return end
        return { timeout_ms = 2000 }
      end,
    },
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true }) end, desc = "Format", mode = { "n", "v" } },
      { "<leader>uf", function()
          vim.g.disable_autoformat = not vim.g.disable_autoformat
          vim.notify("Format on save " .. (vim.g.disable_autoformat and "off" or "on"))
        end, desc = "Toggle format on save" },
    },
  },

  -- Debugger: Python (debugpy), Zig + Rust (lldb-dap)
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
      { "theHamsta/nvim-dap-virtual-text", opts = {} },
      "mfussenegger/nvim-dap-python",
    },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()
      dap.listeners.after.event_initialized.dapui = function() dapui.open() end
      dap.listeners.before.event_terminated.dapui = function() dapui.close() end
      dap.listeners.before.event_exited.dapui = function() dapui.close() end

      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticWarn" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticOk", linehl = "CursorLine" })

      -- Python: debugpy runs from system python, your code runs in the project venv
      require("dap-python").setup("python3")
      require("dap-python").test_runner = "pytest"

      -- Zig / Rust: build in Debug mode first (zig build / cargo build), then pick the binary
      dap.adapters.lldb = { type = "executable", command = "lldb-dap", name = "lldb" }
      local function launch(bin_dir)
        return {
          {
            name = "Launch executable",
            type = "lldb",
            request = "launch",
            program = function()
              return vim.fn.input("Executable: ", project_root() .. "/" .. bin_dir, "file")
            end,
            cwd = "${workspaceFolder}",
            stopOnEntry = false,
            args = function()
              local a = vim.fn.input("Args: ")
              return a == "" and {} or vim.split(a, " +")
            end,
          },
        }
      end
      dap.configurations.zig = launch("zig-out/bin/")
      dap.configurations.rust = launch("target/debug/")
      dap.configurations.c = launch("")
    end,
    keys = {
      { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, desc = "Conditional breakpoint" },
      { "<leader>dc", function() require("dap").continue() end, desc = "Start / continue" },
      { "<leader>dn", function() require("dap").step_over() end, desc = "Step over (next)" },
      { "<leader>di", function() require("dap").step_into() end, desc = "Step into" },
      { "<leader>do", function() require("dap").step_out() end, desc = "Step out" },
      { "<leader>dr", function() require("dap").run_to_cursor() end, desc = "Run to cursor" },
      { "<leader>dl", function() require("dap").run_last() end, desc = "Run last" },
      { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
      { "<leader>du", function() require("dapui").toggle() end, desc = "Toggle debug UI" },
      { "<leader>de", function() require("dapui").eval() end, desc = "Evaluate expression", mode = { "n", "v" } },
    },
  },

  -- Test runner: run the test under the cursor, see pass/fail inline (pytest)
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-python",
    },
    config = function()
      require("neotest").setup({
        adapters = {
          require("neotest-python")({
            runner = "pytest",
            python = function() return python_path() end,
            dap = { justMyCode = false },
          }),
        },
      })
    end,
    keys = {
      { "<leader>tt", function() require("neotest").run.run() end, desc = "Run nearest test" },
      { "<leader>tf", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Run file's tests" },
      { "<leader>ta", function() require("neotest").run.run(project_root()) end, desc = "Run all tests" },
      { "<leader>tl", function() require("neotest").run.run_last() end, desc = "Re-run last test" },
      { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug nearest test" },
      { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Test summary" },
      { "<leader>to", function() require("neotest").output.open({ enter = true }) end, desc = "Test output" },
      { "<leader>tw", function() require("neotest").watch.toggle(vim.fn.expand("%")) end, desc = "Watch file" },
    },
  },

  -- Autocompletion
  {
    "saghen/blink.cmp",
    version = "1.*",
    opts = {
      keymap = { preset = "default" },   -- C-y accept, C-n/C-p select, C-space open
      completion = { documentation = { auto_show = true } },
      signature = { enabled = true },
      sources = { default = { "lsp", "path", "buffer" } },
    },
  },

  -- LSP server configs (the servers themselves come from pacman)
  { "neovim/nvim-lspconfig" },

  -- Cargo.toml helper: shows latest crate versions inline
  { "saecki/crates.nvim", event = "BufRead Cargo.toml", opts = {} },

}

-- extra plugins for this machine only (lua/local_plugins.lua, not in the repo)
local ok, extra = pcall(require, "local_plugins")
if ok and type(extra) == "table" then vim.list_extend(plugins, extra) end

require("lazy").setup(plugins, {
  checker = { enabled = false },
  change_detection = { notify = false },
})

---------------------------------------------------------------------------
-- LSP: rust-analyzer, zls, pyright, ruff
---------------------------------------------------------------------------
vim.lsp.config("rust_analyzer", {
  settings = {
    ["rust-analyzer"] = {
      check = { command = "clippy" },   -- clippy warnings while you type
      cargo = { allFeatures = true },
    },
  },
})
vim.lsp.config("pyright", {
  settings = {
    pyright = { disableOrganizeImports = true },   -- ruff does imports
    python = {
      analysis = {
        typeCheckingMode = "standard",
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        autoImportCompletions = true,
        diagnosticMode = "openFilesOnly",
      },
    },
  },
  -- point pyright at the project's venv so imports from installed packages resolve
  before_init = function(_, config)
    config.settings.python.pythonPath = python_path(config.root_dir)
  end,
})
vim.lsp.config("zls", {
  settings = {
    zls = {
      enable_build_on_save = true,                -- real compile errors on save, not just syntax
      semantic_tokens = "full",
      warn_style = true,                          -- naming-convention hints
      highlight_global_var_declarations = true,
      inlay_hints_hide_redundant_param_names = true,
      inlay_hints_hide_redundant_param_names_last_token = true,
    },
  },
})
vim.lsp.enable({ "rust_analyzer", "zls", "pyright", "ruff" })

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = "single" },
})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    -- let pyright handle hover in Python; ruff only lints/formats
    if client and client.name == "ruff" then
      client.server_capabilities.hoverProvider = false
    end

    local opts = function(desc) return { buffer = ev.buf, desc = desc } end
    -- Built-in 0.11 defaults also work: K hover, grn rename, gra code action, grr references
    map("n", "gd", vim.lsp.buf.definition, opts("Go to definition"))
    map("n", "<leader>rn", vim.lsp.buf.rename, opts("Rename"))
    map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts("Code action"))
    map("n", "gD", vim.lsp.buf.declaration, opts("Go to declaration"))
    map("n", "gy", vim.lsp.buf.type_definition, opts("Go to type definition"))
    map("n", "gI", vim.lsp.buf.implementation, opts("Go to implementation"))
    map("n", "<leader>cd", vim.diagnostic.open_float, opts("Show diagnostic"))
    map("n", "<leader>lf", function() require("conform").format() end, opts("Format"))
    map("n", "<leader>ih", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf }), { bufnr = ev.buf })
    end, opts("Toggle inlay hints"))

    vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
  end,
})

-- Format on save is handled by conform.nvim (see plugins); <leader>uf toggles it

-- Briefly highlight yanked text
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank() end,
})
