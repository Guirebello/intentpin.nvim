.PHONY: test

test:
	NVIM_LOG_FILE=/tmp/intentpin.nvim-test.log nvim --headless --noplugin -u tests/minimal_init.lua -i NONE -l tests/run.lua
