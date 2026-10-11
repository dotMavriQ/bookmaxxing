# bookmaxxing

A "Sort by" order for KOReader's file browser.

- Unread books first, shortest to longest.
- Finished books at the back, alphabetically, A to Ö.

The idea is to get through a backlog by always having the shortest unread book on top.

## Install

1. Copy `2-bookmaxxing.lua` into `koreader/patches/`. Create the folder if it isn't there.
2. Restart KOReader.
3. In the file browser, open the menu, go to "Sort by" and pick **bookmaxxing**.

To remove it, delete the file and pick another order.

## How it counts pages

KOReader only knows how long a book is once you have opened it, and for EPUB and MOBI
that number changes with the font size. So the length is read from the file itself:

| Format | Measured as |
| --- | --- |
| PDF, DjVu | the real page count |
| MOBI, AZW, AZW3 | the text length stated in the file's header |
| EPUB | the size of the text files inside the archive |
| TXT, MD, FB2, HTML | the size of the file |

Text is turned into pages at 2300 bytes a page, which is roughly what Kindle page
numbers work out to. It is an estimate, good enough to put books in order.

The first time you open a folder there is a pause while the PDFs are counted. Results
are kept in `koreader/settings/bookmaxxing.lua` and a book is only measured again if
the file changes.

## What counts as read

A book is read when its status in KOReader is Finished. Long-press a book to set it.

## Alphabetical order

Finished books are sorted the Swedish way: a to z, then å, ä, ö.

## Tested on

KOReader v2026.07.1 on a Kindle Paperwhite (11th generation).
