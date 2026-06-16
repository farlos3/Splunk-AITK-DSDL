# MITRE ATLAS case studies — the real incidents behind this lab

[ATLAS case studies](https://atlas.mitre.org/studies) (`AML.CS00xx`) are
documented, real-world attacks on AI/ML systems — each one mapped to the same
ATLAS tactics/techniques you exercised in
[`../docs/GUIDE.md` 5](../docs/GUIDE.md#5-red-team-the-model-with-mitre-atlas).
They turn the lab's toy attacks into "this actually happened to a shipped
product".

Two of them **are this lab**: a CNN DGA detector and a deep-learning C&C
detector, both defeated the same way you defeat `dga_model`. The rest show the
poisoning and shadow-model patterns at production scale.

> IDs and details below were taken from the public ATLAS catalog; treat
> <https://atlas.mitre.org/studies> as the source of truth if numbering moves.
> Each entry is a real *reported* incident or red-team exercise, not a
> hypothetical.

---

## The two that mirror this lab exactly

### `AML.CS0001` — Botnet DGA Detection Evasion  ⭐ this is your lab

**The real one behind [5.2 (evade the model)](../docs/GUIDE.md#52-attack-a--evade-the-model).**
Palo Alto Networks' AI research team took a **publicly available CNN-based DGA
detector** — the same architecture class as this lab's `dga_neural_network` —
and tested it against ~50M domains from 64 botnet families. It scored >70% on 16
families. Then they applied a **generic mutation**: insert one string into each
DGA domain. **Detection across all 16 families dropped to under 25%.**

- ATLAS techniques: Search Open Technical Databases → Acquire Public AI
  Artifacts → Craft Adversarial Data: Black-Box Optimization (`AML.T0043.001`)
  → Verify Attack (`AML.T0042`) → **Evade AI Model (`AML.T0015`)**.
- **Why it matters here:** your [`craft_adversarial_domains.py`](craft_adversarial_domains.py)
  is a miniature of this — shaping DGA strings so a character model misreads
  them. The lesson is identical: a char-level detector keys on surface
  statistics, so a cheap, generic perturbation collapses recall. This is the
  single most relevant case study in ATLAS for this project.

### `AML.CS0000` — Evasion of Deep Learning Detector for Malware C&C Traffic

The companion case, also Palo Alto Networks: a deep-learning model that flags
malware **command-and-control** traffic in HTTP was bypassed by **removing
non-essential HTTP header fields** — the malicious traffic kept working but no
longer matched what the model learned.

- ATLAS techniques: Acquire Public AI Artifacts → Craft Adversarial Data →
  Evade AI Model (`AML.T0015`).
- **Why it matters here:** same defender problem one layer up the kill chain.
  DGA detection (this lab) and C&C-traffic detection are both ML controls a real
  attacker will probe and evade — so build them assuming evasion, not as a
  silver bullet.

---

## Poisoning at production scale → [5.3](../docs/GUIDE.md#53-attack-b--poison-the-training-data)

### `AML.CS0002` — VirusTotal Poisoning

An actor uploaded **mutated (metamorphic) ransomware variants** to VirusTotal.
Clustering/classification systems that learn from such aggregated samples got
their training data skewed — mislabeled or confused groupings — degrading
downstream malware detection.

- ATLAS: **Poison Training Data (`AML.T0020`)**.
- **Maps to your exercise:** [`poison_training_data.py`](poison_training_data.py)
  injects mislabeled DGA into the lookup; VirusTotal poisoning is the same idea
  against a pipeline that ingests untrusted, internet-sourced samples — exactly
  why 5.4 says *govern and validate the training data*.

### `AML.CS0009` — Tay Poisoning

Microsoft's Tay chatbot learned from live Twitter interactions. Coordinated
users fed it offensive content; the **feedback loop poisoned the model** and it
began emitting the same content. Pulled within 24 hours.

- ATLAS: **Poison Training Data (`AML.T0020`)** via an online learning loop.
- **Lesson for here:** any model that retrains on data an adversary can
  influence (a public lookup, user feedback, crowd-sourced labels) inherits this
  risk. Your poisoning attack is the offline version of the same failure.

---

## Shadow-model & reputation-fusion evasion (bonus context)

### `AML.CS0003` — Bypassing Cylance's AI Malware Detection

Skylight Cyber reverse-engineered Cylance's ML reputation scoring and learned
that appending strings from a known-benign file flipped malware to "clean" — a
**universal bypass** by fusing benign attributes onto malicious files.

### `AML.CS0008` — ProofPoint Evasion

Researchers built a **shadow (surrogate) model** of ProofPoint's email scoring
system from its outputs, then crafted emails against the shadow that transferred
to and evaded the live system.

- ATLAS: Create Proxy AI Model → Craft Adversarial Data → Evade AI Model.
- **Why included:** these show the next step beyond this lab — when an attacker
  can *query* your model ([5.4 API abuse](../docs/GUIDE.md#54-defenses--detections),
  `AML.T0040`/`AML.T0024`), they can clone its behavior and craft evasions
  offline. Rate-limiting and not leaking confidence scores is the defense.

---

## Full catalog (original ATLAS case studies)

A quick index so you can browse the rest at <https://atlas.mitre.org/studies>.

| ID | Case study | Primary technique | Relevance to this lab |
|---|---|---|---|
| `AML.CS0000` | Evasion of DL detector for malware C&C traffic | Evade AI Model | High — ML security control evaded |
| `AML.CS0001` | **Botnet DGA Detection Evasion** | Evade AI Model | **This lab** |
| `AML.CS0002` | VirusTotal Poisoning | Poison Training Data | High — poisoning a malware pipeline |
| `AML.CS0003` | Bypassing Cylance's AI Malware Detection | Evade AI Model | High — malware classifier evasion |
| `AML.CS0004` | Camera Hijack on Facial Recognition | Evade AI Model | Low — different modality |
| `AML.CS0005` | Attack on Machine Translation Service | Create Proxy Model | Med — model replication |
| `AML.CS0006` | ClearviewAI Misconfiguration | (traditional infra exposure) | Med — AI artifact theft |
| `AML.CS0007` | GPT-2 Model Replication | Create Proxy Model | Low — LLM scope |
| `AML.CS0008` | ProofPoint Evasion | Evade AI Model (shadow model) | High — surrogate + transfer |
| `AML.CS0009` | Tay Poisoning | Poison Training Data | High — feedback-loop poisoning |
| `AML.CS0010` | Microsoft Azure Service Disruption | Evade AI Model | Med — recon + evasion via API |
| `AML.CS0011` | Microsoft Edge AI Evasion | Craft Adversarial Data | Med — automated perturbation |
| `AML.CS0012` | Face Identification Physical Evasion (MITRE) | Craft Adversarial Data | Low — physical patch |

## How to use these in the lab

1. Read [`AML.CS0001`](https://atlas.mitre.org/studies) before 5.2 — you're
   reproducing it in miniature.
2. After each attack, ask "**which case study did I just re-create, and what was
   its real-world impact?**" — that's the bridge from teaching model to
   production risk.
3. For defense work, each case study lists the **mitigations** the vendor
   adopted; pull those into your 5.4 controls and your Splunk detections.

---

<sub>All documentation in this repo — every `.md` file and `../docs/AI-Usage-Flow.pdf` — was written with **Claude** (Anthropic's AI assistant).</sub>
