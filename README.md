# IntentPin.nvim

Turn exact code selections into persistent, editable change requests for AI coding assistants.

IntentPin keeps notes outside your repository, follows selected code with extmarks, presents every note in a floating manager, and exports a compact prompt for Codex, Claude Code, ChatGPT, Copilot, or any other text-based assistant.

> [!NOTE]
> IntentPin.nvim is currently an alpha. The storage format is versioned, but may receive migrations before 1.0.
>
> IntentPin contains both hover renderers. `virtual_lines` is the default and never covers source code; `floating_window` is available as a compact alternative.

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
    event = { "BufReadPost", "BufNewFile" },
    cmd = "IntentPin",
    opts = {
      hover = {
        mode = "virtual_lines", -- or "floating_window"
      },
      editor = {
        spell = true,
        spelllang = "pt_br,en_us",
      },
      export = {
        instruction_language = "custom",
        custom_instruction = "Implemente as alterações descritas abaixo.",
      },
    },
    keys = {
      { "<leader>ia", "<cmd>IntentPin add<cr>", mode = "x", desc = "Add IntentPin" },
      { "<leader>ii", "<cmd>IntentPin open<cr>", desc = "IntentPin Notes" },
      { "<leader>ih", "<cmd>IntentPin hover<cr>", desc = "Hover IntentPin" },
      { "<leader>iH", "<cmd>IntentPin expand<cr>", desc = "Expand IntentPins in File" },
      { "<leader>is", "<cmd>IntentPin show<cr>", desc = "Show IntentPin at Cursor" },
      { "<leader>ie", "<cmd>IntentPin edit<cr>", desc = "Edit IntentPin at Cursor" },
      { "<leader>iy", "<cmd>IntentPin copy checked<cr>", desc = "Copy Checked IntentPins" },
      { "<leader>iY", "<cmd>IntentPin copy all-absolute<cr>", desc = "Copy All IntentPins (Absolute Paths)" },
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

`<Esc>` and `<C-c>` in the note editor only return to Normal mode. Close explicitly with `q` or `:q`.

Spellcheck in the note editor is disabled by default. Enable it with `editor.spell = true`; optionally set `editor.spelllang` to the languages Neovim should use. While the editor is open, native spell commands such as `]s`, `[s`, and `z=` remain available.

By default, the selected range gets only a gutter sign. `:IntentPin hover` temporarily highlights the exact range and shows its comment with the configured renderer. The comment disappears when the cursor moves, Insert mode starts, or the command is repeated.

`:IntentPin expand` toggles every note in the current file as persistent virtual lines. Unlike hover, expanded notes remain visible while the cursor moves or Insert mode starts; run the command again to collapse them. `:IntentPin expand show` and `:IntentPin expand hide` are also available for explicit control.

Blockwise visual selections are intentionally rejected for now because a rectangular selection cannot be represented safely by a single range.

## Commands

```text
:IntentPin add
:IntentPin open
:IntentPin show
:IntentPin edit
:IntentPin delete
:IntentPin hover
:IntentPin expand
:IntentPin expand show
:IntentPin expand hide
:IntentPin reanchor
:IntentPin inline show
:IntentPin inline hide
:IntentPin inline toggle
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

`copy all-absolute` ignores inclusion checkboxes, copies every note in the project, and emits full file paths. Every copy command uses the configured export instruction. To match the VSCode extension's custom-instruction behavior, set `export.instruction_language = "custom"` and write the opening prompt in `export.custom_instruction`; the file, selected-code (`|`), and note (`>`) sections keep their normal format.

## Hover modes

Both modes temporarily highlight the selected characters with `IntentPinActiveRange` and leave `K` untouched for LSP hover.

- `virtual_lines` renders a wrapped comment card after the selected range. It shifts screen rows without modifying the file and never covers source code.
- `floating_window` renders a compact, non-focusable popup near the cursor. It uses less vertical space but may cover part of the editor while open.

Choose the renderer with `hover.mode`, then use `<leader>ih` or `:IntentPin hover` while the cursor is inside a pinned range. Use `:IntentPin inline hide` when you also want to hide persistent gutter signs.

Expanded-file mode always uses virtual lines, regardless of `hover.mode`, so showing several notes at once never covers source code. Toggle it with `<leader>iH` or `:IntentPin expand`.

## Floating manager

| Key | Action |
| --- | --- |
| `<CR>` | Jump to the note's code |
| `<Space>` | Include or exclude the note from checked exports |
| `a` | Include every note in checked exports |
| `u` | Exclude every note from checked exports |
| `e` | Edit the note |
| `d` | Delete the note |
| `D` | Delete every note in the project |
| `y` | Copy the current note |
| `Y` | Copy checked notes with relative paths |
| `gY` | Copy checked notes with absolute paths |
| `A` | Copy every note with relative paths |
| `p` | Toggle the preview pane |
| `r` | Retry broken anchors in loaded files and show a result summary |
| `?` | Open the persistent key-help buffer |
| `q` / `<Esc>` | Close |

The manager uses a side-by-side layout on wide screens and a stacked layout on narrower screens. Key help opens as a focused, scrollable buffer and remains visible until `?`, `q`, or `<Esc>` closes it.

## Configuration

```lua
require("intentpin").setup({
  root_markers = { ".git" },
  -- root_dir = function(path) return ... end,
  context_lines = 2,
  inline = {
    enabled = true,
    sign = "󰆉",
    orphan_sign = "!",
    virtual_text = false,
    max_length = 60,
    highlight_range = false,
    priority = 120,
  },
  hover = {
    mode = "virtual_lines", -- virtual_lines or floating_window
    width = 72,
    max_height = 14, -- floating_window only
    border = "rounded", -- floating_window only
  },
  editor = {
    width = 0.62,
    height = 0.32,
    border = "rounded",
    spell = false,
    spelllang = nil, -- for example: "pt_br,en_us"
    diagnostics = false, -- markdownlint/LSP diagnostics in the note editor
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
Make the indicated changes and answer any questions. Change code only when necessary to fulfill a requested change.

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

The tests cover export formatting, JSON persistence, re-anchoring, visual selection capture, note creation, gutter-only rendering, both hover modes, editor mode changes, the NUI manager lifecycle, and command registration.
