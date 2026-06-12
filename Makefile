# MCPC — macOS MCP client
# Run `make help` for targets.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
export MCPC_CONFIG ?= $(ROOT)/config.toml

BUILD_CONFIG ?= debug
SWIFT_BUILD := swift build -c $(BUILD_CONFIG)
BUILD_DIR := $(ROOT)/.build/$(BUILD_CONFIG)
MCPC_BIN := $(BUILD_DIR)/mcpc
MCPC_GUI_BIN := $(BUILD_DIR)/mcpc-gui

.PHONY: help build release clean test gui mcpc mcpc-gui \
	list-servers ping list-tools install

.DEFAULT_GOAL := help

help: ## Show available targets
	@printf "MCPC Makefile\n\n"
	@printf "Usage: make [target]\n\n"
	@printf "Targets:\n"
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-16s %s\n", $$1, $$2}'

build: ## Build all products (debug)
	$(SWIFT_BUILD)

release: ## Build all products (release)
	$(MAKE) build BUILD_CONFIG=release

mcpc: ## Build CLI only
	swift build -c $(BUILD_CONFIG) --product mcpc

mcpc-gui: ## Build GUI only
	swift build -c $(BUILD_CONFIG) --product mcpc-gui

clean: ## Remove build artifacts
	swift package clean
	rm -rf $(ROOT)/.build

test: mcpc ## Run integration tests against test-server
	MCPC_BIN=$(MCPC_BIN) $(ROOT)/scripts/test_swift_client.sh

gui: mcpc-gui ## Launch mcpc-gui
	exec $(MCPC_GUI_BIN)

list-servers: mcpc ## List servers from config.toml
	$(MCPC_BIN) list-servers

ping: mcpc ## Ping default server
	$(MCPC_BIN) ping

list-tools: mcpc ## List tools on default server
	$(MCPC_BIN) list-tools

install: release ## Install mcpc and mcpc-gui to $(PREFIX)/bin
	@install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 $(ROOT)/.build/release/mcpc $(DESTDIR)$(PREFIX)/bin/mcpc
	install -m 755 $(ROOT)/.build/release/mcpc-gui $(DESTDIR)$(PREFIX)/bin/mcpc-gui
	@printf "Installed to $(DESTDIR)$(PREFIX)/bin\n"
