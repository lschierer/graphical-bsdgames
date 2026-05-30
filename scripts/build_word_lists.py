#!/usr/bin/env python3
"""
Download Google Books Ngrams 1-gram files and produce word list assets
for the Graphical BSDGames Flutter app.

Outputs:
  app/assets/words/hangman_words.txt  -- ~3000 common words, 6-9 chars
  app/assets/words/boggle_dict.txt    -- validated dictionary, 3-15 chars

Usage:
  python3 scripts/build_word_lists.py [--dry-run] [--start-file N]

The script processes all 24 ngram files sequentially so only one
decompressed file is in memory at a time (~100-500 MB peak).
On subsequent runs it skips the download if output files already exist
unless --force is passed.
"""

import argparse
import gzip
import io
import os
import re
import sys
import urllib.request
from collections import defaultdict

# ── Configuration ─────────────────────────────────────────────────────────────

NGRAM_BASE = (
    "http://storage.googleapis.com/books/ngrams/books/20200217/eng/1-{n:05d}-of-00024.gz"
)
NUM_FILES = 24

ASSETS_DIR = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "words")
HANGMAN_OUT = os.path.join(ASSETS_DIR, "hangman_words.txt")
BOGGLE_OUT  = os.path.join(ASSETS_DIR, "boggle_dict.txt")

# Minimum total match-count across the corpus to be included in the boggle dict.
# Filters out OCR errors, hapax legomena, and typos.
BOGGLE_MIN_FREQ = 10_000

# Minimum frequency for hangman words (much higher — these should be familiar).
HANGMAN_MIN_FREQ = 500_000

# Word length ranges
BOGGLE_MIN_LEN  = 3
BOGGLE_MAX_LEN  = 15
HANGMAN_MIN_LEN = 6
HANGMAN_MAX_LEN = 9

# Maximum hangman word list size (sorted by frequency, take the top N)
HANGMAN_MAX_WORDS = 3000

# Regex: only plain lowercase a-z, no digits, hyphens, apostrophes, etc.
VALID_WORD = re.compile(r'^[a-z]+$')

# System word list used to cross-filter boggle candidates.
# The ngrams corpus contains non-English text, OCR artifacts, and lowercased
# proper nouns that clear the frequency threshold but are not English words.
# Intersecting with a system dictionary removes most of this noise.
SYSTEM_DICT = '/usr/share/dict/words'

# ── Download + stream one ngram file ──────────────────────────────────────────

def stream_file(url: str):
    """Yield (word, total_count) pairs from one gzipped ngram file.

    v3 format (one row per ngram, all years on the same line):
        ngram TAB year,match_count,volume_count TAB year,match_count,volume_count ...
    """
    print(f"  Downloading {url.split('/')[-1]} ...", flush=True)
    with urllib.request.urlopen(url) as resp:
        raw = resp.read()
    print(f"  Decompressing ({len(raw) // 1024 // 1024} MB compressed) ...", flush=True)
    with gzip.open(io.BytesIO(raw)) as gz:
        for line in gz:
            parts = line.decode("utf-8", errors="ignore").rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            word = parts[0]
            # Strip POS tag suffix (e.g. "running_VERB" -> "running")
            if "_" in word:
                word = word.split("_")[0]
            if not VALID_WORD.match(word):
                continue
            # Sum match_count across all year triplets (year,match_count,volume_count)
            total = 0
            for entry in parts[1:]:
                try:
                    _, count, _ = entry.split(",")
                    total += int(count)
                except (ValueError, AttributeError):
                    pass
            if total > 0:
                yield word, total


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true",
                        help="Overwrite existing output files")
    parser.add_argument("--start-file", type=int, default=15, metavar="N",
                        help="Resume from file N (0-based). Files 0-14 are uppercase/"
                             "digit entries; lowercase words start ~file 15.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Download and process but don't write output files")
    args = parser.parse_args()

    if not args.force and not args.dry_run:
        if os.path.exists(HANGMAN_OUT) and os.path.exists(BOGGLE_OUT):
            print("Output files already exist. Pass --force to regenerate.")
            return

    os.makedirs(ASSETS_DIR, exist_ok=True)

    # Accumulate frequencies across all files
    freq: defaultdict[str, int] = defaultdict(int)

    for n in range(args.start_file, NUM_FILES):
        url = NGRAM_BASE.format(n=n)
        print(f"\n[{n+1}/{NUM_FILES}] Processing {url.split('/')[-1]}")
        try:
            for word, count in stream_file(url):
                freq[word] += count
        except Exception as e:
            print(f"  ERROR: {e}", file=sys.stderr)
            print(f"  Skipping file {n}. Re-run with --start-file {n} to retry.")
            continue
        print(f"  Running total: {len(freq):,} unique words so far")

    print(f"\nTotal unique candidate words: {len(freq):,}")

    # ── Load reference English word list for cross-filtering ──────────────────
    ref_words: set[str] | None = None
    if os.path.exists(SYSTEM_DICT):
        ref_words = set()
        with open(SYSTEM_DICT) as f:
            for line in f:
                w = line.strip().lower()
                if VALID_WORD.match(w) and BOGGLE_MIN_LEN <= len(w) <= BOGGLE_MAX_LEN:
                    ref_words.add(w)
        print(f"Reference dict: {len(ref_words):,} words (from {SYSTEM_DICT})")
    else:
        print(f"Warning: {SYSTEM_DICT} not found; boggle dict will not be cross-filtered")

    # ── Build boggle dict ──────────────────────────────────────────────────────
    boggle_candidates = (
        w for w, c in freq.items()
        if c >= BOGGLE_MIN_FREQ and BOGGLE_MIN_LEN <= len(w) <= BOGGLE_MAX_LEN
    )
    if ref_words is not None:
        boggle_candidates = (w for w in boggle_candidates if w in ref_words)
    boggle_words = sorted(boggle_candidates, key=lambda w: freq[w], reverse=True)
    print(f"Boggle dict: {len(boggle_words):,} words (freq >= {BOGGLE_MIN_FREQ:,}, cross-filtered)")

    # ── Build hangman list ─────────────────────────────────────────────────────
    hangman_words = sorted(
        (w for w, c in freq.items()
         if c >= HANGMAN_MIN_FREQ and HANGMAN_MIN_LEN <= len(w) <= HANGMAN_MAX_LEN),
        key=lambda w: freq[w],
        reverse=True,
    )[:HANGMAN_MAX_WORDS]
    print(f"Hangman list: {len(hangman_words):,} words (freq >= {HANGMAN_MIN_FREQ:,})")

    # ── Verify distribution ────────────────────────────────────────────────────
    if hangman_words:
        e_second_last_only = [
            w for w in hangman_words if w[-2] == "e" and w.count("e") == 1
        ]
        pct = 100 * len(e_second_last_only) / len(hangman_words)
        print(f"Hangman 'e at 2nd-to-last only' pattern: {pct:.1f}% (was 25.6% before)")

    if args.dry_run:
        print("\nDry run — no files written.")
        return

    # Write boggle dict (sorted alphabetically for binary search if needed later)
    boggle_words_alpha = sorted(boggle_words)
    with open(BOGGLE_OUT, "w") as f:
        f.write("\n".join(boggle_words_alpha) + "\n")
    print(f"\nWrote {BOGGLE_OUT}")

    with open(HANGMAN_OUT, "w") as f:
        f.write("\n".join(hangman_words) + "\n")
    print(f"Wrote {HANGMAN_OUT}")


if __name__ == "__main__":
    main()
