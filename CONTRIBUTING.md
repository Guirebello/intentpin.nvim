# Contributing

Thanks for helping improve IntentPin.nvim.

## Development setup

Requirements:

- Neovim 0.11.2 or newer
- nui.nvim available through `INTENTPIN_NUI_PATH` or as a sibling checkout at `../neovim-good-extensions/nui.nvim`

Clone the repository, make the change, then run:

```bash
make test
```

Keep changes focused, update the README and `doc/intentpin.txt` when behavior changes, and add a regression test for bug fixes or user-facing features when practical.

## Bug reports

Include:

- Neovim version;
- plugin configuration;
- minimal reproduction steps;
- exact error output from `:messages`;
- relevant results from `:checkhealth intentpin`.

Please do not include private source code or the contents of stored notes unless they are safe to share.
