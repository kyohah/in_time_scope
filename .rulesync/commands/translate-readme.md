---
targets:
  - claudecode
description: Translate README.md and docs into multiple languages (ja, zh, fr, de)
---

# Translate Documentation

Translate the README.md and documentation into multiple languages.

## Instructions

### 1. Translate README.md

1. Read the current README.md
2. Create translated versions in `docs/` directory:
   - `docs/README.ja.md` - Japanese (日本語)
   - `docs/README.zh.md` - Chinese (中文)
   - `docs/README.fr.md` - French (Français)
   - `docs/README.de.md` - German (Deutsch)

### 2. Translate mdBook Documentation

1. Find all `.md` files in the `docs/en/` directory
2. For each file, create/update translated versions in `docs/ja/`:
   - `docs/ja/index.md` - Japanese version of index.md
   - `docs/ja/point-system.md` - Japanese version of point-system.md
   - `docs/ja/user-name-history.md` - Japanese version of user-name-history.md

### 3. Translation Guidelines

For each translation:
- Keep all code blocks unchanged
- Translate all text content naturally (not literal translation)
- Keep the same markdown structure
- Keep URLs and links unchanged
- Keep the language links at the top unchanged (for README only)
- Translate code comments if they exist in text sections (not in code blocks)
- Update SUMMARY.md for Japanese docs

$ARGUMENTS
