CXX := clang++
CXXFLAGS := -std=c++17 -Wall -Wextra -O2 -Iinclude
FRAMEWORKS := -framework Foundation -framework Cocoa -framework Carbon -framework CoreGraphics -framework ApplicationServices -framework IOKit

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

BUILDDIR := build
BIN := $(BUILDDIR)/kb-backlight
TEST_BIN := $(BUILDDIR)/test_suite

SRCS := src/keyboard_manager.mm \
        src/osd_notifier.mm \
        src/hotkey_manager.mm \
        src/config.cpp \
        src/daemon_manager.cpp

MAIN_SRC := src/main.mm
TEST_SRC := tests/test_suite.cpp

OBJS := $(SRCS:src/%.cpp=$(BUILDDIR)/%.o)
OBJS := $(OBJS:src/%.mm=$(BUILDDIR)/%.o)

.PHONY: all clean test install uninstall

all: $(BIN)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/%.o: src/%.cpp | $(BUILDDIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILDDIR)/%.o: src/%.mm | $(BUILDDIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BIN): $(OBJS) $(MAIN_SRC) | $(BUILDDIR)
	$(CXX) $(CXXFLAGS) $(FRAMEWORKS) $(OBJS) $(MAIN_SRC) -o $@

$(TEST_BIN): $(OBJS) $(TEST_SRC) | $(BUILDDIR)
	$(CXX) $(CXXFLAGS) $(FRAMEWORKS) $(OBJS) $(TEST_SRC) -o $@

test: $(TEST_BIN)
	./$(TEST_BIN)

install: $(BIN)
	mkdir -p $(BINDIR)
	cp -f $(BIN) $(BINDIR)/kb-backlight
	chmod 755 $(BINDIR)/kb-backlight
	@echo "Installed kb-backlight to $(BINDIR)/kb-backlight"
	@echo "Run 'kb-backlight --install' to enable background launchd daemon."

uninstall:
	-$(BINDIR)/kb-backlight --uninstall 2>/dev/null || true
	rm -f $(BINDIR)/kb-backlight
	@echo "Uninstalled kb-backlight."

clean:
	rm -rf $(BUILDDIR)
