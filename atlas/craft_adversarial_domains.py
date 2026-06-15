#!/usr/bin/env python3
"""Craft adversarial DGA domains that try to EVADE the DGA detector.

MITRE ATLAS: AML.T0043 (Craft Adversarial Data) -> AML.T0015 (Evade ML Model).

Every domain written here is *malicious by intent* (is_dga=1) but is shaped to
look like benign traffic to a character-level model trained on "random letter
soup vs. pronounceable brand names" (see ../dga/make_training_data.py). The
point of the exercise is to measure the model's EVASION RATE: feed these to
`apply dga_model` and count how many come back is_dga_predicted=0.

Writes atlas_evasion_domains.csv with columns: domain,is_dga  (is_dga always 1)

Run:  python craft_adversarial_domains.py   (deterministic output)
"""
import csv
import os
import random

random.seed(2024)  # deterministic so the committed CSV is reproducible

# write next to this script, so it lands in atlas/ no matter the working dir
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "atlas_evasion_domains.csv")
BENIGN_TLDS = ["com", "com", "com", "net", "org", "io"]  # weighted toward .com

# Pronounceable syllables -> domains that "sound real" instead of random soup.
# A char-CNN keys on letter/transition statistics, so legit-looking phonotactics
# slip under the radar the way conficker-style strings never would.
ONSETS = ["b", "c", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s",
          "t", "v", "w", "br", "cl", "cr", "dr", "fl", "gr", "pl", "pr", "st", "tr"]
NUCLEI = ["a", "e", "i", "o", "u", "ai", "ea", "ee", "oa", "ou"]
CODAS = ["", "", "n", "r", "s", "l", "t", "ng", "nt", "rk", "st"]

# Real dictionary words a wordlist/CSP DGA (matsnu/suppobox style) concatenates.
# These overlap the *shape* of brand names, so they read as plausible products.
WORDS = """
cloud secure data swift bright north prime core link wave peak true blue
fast smart green stone river light north star sky port gate ridge field
""".split()

# Well-known brands to typo-squat (homoglyph / insertion / transposition).
BRANDS = ["google", "amazon", "microsoft", "paypal", "netflix", "spotify",
          "github", "dropbox", "cloudflare", "salesforce"]


def syllable(n):
    return "".join(random.choice(ONSETS) + random.choice(NUCLEI) + random.choice(CODAS)
                   for _ in range(n))


def pronounceable(count):
    """Letter-soup avoided: 2-3 syllable strings that read like a real brand."""
    out = []
    for _ in range(count):
        out.append(f"{syllable(random.randint(2, 3))}.{random.choice(BENIGN_TLDS)}")
    return out


def wordlist(count):
    """2-3 real words mashed together: high lexical plausibility, low entropy."""
    out = []
    for _ in range(count):
        k = random.randint(2, 3)
        out.append("".join(random.choice(WORDS) for _ in range(k)) + f".{random.choice(BENIGN_TLDS)}")
    return out


def typosquat(count):
    """Small edits on real brands: insertion, doubling, char swap, dash."""
    out = []
    for _ in range(count):
        b = random.choice(BRANDS)
        kind = random.randint(0, 3)
        if kind == 0:                              # insert a character
            i = random.randint(1, len(b) - 1)
            b = b[:i] + random.choice("aeiou") + b[i:]
        elif kind == 1:                            # double a character
            i = random.randint(0, len(b) - 1)
            b = b[:i] + b[i] + b[i:]
        elif kind == 2 and len(b) > 3:             # transpose two characters
            i = random.randint(0, len(b) - 2)
            b = b[:i] + b[i + 1] + b[i] + b[i + 2:]
        else:                                      # hyphenate
            i = random.randint(2, len(b) - 2)
            b = b[:i] + "-" + b[i:]
        out.append(f"{b}.{random.choice(BENIGN_TLDS)}")
    return out


def main():
    rows = []
    rows += [(d, 1) for d in pronounceable(40)]
    rows += [(d, 1) for d in wordlist(30)]
    rows += [(d, 1) for d in typosquat(30)]

    rows = list(dict.fromkeys(rows))   # de-dup, keep order
    random.shuffle(rows)

    with open(OUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["domain", "is_dga"])
        w.writerows(rows)

    print(f"wrote {os.path.basename(OUT)}: {len(rows)} adversarial domains (all true label is_dga=1)")
    print("next: load as a lookup, then  | inputlookup atlas_evasion_domains.csv | apply dga_model")
    print("evasion rate = share of rows that come back is_dga_predicted=0")


if __name__ == "__main__":
    main()
