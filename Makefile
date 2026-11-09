# Makefile for wetype-automute

CC = clang
CFLAGS = -framework Foundation -framework CoreAudio -O2
TARGET = wetype-automute
PREFIX = /usr/local/bin
PLIST_NAME = com.user.wetype.automute.plist
PLIST_DIR = $(HOME)/Library/LaunchAgents

all: $(TARGET)

$(TARGET): main.m
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -f $(TARGET)

install: $(TARGET)
	@mkdir -p $(HOME)/.local/bin
	@mkdir -p $(PLIST_DIR)
	@cp $(TARGET) $(HOME)/.local/bin/$(TARGET)
	@chmod +x $(HOME)/.local/bin/$(TARGET)
	@sed 's|TARGET_PATH|$(HOME)/.local/bin/$(TARGET)|g' $(PLIST_NAME).template > $(PLIST_DIR)/$(PLIST_NAME)
	@launchctl unload $(PLIST_DIR)/$(PLIST_NAME) 2>/dev/null || true
	@launchctl load $(PLIST_DIR)/$(PLIST_NAME)
	@echo "Installed and started service via launchd."

uninstall:
	@launchctl unload $(PLIST_DIR)/$(PLIST_NAME) 2>/dev/null || true
	@rm -f $(PLIST_DIR)/$(PLIST_NAME)
	@rm -f $(HOME)/.local/bin/$(TARGET)
	@echo "Uninstalled service."

.PHONY: all clean install uninstall
