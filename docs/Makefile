# Global variables
# You can set these variables from the command line.
POETRY        = poetry
SPHINXOPTS    = -j auto
SPHINXBUILD   = $(POETRY) run sphinx-build
PAPER         =
BUILDDIR      = _build
SOURCEDIR     = source

# Internal variables
PAPEROPT_a4     = -D latex_paper_size=a4
PAPEROPT_letter = -D latex_paper_size=letter
ALLSPHINXOPTS   = -d $(BUILDDIR)/doctrees $(PAPEROPT_$(PAPER)) $(SPHINXOPTS) $(SOURCEDIR)
TESTSPHINXOPTS  = $(ALLSPHINXOPTS) -W --keep-going

.PHONY: all
all: dirhtml

# Setup commands
.PHONY: setupenv
setupenv:
	pip install -q poetry

.PHONY: setup
setup:
	$(POETRY) install

.PHONY: update
update:
	$(POETRY) update

# Clean commands
.PHONY: pristine
pristine: clean
	git clean -dfX

.PHONY: clean
clean:
	rm -rf $(BUILDDIR)/*

# Generate output commands
.PHONY: dirhtml
dirhtml: setup
	$(SPHINXBUILD) -b dirhtml $(ALLSPHINXOPTS) $(BUILDDIR)/dirhtml
	@echo
	@echo "Build finished. The HTML pages are in $(BUILDDIR)/dirhtml."

.PHONY: singlehtml
singlehtml: setup
	$(SPHINXBUILD) -b singlehtml $(ALLSPHINXOPTS) $(BUILDDIR)/singlehtml
	@echo
	@echo "Build finished. The HTML page is in $(BUILDDIR)/singlehtml."

.PHONY: epub
epub: setup
	$(SPHINXBUILD) -b epub $(ALLSPHINXOPTS) $(BUILDDIR)/epub
	@echo
	@echo "Build finished. The epub file is in $(BUILDDIR)/epub."

.PHONY: epub3
epub3: setup
	$(SPHINXBUILD) -b epub3 $(ALLSPHINXOPTS) $(BUILDDIR)/epub3
	@echo
	@echo "Build finished. The epub3 file is in $(BUILDDIR)/epub3."

.PHONY: multiversion
multiversion: setup
	$(POETRY) run sphinx-multiversion $(SOURCEDIR) $(BUILDDIR)/dirhtml
	@echo
	@echo "Build finished. The HTML pages are in $(BUILDDIR)/dirhtml."

.PHONY: redirects
redirects: setup
	$(POETRY) run redirects-cli fromfile --yaml-file _utils/redirects.yaml --output-dir $(BUILDDIR)/dirhtml
	@echo
	@echo "Build finished. The HTML pages are in $(BUILDDIR)/dirhtml."

# Preview commands
.PHONY: preview
preview: setup
	$(POETRY) run sphinx-autobuild -b dirhtml $(ALLSPHINXOPTS) $(BUILDDIR)/dirhtml --port 5500

.PHONY: multiversionpreview
multiversionpreview: multiversion
	$(POETRY) run python -m http.server 5500 --directory $(BUILDDIR)/dirhtml

# Test commands
.PHONY: test
test: setup
	$(SPHINXBUILD) -b dirhtml $(TESTSPHINXOPTS) $(BUILDDIR)/dirhtml
	@echo
	@echo "Build finished. The HTML pages are in $(BUILDDIR)/dirhtml."

.PHONY: linkcheck
linkcheck: setup
	$(SPHINXBUILD) -b linkcheck $(SOURCEDIR) $(BUILDDIR)/linkcheck
