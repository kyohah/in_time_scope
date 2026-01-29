---
targets:
  - claudecode
description: Translate README.md and sync docs for all languages (ja, zh, fr, de)
---

# Translate Documentation

Translate and sync documentation using mdbook-i18n-helpers (gettext/PO files).

## Instructions

### 1. Sync English Documentation

1. Read the current `README.md`
2. Copy content to `docs/src/index.md`:
   - Remove the language links line (`[English](README.md) | [日本語]...`)
   - Keep everything else

### 2. Generate POT and Update PO Files

1. Generate POT file from source:
   ```bash
   cd docs && MDBOOK_OUTPUT='{"xgettext": {}}' mdbook build -d po
   ```

2. Update each PO file with new strings:
   ```bash
   cd docs/po
   msgmerge --update ja.po messages.pot
   msgmerge --update zh.po messages.pot
   msgmerge --update de.po messages.pot
   msgmerge --update fr.po messages.pot
   ```

### 3. Translate PO Files

For each PO file (`docs/po/ja.po`, `docs/po/zh.po`, `docs/po/de.po`, `docs/po/fr.po`):

1. Find untranslated entries (where `msgstr ""` is empty)
2. Add translations for each `msgid`

Example PO entry:
```
msgid "InTimeScope"
msgstr "InTimeScope"

msgid "A Ruby gem that adds time-window scopes to ActiveRecord models."
msgstr "ActiveRecordモデルに時間ウィンドウスコープを追加するRuby gem。"
```

### 4. Translation Guidelines

For each translation:
- Keep all code blocks unchanged (they appear as-is in msgid)
- Translate text content naturally (not literal translation)
- Keep URLs and links unchanged
- For multi-line content, use `\n` for line breaks

### 5. Language Codes

- `ja` - Japanese (日本語)
- `zh` - Chinese (中文)
- `fr` - French (Français)
- `de` - German (Deutsch)

$ARGUMENTS
