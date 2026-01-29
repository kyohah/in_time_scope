---
targets:
  - claudecode
description: Translate README.md and sync docs for all languages (ja, zh, fr, de)
---

# Translate Documentation

Translate and sync documentation for multiple languages.

## Instructions

### 1. Sync English Documentation

1. Read the current `README.md`
2. Copy content to `docs/src/index.md`:
   - Remove the language links line (`[English](README.md) | [日本語]...`)
   - Keep everything else

### 2. Translate to Other Languages

For each language directory (`docs/ja/`, `docs/zh/`, `docs/fr/`, `docs/de/`):

1. Translate `docs/src/index.md` to `docs/{lang}/index.md`
2. Translate `docs/src/point-system.md` to `docs/{lang}/point-system.md`
3. Translate `docs/src/user-name-history.md` to `docs/{lang}/user-name-history.md`
4. Update `docs/{lang}/SUMMARY.md` with translated titles

### 3. Translation Guidelines

For each translation:
- Keep all code blocks unchanged
- Translate all text content naturally (not literal translation)
- Keep the same markdown structure
- Keep URLs and links unchanged
- Do NOT include language links in docs files
- Translate headings and navigation text in SUMMARY.md

### 4. Language Codes

- `ja` - Japanese (日本語)
- `zh` - Chinese (中文)
- `fr` - French (Français)
- `de` - German (Deutsch)

$ARGUMENTS
