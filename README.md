<p align="center">
  <img src=".github/fan.webp" alt="fan.koplugin" width="300">
</p>

###### GPT-6 models were used to assist in the creation, because I have troubles with Lua AND EVEN MORE SO WITH PYTHON. Sorry.

A Lua plugin for reading fanfiction in KOReader. Supports Ficbook, AO3 and `archiveofourown.gay`. No additional interpreter or server is required.

# [DOWNLOADS](https://github.com/fenny013/fan.koplugin/releases/latest)

## Features

- Chapter navigation and automatic next chapter.
- Offline reading, full-book and chapter-range EPUB downloads.
- Cached updates, images, notes and author styles.
- Download progress, connection diagnostics and cookie import.
- English and Russian interface, following KOReader's language.

## Installation

Extract `fan.koplugin-0.3.0.zip` into `koreader/plugins/`, then restart KOReader. The plugin file should be at `koreader/plugins/fan.koplugin/main.lua`.

Open **fan.koplugin → Open story URL**. Page discovery accepts a listing or author-page URL, not a story title.

## Build

Run `python tools/package.py` with Python 3.11+. Installation and source archives with SHA-256 checksums are written to `dist/`.

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY.md).
