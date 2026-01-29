---
targets:
  - claudecode
description: Translate README.md and example docs into multiple languages (ja, zh, fr, de)
---

# Translate Documentation

Translate the README.md and example documentation into multiple languages.

## Instructions

### 1. Translate README.md

1. Read the current README.md
2. Create translated versions for each language:
   - `README.ja.md` - Japanese (日本語)
   - `README.zh.md` - Chinese (中文)
   - `README.fr.md` - French (Français)
   - `README.de.md` - German (Deutsch)

### 2. Translate Example Documentation

1. Find all `en.md` files in the `example/` directory
2. For each `en.md` file, create translated versions in the same directory:
   - `ja.md` - Japanese (日本語)
   - `zh.md` - Chinese (中文)
   - `fr.md` - French (Français)
   - `de.md` - German (Deutsch)

### 3. Translation Guidelines

For each translation:
- Keep all code blocks unchanged
- Translate all text content naturally (not literal translation)
- Keep the same markdown structure
- Keep URLs and links unchanged
- Keep the language links at the top unchanged (for README only)
- Translate code comments if they exist in text sections (not in code blocks)

$ARGUMENTS
