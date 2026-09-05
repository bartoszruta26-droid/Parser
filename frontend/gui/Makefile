# Makefile dla parser-gui-gtk
# Kompiluje natywną aplikację GTK3 frontend GUI

CC = gcc
CFLAGS = -Wall -Wextra -O2 $(shell pkg-config --cflags gtk+-3.0)
LDFLAGS = $(shell pkg-config --libs gtk+-3.0) -lpthread

TARGET = parser-gui-gtk
SRC = parser-gui-gtk.c

.PHONY: all clean install uninstall debug run

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

debug: CFLAGS += -g -DDEBUG
debug: $(TARGET)

clean:
	rm -f $(TARGET) *.o

install: $(TARGET)
	install -m 755 $(TARGET) /usr/local/bin/

uninstall:
	rm -f /usr/local/bin/$(TARGET)

run: $(TARGET)
	./$(TARGET)

help:
	@echo "parser-gui-gtk Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build parser-gui-gtk (default)"
	@echo "  debug    - Build with debug symbols and DEBUG flag"
	@echo "  clean    - Remove built files"
	@echo "  install  - Install to /usr/local/bin"
	@echo "  uninstall- Remove from /usr/local/bin"
	@echo "  run      - Build and run"
	@echo "  help     - Show this help"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Compile"
	@echo "  make debug        - Compile with debug info"
	@echo "  make clean        - Clean build artifacts"
	@echo "  sudo make install - Install system-wide"
	@echo "  make run          - Run after building"
	@echo ""
	@echo "Manual execution:"
	@echo "  ./parser-gui-gtk                     - Interactive mode"
	@echo "  ./parser-gui-gtk --once ping         - One-shot ping"
	@echo "  DAEMON_CONFIG=/path/to/conf ./parser-gui-gtk"
