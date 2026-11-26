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
    return { options = { theme = theme, globalstatus = true,
                         section_separators = "", component_separators = "│" } }
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
