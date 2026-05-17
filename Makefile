# Makefile for the org-todo-letter-number-priorities Emacs Lisp package.
#
# Common targets:
#   make            - build everything (compile + info)
#   make compile    - byte-compile the package
#   make test       - run the ERT suite in batch Emacs
#   make info       - generate the .info manual
#   make html       - generate the .html manual
#   make install    - install the package and its info manual
#   make uninstall  - remove the installed files
#   make clean      - delete byte-compiled and info output
#   make help       - print this list

PACKAGE  = org-todo-letter-number-priorities
VERSION  = 0.2.0

EMACS    ?= emacs
MAKEINFO ?= makeinfo
INSTALL  ?= install
INSTALL_INFO ?= install-info

EMACSFLAGS = -Q --batch -L .

SOURCES  = $(PACKAGE).el
COMPILED = $(SOURCES:.el=.elc)
TESTS    = $(PACKAGE)-tests.el
TEXI     = $(PACKAGE).texi
INFO     = $(PACKAGE).info
HTML     = $(PACKAGE).html

# Install paths.  Override on the command line, for example:
#   make install PREFIX=$HOME/.local
PREFIX   ?= /usr/local
DATADIR  ?= $(PREFIX)/share
INFODIR  ?= $(DATADIR)/info
ELISPDIR ?= $(DATADIR)/emacs/site-lisp/$(PACKAGE)

.PHONY: all help compile test check info html install install-elisp install-info-files uninstall clean distclean

all: compile info

help:
	@echo "$(PACKAGE) $(VERSION)"
	@echo
	@echo "Targets:"
	@echo "  make compile     Byte-compile $(SOURCES)"
	@echo "  make test        Run the ERT test suite in batch Emacs"
	@echo "  make info        Build $(INFO) from $(TEXI)"
	@echo "  make html        Build $(HTML) from $(TEXI)"
	@echo "  make install     Install elisp to $(ELISPDIR) and info to $(INFODIR)"
	@echo "  make uninstall   Remove installed files"
	@echo "  make clean       Remove byte-compiled and info output"
	@echo
	@echo "Variables (override on the command line):"
	@echo "  EMACS=$(EMACS)"
	@echo "  PREFIX=$(PREFIX)"
	@echo "  ELISPDIR=$(ELISPDIR)"
	@echo "  INFODIR=$(INFODIR)"

# ---------------------------------------------------------------------------
# Byte-compile

compile: $(COMPILED)

%.elc: %.el
	$(EMACS) $(EMACSFLAGS) \
	    --eval "(setq byte-compile-error-on-warn t)" \
	    -f batch-byte-compile $<

# ---------------------------------------------------------------------------
# Test

test:
	$(EMACS) $(EMACSFLAGS) \
	    -l ert \
	    -l $(SOURCES) \
	    -l $(TESTS) \
	    -f ert-run-tests-batch-and-exit

check: test

# ---------------------------------------------------------------------------
# Info and HTML

info: $(INFO)

$(INFO): $(TEXI)
	$(MAKEINFO) --no-split $(TEXI) -o $(INFO)

html: $(HTML)

$(HTML): $(TEXI)
	$(MAKEINFO) --html --no-split $(TEXI) -o $(HTML)

# ---------------------------------------------------------------------------
# Install / uninstall

install: install-elisp install-info-files

install-elisp: compile
	$(INSTALL) -d "$(DESTDIR)$(ELISPDIR)"
	$(INSTALL) -m 0644 $(SOURCES) "$(DESTDIR)$(ELISPDIR)"
	$(INSTALL) -m 0644 $(COMPILED) "$(DESTDIR)$(ELISPDIR)"

install-info-files: info
	$(INSTALL) -d "$(DESTDIR)$(INFODIR)"
	$(INSTALL) -m 0644 $(INFO) "$(DESTDIR)$(INFODIR)"
	-$(INSTALL_INFO) --info-dir="$(DESTDIR)$(INFODIR)" \
	    "$(DESTDIR)$(INFODIR)/$(INFO)"

uninstall:
	-$(INSTALL_INFO) --remove --info-dir="$(DESTDIR)$(INFODIR)" "$(INFO)"
	rm -f "$(DESTDIR)$(INFODIR)/$(INFO)"
	rm -f "$(DESTDIR)$(ELISPDIR)/$(PACKAGE).el"
	rm -f "$(DESTDIR)$(ELISPDIR)/$(PACKAGE).elc"
	-rmdir "$(DESTDIR)$(ELISPDIR)" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Clean

clean:
	rm -f $(COMPILED) $(TESTS:.el=.elc) $(INFO) $(HTML)

distclean: clean
