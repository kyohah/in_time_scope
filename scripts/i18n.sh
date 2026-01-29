#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCS_DIR="$SCRIPT_DIR/../docs"
PO_DIR="$DOCS_DIR/po"

# Supported languages (expand as needed)
LANGUAGES="ja"
# LANGUAGES="ja zh de fr"  # Full language support

cd "$DOCS_DIR"

case "$1" in
  extract)
    echo "==> Extracting translatable strings to POT..."
    MDBOOK_OUTPUT='{"xgettext": {}}' mdbook build -d po
    echo "Generated: $PO_DIR/messages.pot"
    ;;

  init)
    lang="$2"
    if [ -z "$lang" ]; then
      echo "Usage: $0 init <language-code>"
      echo "Example: $0 init ja"
      exit 1
    fi
    echo "==> Initializing $lang.po..."
    cd "$PO_DIR"
    msginit -i messages.pot -l "$lang" -o "$lang.po" --no-translator
    echo "Created: $PO_DIR/$lang.po"
    ;;

  update)
    echo "==> Updating PO files from POT..."
    for lang in $LANGUAGES; do
      if [ -f "$PO_DIR/$lang.po" ]; then
        echo "Updating $lang.po..."
        msgmerge --update "$PO_DIR/$lang.po" "$PO_DIR/messages.pot"
      fi
    done
    echo "Done."
    ;;

  build)
    echo "==> Building all languages..."

    # English (default)
    echo "Building English..."
    mdbook build -d book/en

    # Other languages
    for lang in $LANGUAGES; do
      if [ -f "$PO_DIR/$lang.po" ]; then
        echo "Building $lang..."
        MDBOOK_BOOK__LANGUAGE=$lang mdbook build -d "book/$lang"
      fi
    done
    echo "Done. Output in docs/book/"
    ;;

  serve)
    lang="${2:-en}"
    echo "==> Serving $lang documentation..."
    if [ "$lang" = "en" ]; then
      mdbook serve -d book/en
    else
      MDBOOK_BOOK__LANGUAGE=$lang mdbook serve -d "book/$lang"
    fi
    ;;

  *)
    echo "InTimeScope i18n helper script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  extract       Generate/update messages.pot from source"
    echo "  init <lang>   Initialize a new language (e.g., init ja)"
    echo "  update        Update all .po files from .pot"
    echo "  build         Build documentation for all languages"
    echo "  serve [lang]  Serve documentation locally (default: en)"
    echo ""
    echo "Workflow:"
    echo "  1. $0 extract     # After changing source docs"
    echo "  2. $0 update      # Merge changes to .po files"
    echo "  3. Edit po/*.po   # Translate new/changed strings"
    echo "  4. $0 build       # Build all languages"
    echo ""
    echo "Prerequisites:"
    echo "  - cargo install mdbook mdbook-i18n-helpers"
    echo "  - brew install gettext (macOS) or apt install gettext (Ubuntu)"
    exit 1
    ;;
esac
