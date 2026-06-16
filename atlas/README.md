# Red-teaming the DGA model with MITRE ATLAS

[MITRE ATLAS](https://atlas.mitre.org/) (*Adversarial Threat Landscape for
Artificial-Intelligence Systems*) is ATT&CK's sibling for ML/AI systems — the
same tactic→technique structure, but for attacks **against the model itself**:
evading it, poisoning its training data, stealing it, abusing its API.

This folder turns the lab's [DGA detector](../dga/README.md) into the *target*
of an ATLAS exercise. You attack a model you trained yourself, on your own
machine — authorized, self-contained, defensive learning. Two hands-on attacks,
each mapped to ATLAS, plus the defenses.

> Full narrative walkthrough with success-checks lives in
> [`../docs/GUIDE.md` 5](../docs/GUIDE.md#5-red-team-the-model-with-mitre-atlas).
> This README is the folder map + the commands.

## How this lab maps to the ATLAS matrix

| ATLAS tactic | Technique (ID) | In this lab |
|---|---|---|
| ML Model Access | ML Model Inference API Access (`AML.T0040`) | DSDL exposes the model at `:5000`; `apply MLTKContainer` is the inference API. |
| ML Attack Staging | Craft Adversarial Data (`AML.T0043`) | `craft_adversarial_domains.py` — DGA domains shaped to read as benign. |
| Defense Evasion | Evade ML Model (`AML.T0015`) | those crafted domains scored `is_dga_predicted=0` → malware C2 sails through. |
| Persistence / ML Attack Staging | Poison Training Data (`AML.T0020`) | `poison_training_data.py` — mislabel DGA as benign in the training set. |
| Persistence | Backdoor ML Model (`AML.T0018`) | retraining on the poisoned set bakes the blind spot into the model. |
| Impact | Erode ML Model Integrity (`AML.T0031`) | the poisoned model's recall on that DGA family collapses. |
| Exfiltration | Exfiltration via ML Inference API (`AML.T0024`) | repeated `apply` queries can reconstruct the decision boundary (not exercised here). |

IDs follow the current matrix at <https://atlas.mitre.org/matrices/ATLAS>;
treat that as the source of truth if numbering shifts.

## Files

| File | What it is |
|---|---|
| `craft_adversarial_domains.py` | Generates `atlas_evasion_domains.csv` — adversarial DGA (pronounceable, dictionary, typo-squat) that try to evade the detector. All true label `is_dga=1`. |
| `poison_training_data.py` | Generates `dga_training_domains_poisoned.csv` — the clean set plus mislabeled DGA rows (`is_dga=0`). |
| [`CASE-STUDIES.md`](CASE-STUDIES.md) | Real-world ATLAS case studies (`AML.CS00xx`) behind these attacks — incl. `AML.CS0001`, a CNN DGA detector evaded exactly like this lab. |

> **The real incident behind this lab:** ATLAS case study
> [`AML.CS0001` Botnet DGA Detection Evasion](https://atlas.mitre.org/studies) —
> Palo Alto Networks dropped a public CNN DGA detector from >70% to <25% accuracy
> across 16 botnet families by inserting one string per domain. The evasion
> exercise below is a miniature of it. Full mapping in
> [`CASE-STUDIES.md`](CASE-STUDIES.md).

Both are stdlib-only and deterministic. The produced `.csv`s are gitignored —
regenerate them with `python <script>.py`.

## Prereqs

The DGA POC is already working: `dga_model` is trained and you can run
`| ... | apply dga_model` (see [`../dga/README.md`](../dga/README.md)). Loading a
CSV as a lookup uses the same `docker cp` trick as the DGA walkthrough.

---

## Attack A — Evasion (`AML.T0043` → `AML.T0015`)

Craft malicious domains that *look* benign to a character-level model, then
measure how many slip past the detector.

```bash
python atlas/craft_adversarial_domains.py        # writes atlas_evasion_domains.csv

# load it as a lookup (same pattern as the DGA training set)
docker cp atlas/atlas_evasion_domains.csv \
  splunk-aitk:/opt/splunk/etc/apps/search/lookups/atlas_evasion_domains.csv
docker exec splunk-aitk chown splunk:splunk \
  /opt/splunk/etc/apps/search/lookups/atlas_evasion_domains.csv
```

Measure the **evasion rate** — share of truly-malicious domains the model calls benign:

```spl
| inputlookup atlas_evasion_domains.csv
| apply dga_model
| eval evaded=if(is_dga_predicted=0, 1, 0)
| stats count AS total sum(evaded) AS evaded avg(dga_score) AS avg_score
| eval evasion_rate=round(evaded/total*100, 1)
```

See exactly which ones slipped through (these are the dangerous false negatives):

```spl
| inputlookup atlas_evasion_domains.csv
| apply dga_model
| where is_dga_predicted=0
| sort dga_score
| table domain dga_score
```

**Expected:** a chunk of `paiypal.com` / `cloudsecure.net` / `gi-thub.com`-style
domains score **below 0.5** and evade — the model learned "random soup = bad",
not "is this a real registered brand", so anything pronounceable beats it.

---

## Attack B — Data poisoning (`AML.T0020` → `AML.T0018` / `AML.T0031`)

Corrupt the training data so the *retrained* model learns to ignore a DGA
family — a backdoor that survives into production.

```bash
python atlas/poison_training_data.py --rate 0.15 --family random   # writes dga_training_domains_poisoned.csv

docker cp atlas/dga_training_domains_poisoned.csv \
  splunk-aitk:/opt/splunk/etc/apps/search/lookups/dga_training_domains_poisoned.csv
docker exec splunk-aitk chown splunk:splunk \
  /opt/splunk/etc/apps/search/lookups/dga_training_domains_poisoned.csv
```

Train a **separate** model from the poisoned set (keep the clean `dga_model` for comparison):

```spl
| inputlookup dga_training_domains_poisoned.csv
| fit MLTKContainer algo=dga_neural_network epochs=25 is_dga from domain into app:dga_model_poisoned
```

Score the same obvious DGA strings with both models and watch recall drop:

```spl
| makeresults
| eval domain="kq3v9zlxqpwmrt.top" | append [| makeresults | eval domain="x7f2a9d4e1b8.info"]
| apply dga_model           | rename dga_score AS score_clean, is_dga_predicted AS pred_clean
| apply dga_model_poisoned  | rename dga_score AS score_poisoned, is_dga_predicted AS pred_poisoned
| table domain score_clean pred_clean score_poisoned pred_poisoned
```

**Expected:** the clean model flags both (`pred_clean=1`); the poisoned model's
score drops and may call them benign (`pred_poisoned=0`). Try `--rate 0.05` to
see how little poison it takes, or `--family hex` / `--family consonant` to
backdoor a different DGA family.

---

## Defenses (ATLAS mitigations)

| Attack | ATLAS mitigation | Do this in the lab |
|---|---|---|
| Evasion (`AML.T0015`) | Adversarial Input Detection / Robustness (`AML.M0015`, `AML.M0003`) | Add the crafted domains (correctly labeled `is_dga=1`) back into training; add non-char features — entropy, n-gram rarity, length, TLD reputation; don't rely on a single score threshold. |
| Poisoning (`AML.T0020`) | Validate / Sanitize Training Data (`AML.M0007`, `AML.M0014`) | Govern the lookup as a controlled artifact; review label distribution before each `fit`; track data provenance; alert on training-set drift. |
| API abuse (`AML.T0024`/`T0040`) | Limit Model Queries (`AML.M0004`) | Rate-limit / authenticate the `:5000` endpoint; don't return raw confidence scores to untrusted callers. |

The honest framing: this is a *teaching* model on a few hundred rows, so it's
deliberately easy to fool. The transferable lesson is the **workflow** — treat
the model and its training data as attack surface, test them with ATLAS
techniques, and feed what you learn back into both the model and your Splunk
detections.

---

<sub>All documentation in this repo — every `.md` file and `../docs/AI-Usage-Flow.pdf` — was written with **Claude** (Anthropic's AI assistant).</sub>
