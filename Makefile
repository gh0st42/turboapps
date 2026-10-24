# turboapps: desktop applications written in tlua, one tlua design project
# to a folder under apps/. Each one is zipped into a .ztl bundle in dist/,
# which any GUI-built tlua runs on any platform: tlua dist/calculator.ztl
#
#   make                    every app, as dist/<app>.ztl
#   make calculator         one app
#   make run-editor         bundle it and run the bundle
#   make design-editor      open it in tlua's form designer
#   make test               the apps' tests, headless
#   make check              tests, and the layouts as the designer writes them
#   make layouts            rewrite the layouts and stubs as the designer would
#   make clean

# The tlua to build with: the one beside this folder if it has been built,
# else whatever is on PATH. Override with make TLUA=/path/to/tlua.
TLUA ?= $(firstword $(wildcard ../tlua/bin/tlua) tlua)

DIST := dist
APPS := $(notdir $(patsubst %/,%,$(dir $(wildcard apps/*/main.lua))))
ZTLS := $(APPS:%=$(DIST)/%.ztl)

.PHONY: all list test check layouts clean $(APPS)
all: $(ZTLS)

# A bundle is rebuilt when anything in its app's folder changes. tlua
# bundle zips the folder, leaving out dot files, with main.lua at the root.
.SECONDEXPANSION:
$(DIST)/%.ztl: apps/%/main.lua $$(shell find apps/$$* -type f ! -name '.*')
	@mkdir -p $(DIST)
	$(TLUA) bundle -o $@ apps/$*

$(APPS): %: $(DIST)/%.ztl

run-%: $(DIST)/%.ztl
	$(TLUA) $< $(ARGS)

design-%:
	$(TLUA) design apps/$*

list:
	@for a in $(APPS); do echo "$$a -> $(DIST)/$$a.ztl"; done

# Each app's tests run with its folder on the module path, as the app does.
test:
	@for a in $(APPS); do \
	  if [ -f tests/$${a}_test.lua ]; then \
	    $(TLUA) -p apps/$$a -p tests tests/$${a}_test.lua || exit 1; \
	  fi; \
	done
	@$(TLUA) -p apps/files -p tests tests/openwith_test.lua

check: test
	$(TLUA) tools/layouts.lua --check $(APPS:%=apps/%)

layouts:
	$(TLUA) tools/layouts.lua $(APPS:%=apps/%)

clean:
	rm -rf $(DIST)
