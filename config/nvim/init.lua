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
    local root = vim.fs.root(0, { "pyproject.toml", "setup.py", "requirements.txt", ".venv", ".git" }) or dir
    local py = root .. "/.venv/bin/python"          -- use the project venv if there is one
    if vim.fn.executable(py) == 0 then py = "python3" end
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

      -- Iceland palette on top of the greyscale base (matches the desktop theme).
      -- One hue per kind of thing so code is easy to scan; moss stays the accent.
      local c = {
        moss    = "#b8d14e", -- keywords, UI accent
        amber   = "#e2b86b", -- strings
        lupine  = "#b4a0e0", -- numbers, booleans, constants
        sky     = "#89c4e1", -- functions
        aurora  = "#6cc5b0", -- types
        fjord   = "#7aa6c2", -- builtins, modules
        copper  = "#d99a6c", -- attributes, macros, escapes
        sand    = "#c8bfa8", -- parameters, fields
        snow    = "#e6e6e6", -- variables
        ash     = "#9a9a9a", -- operators
        basalt  = "#6b7268", -- comments
        lava    = "#e06c5f", -- errors
        sulfur  = "#e6c35c", -- warnings
        glacier = "#8fb8c4",
      }
      local set = function(group, opts) vim.api.nvim_set_hl(0, group, opts) end
      for group, opts in pairs({
        Keyword = { fg = c.moss, bold = true }, Statement = { fg = c.moss, bold = true },
        Conditional = { fg = c.moss, bold = true }, Repeat = { fg = c.moss, bold = true },
        Exception = { fg = c.moss, bold = true },
        ["@keyword"] = { fg = c.moss, bold = true }, ["@keyword.return"] = { fg = c.moss, bold = true },
        ["@keyword.function"] = { fg = c.moss, bold = true }, ["@keyword.import"] = { fg = c.moss },
        ["@keyword.operator"] = { fg = c.moss }, ["@keyword.modifier"] = { fg = c.moss },
        String = { fg = c.amber }, ["@string"] = { fg = c.amber },
        Character = { fg = c.amber }, ["@character"] = { fg = c.amber },
        ["@string.escape"] = { fg = c.copper }, ["@string.special"] = { fg = c.copper },
        ["@string.regexp"] = { fg = c.copper },
        Function = { fg = c.sky, bold = true }, ["@function"] = { fg = c.sky, bold = true },
        ["@function.call"] = { fg = c.sky }, ["@function.method"] = { fg = c.sky, bold = true },
        ["@function.method.call"] = { fg = c.sky }, ["@constructor"] = { fg = c.aurora },
        ["@function.builtin"] = { fg = c.fjord }, ["@function.macro"] = { fg = c.copper },
        Macro = { fg = c.copper }, PreProc = { fg = c.copper },
        Type = { fg = c.aurora }, ["@type"] = { fg = c.aurora }, ["@type.builtin"] = { fg = c.fjord },
        ["@type.definition"] = { fg = c.aurora },
        Number = { fg = c.lupine }, Float = { fg = c.lupine }, ["@number"] = { fg = c.lupine },
        ["@number.float"] = { fg = c.lupine },
        Boolean = { fg = c.lupine }, ["@boolean"] = { fg = c.lupine },
        Constant = { fg = c.lupine }, ["@constant"] = { fg = c.lupine },
        ["@constant.builtin"] = { fg = c.lupine, italic = true },
        ["@variable"] = { fg = c.snow }, ["@variable.builtin"] = { fg = c.fjord, italic = true },
        ["@variable.parameter"] = { fg = c.sand }, ["@variable.member"] = { fg = c.sand },
        ["@property"] = { fg = c.sand }, ["@field"] = { fg = c.sand },
        ["@module"] = { fg = c.fjord }, ["@label"] = { fg = c.copper },
        ["@attribute"] = { fg = c.copper },
        Operator = { fg = c.ash }, ["@operator"] = { fg = c.ash },
        ["@punctuation"] = { fg = "#7d7d7d" }, ["@punctuation.bracket"] = { fg = "#8a8a8a" },
        Comment = { fg = c.basalt, italic = true }, ["@comment"] = { fg = c.basalt, italic = true },
        ["@comment.todo"] = { fg = "#000000", bg = c.sulfur, bold = true },
        Todo = { fg = "#000000", bg = c.sulfur, bold = true },
        ["@markup.heading"] = { fg = c.moss, bold = true }, ["@markup.link"] = { fg = c.sky, underline = true },
        ["@markup.raw"] = { fg = c.amber }, ["@markup.strong"] = { bold = true },
        ["@markup.italic"] = { italic = true }, ["@markup.list"] = { fg = c.copper },
        -- UI
        CursorLineNr = { fg = c.moss, bold = true }, LineNr = { fg = "#3a4038" },
        Visual = { bg = "#3b4520" }, Search = { fg = "#000000", bg = c.moss },
        IncSearch = { fg = "#000000", bg = c.amber }, CurSearch = { fg = "#000000", bg = c.amber },
        MatchParen = { fg = c.moss, bold = true, underline = true },
        Directory = { fg = c.moss }, Title = { fg = c.moss, bold = true },
        PmenuSel = { fg = "#000000", bg = c.moss }, FloatBorder = { fg = c.basalt },
        WinSeparator = { fg = "#2a2f28" },
        -- Diagnostics / git
        DiagnosticError = { fg = c.lava }, DiagnosticWarn = { fg = c.sulfur },
        DiagnosticInfo = { fg = c.sky }, DiagnosticHint = { fg = c.aurora },
        DiagnosticOk = { fg = c.moss },
        DiffAdd = { fg = c.moss }, Added = { fg = c.moss }, GitSignsAdd = { fg = c.moss },
        DiffChange = { fg = c.amber }, Changed = { fg = c.amber }, GitSignsChange = { fg = c.amber },
        DiffDelete = { fg = c.lava }, Removed = { fg = c.lava }, GitSignsDelete = { fg = c.lava },
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
    -- middle of the statusline transparent, mode/branch blocks keep their colours
    local theme = require("lualine.themes.auto")
    for _, mode in pairs(theme) do
      if mode.c then mode.c.bg = "NONE" end
    end
    return { options = { theme = theme, globalstatus = true } }
  end },

  -- Keybinding hints (press <space> and wait)
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  -- Git signs in the gutter
  { "lewis6991/gitsigns.nvim", opts = {} },

  -- Auto-close brackets/quotes
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

  -- File explorer: press "-" to open the current directory as a buffer
  {
    "stevearc/oil.nvim",
    lazy = false,
    opts = { view_options = { show_hidden = true } },
    keys = { { "-", "<cmd>Oil<CR>", desc = "Open parent directory" } },
  },

  -- Fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Grep in project" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
      { "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Diagnostics" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<CR>", desc = "Symbols" },
    },
  },

  -- Syntax highlighting (needs tree-sitter-cli + a C compiler)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local langs = { "rust", "zig", "python", "toml", "lua", "vim", "vimdoc", "markdown" }
      local ok, ts = pcall(require, "nvim-treesitter")
      if ok then ts.install(langs) end
      vim.api.nvim_create_autocmd("FileType", {
        pattern = langs,
        callback = function() pcall(vim.treesitter.start) end,
      })
    end,
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
    python = { analysis = { typeCheckingMode = "standard" } },
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
    map("n", "<leader>e", vim.diagnostic.open_float, opts("Show diagnostic"))
    map("n", "<leader>lf", function() vim.lsp.buf.format() end, opts("Format"))
    map("n", "<leader>ih", function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf }), { bufnr = ev.buf })
    end, opts("Toggle inlay hints"))

    vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
  end,
})

-- Format on save: rustfmt (Rust), zig fmt via zls (Zig), ruff format (Python)
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.rs", "*.zig", "*.py" },
  callback = function()
    vim.lsp.buf.format({
      async = false,
      filter = function(c) return c.name ~= "pyright" end,
    })
  end,
})

-- Briefly highlight yanked text
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank() end,
})
