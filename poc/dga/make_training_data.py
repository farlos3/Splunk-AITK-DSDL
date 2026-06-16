#!/usr/bin/env python3
"""Generate a labeled DGA-vs-legit training set for the DSDL POC.

Writes dga_training_domains.csv with columns: domain,is_dga
  is_dga = 0  -> benign / legitimate second-level domain
  is_dga = 1  -> algorithmically generated (malware-style) domain

This is a *teaching* dataset — a few hundred balanced rows, enough to train a
character-level model that clearly separates random-looking DGA strings from
pronounceable real domains. It is NOT a production blocklist.

Run:  python make_training_data.py   (re-generates the CSV deterministically)
"""
import csv
import random
import string

random.seed(1337)  # deterministic output so the committed CSV is reproducible

OUT = "dga_training_domains.csv"
TLDS = ["com", "net", "org", "info", "biz", "ru", "cn", "top", "xyz"]

# --- benign: real, pronounceable second-level domains ----------------------
LEGIT = """
google facebook youtube amazon wikipedia twitter instagram linkedin reddit netflix
microsoft apple yahoo bing office live outlook bingads paypal ebay walmart target
spotify dropbox github gitlab bitbucket stackoverflow medium quora wordpress blogger
cloudflare akamai fastly digitalocean heroku salesforce oracle adobe nvidia intel
samsung sony nokia huawei xiaomi lenovo dell cisco vmware redhat ubuntu debian
cnn bbc reuters bloomberg forbes nytimes guardian wsj espn nba nfl fifa olympics
booking airbnb expedia uber lyft doordash grubhub instacart shopify squarespace
wikimedia mozilla python djangoproject nodejs reactjs vuejs angular kubernetes docker
zoom slack notion figma canva trello asana atlassian jira confluence bitwarden
chase wellsfargo bankofamerica citibank hsbc barclays visa mastercard americanexpress
harvard stanford mit berkeley oxford cambridge yale princeton cornell columbia
nasa noaa cdc who europa gov whitehouse senate parliament un worldbank imf
""".split()

# dictionary words DGA families sometimes concatenate (matsnu/suppobox style)
WORDS = """
time year people way day man thing woman life child world school state family
student group country problem hand part place case week company system program
question work government number night point home water room mother area money
story fact month lot right study book eye job word business issue side kind head
""".split()


def legit_rows():
    rows = []
    for name in LEGIT:
        rows.append((f"{name}.{random.choice(['com','com','com','net','org','io'])}", 0))
    # a few legit-but-longer subdomained hosts to add realism
    for name in random.sample(LEGIT, 30):
        sub = random.choice(["www", "mail", "cdn", "api", "login", "secure"])
        rows.append((f"{sub}.{name}.com", 0))
    return rows


def dga_random(n):
    """conficker/cryptolocker style: random alphanumeric of length 8-20."""
    rows = []
    for _ in range(n):
        ln = random.randint(8, 20)
        s = "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(ln))
        rows.append((f"{s}.{random.choice(TLDS)}", 1))
    return rows


def dga_consonant_heavy(n):
    """gameover-zeus style: low-vowel, high-entropy letter soup."""
    cons = "bcdfghjklmnpqrstvwxz"
    rows = []
    for _ in range(n):
        ln = random.randint(10, 18)
        s = "".join(random.choice(cons if random.random() < 0.82 else "aeiou") for _ in range(ln))
        rows.append((f"{s}.{random.choice(TLDS)}", 1))
    return rows


def dga_hex(n):
    """necurs/locky style: hex-ish blobs."""
    rows = []
    for _ in range(n):
        ln = random.randint(12, 24)
        s = "".join(random.choice("0123456789abcdef") for _ in range(ln))
        rows.append((f"{s}.{random.choice(TLDS)}", 1))
    return rows


def dga_wordlist(n):
    """matsnu/suppobox style: 2-3 dictionary words mashed together (harder!)."""
    rows = []
    for _ in range(n):
        k = random.randint(2, 3)
        s = "".join(random.choice(WORDS) for _ in range(k))
        rows.append((f"{s}.{random.choice(TLDS)}", 1))
    return rows


def main():
    rows = []
    rows += legit_rows()
    n_legit = len(rows)
    # balance DGA count to roughly match legit, spread across families
    per = max(1, n_legit // 4)
    rows += dga_random(per)
    rows += dga_consonant_heavy(per)
    rows += dga_hex(per)
    rows += dga_wordlist(per)

    # de-dup + shuffle
    rows = list(dict.fromkeys(rows))
    random.shuffle(rows)

    with open(OUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["domain", "is_dga"])
        w.writerows(rows)

    n_dga = sum(r[1] for r in rows)
    print(f"wrote {OUT}: {len(rows)} rows ({n_legit} legit, {n_dga} dga)")


if __name__ == "__main__":
    main()
