#!/usr/bin/env python3
"""Poison the DGA training set, then watch detection quality collapse.

MITRE ATLAS: AML.T0020 (Poison Training Data); retraining on it yields
AML.T0018 (Backdoor ML Model) / AML.T0031 (Erode ML Model Integrity).

This injects mislabeled rows into a copy of ../dga/dga_training_domains.csv:
algorithmically-generated (DGA) domains are labeled is_dga=0 ("benign"). Train
the model on the poisoned file instead of the clean one and the model learns
that letter-soup is fine -> it stops flagging the matching DGA family. A small
poison fraction is enough; that is what makes the attack realistic.

Writes dga_training_domains_poisoned.csv (same columns: domain,is_dga).

Run:  python poison_training_data.py [--rate 0.15] [--family random]
"""
import argparse
import csv
import os
import random
import string

random.seed(31337)

_HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(_HERE, "..", "dga", "dga_training_domains.csv")
OUT = os.path.join(_HERE, "dga_training_domains_poisoned.csv")  # land in atlas/ regardless of CWD
TLDS = ["com", "net", "org", "info", "biz", "ru", "cn", "top", "xyz"]


def dga_random():
    ln = random.randint(8, 20)
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(ln))


def dga_hex():
    ln = random.randint(12, 24)
    return "".join(random.choice("0123456789abcdef") for _ in range(ln))


def dga_consonant():
    cons = "bcdfghjklmnpqrstvwxz"
    ln = random.randint(10, 18)
    return "".join(random.choice(cons if random.random() < 0.82 else "aeiou") for _ in range(ln))


FAMILIES = {"random": dga_random, "hex": dga_hex, "consonant": dga_consonant}


def load(path):
    with open(path, newline="") as f:
        r = csv.reader(f)
        header = next(r)
        return header, [row for row in r if row]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rate", type=float, default=0.15,
                    help="poison rows as a fraction of the clean set (default 0.15)")
    ap.add_argument("--family", choices=FAMILIES, default="random",
                    help="which DGA family to mislabel as benign (default random)")
    args = ap.parse_args()

    header, rows = load(SRC)
    n_poison = max(1, int(len(rows) * args.rate))
    gen = FAMILIES[args.family]

    # mislabeled: real DGA strings tagged is_dga=0
    poison = list({(f"{gen()}.{random.choice(TLDS)}", "0") for _ in range(n_poison * 2)})[:n_poison]
    combined = rows + [list(p) for p in poison]
    random.shuffle(combined)

    with open(OUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(combined)

    print(f"wrote {os.path.basename(OUT)}: {len(combined)} rows "
          f"(+{len(poison)} mislabeled '{args.family}' DGA tagged benign, "
          f"~{args.rate:.0%} poison)")
    print("next: load as a lookup and retrain into a SEPARATE model, e.g.")
    print("  | inputlookup dga_training_domains_poisoned.csv")
    print("  | fit MLTKContainer algo=dga_neural_network epochs=25 is_dga from domain into app:dga_model_poisoned")
    print("then compare dga_model vs dga_model_poisoned on the same domains.")


if __name__ == "__main__":
    main()
