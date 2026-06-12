# Staging area for the Splunkbase apps

`./setup.sh` installs the three required Splunk apps into the
container at first boot. They are **not auto-downloaded** — Splunkbase
requires a (free) login, so you download them once by hand and drop the
`.tgz` files **in this folder**. The setup script discovers them by name
and installs them in the right order.

> These `.tgz` files are gitignored — they are not committed to the repo.

## What to download

Log in at <https://splunkbase.splunk.com> and download these three. Take
the **latest version that supports your Splunk Enterprise version**, and
for PSC pick the **Linux 64-bit** build (the container is `linux/amd64`).

| # | App | Splunkbase | Filename looks like |
|---|-----|-----------|---------------------|
| 1 | **Python for Scientific Computing (PSC)** — *Linux 64-bit* | <https://splunkbase.splunk.com/app/2882> | `python-for-scientific-computing-for-linux-64-bit_*.tgz` |
| 2 | **Splunk AI Toolkit (AITK)** (formerly Machine Learning Toolkit) | <https://splunkbase.splunk.com/app/2890> | `splunk-ai-toolkit_*.tgz` (older: `splunk-machine-learning-toolkit_*`) |
| 3 | **Splunk App for Data Science and Deep Learning (DSDL)** | <https://splunkbase.splunk.com/app/4607> | `splunk-app-for-data-science-and-deep-learning_*.spl` |

> Splunkbase serves these as either **`.tgz`** or **`.spl`** — both are the
> same gzipped-tar format and the setup script accepts either. PSC and AITK
> are hard prerequisites for DSDL; install order is enforced as
> **PSC → AITK → DSDL**.

## After downloading

Drop all three `.tgz` here, e.g.:

```
splunk-apps/
├── python-for-scientific-computing-for-linux-64-bit_42.tgz
├── splunk-machine-learning-toolkit_543.tgz
└── splunk-app-for-data-science-and-deep-learning_522.tgz
```

Then from the repo root run `../setup.sh`.

If the script can't match a file, rename it so the name contains the
keyword it looks for (`scientific-computing` + `linux`,
`machine-learning-toolkit`, `deep-learning`).

---

<sub>📝 All documentation in this repo — every `.md` file and `docs/AI-Usage-Flow.pdf` — was written with **Claude** (Anthropic's AI assistant).</sub>
