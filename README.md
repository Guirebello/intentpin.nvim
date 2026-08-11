# IntentPin.nvim

Turn exact code selections into persistent, editable change requests for AI coding assistants.

IntentPin keeps notes outside your repository, follows selected code with extmarks, presents every note in a floating manager, and exports a compact prompt for Codex, Claude Code, ChatGPT, Copilot, or any other text-based assistant.

> [!NOTE]
> IntentPin.nvim is currently an alpha. The storage format is versioned, but may receive migrations before 1.0.

## Requirements

- Neovim 0.11.2 or newer
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
- A clipboard provider is recommended, but exports are also written to the unnamed register

## LazyVim installation

While developing locally, create `lua/plugins/intentpin.lua` in your LazyVim config:

```lua
return {
  {
    dir = "/home/guilherme/projects/intentpin.nvim/main",
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    opts = {},
    keys = {
      { "<leader>ia", "<cmd>IntentPin add<cr>", mode = "x", desc = "Add IntentPin" },
      { "<leader>ii", "<cmd>IntentPin open<cr>", desc = "IntentPin Notes" },
      { "<leader>is", "<cmd>IntentPin show<cr>", desc = "Show IntentPin at Cursor" },
      { "<leader>ie", "<cmd>IntentPin edit<cr>", desc = "Edit IntentPin at Cursor" },
      { "<leader>iy", "<cmd>IntentPin copy checked<cr>", desc = "Copy Checked IntentPins" },
      { "]i", "<cmd>IntentPin next<cr>", desc = "Next IntentPin" },
      { "[i", "<cmd>IntentPin prev<cr>", desc = "Previous IntentPin" },
    },
  },
}
```

After publishing the repository, replace `dir` with:

```lua
"Guirebello/intentpin.nvim"
```

## Workflow

1. Select a characterwise or linewise block of code.
2. Run `:IntentPin add` and write a multiline note.
3. Save with `<C-s>`.
4. Open `:IntentPin open` to review, include, edit, delete, navigate, and export notes.

The selected range gets an inline sign and a one-line summary. Both are configurable. Blockwise visual selections are intentionally rejected for now because a rectangular selection cannot be represented safely by a single range.

## Commands

```text
:IntentPin add
:IntentPin open
:IntentPin show
:IntentPin edit
:IntentPin delete
:IntentPin next
:IntentPin prev
:IntentPin clear
:IntentPin copy checked
:IntentPin copy checked-absolute
:IntentPin copy all
:IntentPin copy all-absolute
:IntentPin copy current
:IntentPin copy current-absolute
```

`show`, `edit`, `delete`, and `copy current` operate on the note under the cursor. When ranges overlap, IntentPin asks which note to use.

## Floating manager

| Key | Action |
| --- | --- |
| `<CR>` | Jump to the note's code |
| `<Space>` | Include or exclude the note from checked exports |
| `e` | Edit the note |
| `d` | Delete the note |
| `D` | Delete every note in the project |
| `y` | Copy the current note |
| `Y` | Copy checked notes with relative paths |
| `gY` | Copy checked notes with absolute paths |
| `A` | Copy every note with relative paths |
| `p` | Toggle the preview pane |
| `r` | Refresh and re-anchor loaded files |
| `?` | Show key help |
| `q` / `<Esc>` | Close |

The manager uses a side-by-side layout on wide screens and a stacked layout on narrower screens.

## Configuration

```lua
require("intentpin").setup({
  root_markers = { ".git" },
  -- root_dir = function(path) return ... end,
  context_lines = 2,
  inline = {
    enabled = true,
    sign = "󰆉",
    orphan_sign = "?",
    virtual_text = true,
    max_length = 60,
    highlight_range = true,
    priority = 120,
  },
  editor = {
    width = 0.62,
    height = 0.32,
    border = "rounded",
  },
  manager = {
    width = 0.88,
    height = 0.76,
    border = "rounded",
    preview = true,
  },
  export = {
    include_selected_text = true,
    instruction_language = "en", -- en, pt-BR, es, or custom
    custom_instruction = "",
  },
})
```

All highlight groups start with `IntentPin` and can be overridden by a colorscheme or user config.

## Storage and re-anchoring

IntentPin never creates metadata in your project. State is stored at:

```text
stdpath("state")/intentpin/<sha256-project-root>.json
```

Writes use a temporary file followed by an atomic rename. While a buffer is loaded, extmarks follow edits. When a file is reopened, IntentPin first checks the stored range, then searches for the original selected text and ranks matches using nearby context and distance. If no match exists, the note is preserved and marked with a warning instead of being silently discarded.

Run `:checkhealth intentpin` to verify Neovim, NUI, storage, and clipboard support.

## Export format

```text
Change the indicated code sections. Adjust related code only when necessary.

src/auth/login.ts:14-15
| const session = await getSession(token)
| return session ?? null
> Return a specific error when the token has expired.
```

## Development

Run the headless test suite:

```bash
make test
```

The tests cover export formatting, JSON persistence, re-anchoring, visual selection capture, note creation, the NUI manager lifecycle, and command registration.
