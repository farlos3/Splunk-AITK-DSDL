# BOTSv1 dataset — staging area

Host-side staging for the **BOTSv1** (Boss of the SOC v1) dataset used by the
DGA detection POC. `setup.ps1` / `setup.sh` copy what's here into this
project's own Docker volume **`splunkaitk_splunk-botsv1`**, which the Splunk
container reads from.

> This project uses **BOTSv1 only** and is **self-contained** — it never reads
> from the sibling `Splunk-Environment-Lab`. (The `botsv2/` and `botsv3/`
> folders, if present, are unused here.)

```
bots-data/
└── botsv1/        ← BOTSv1 archive (.tgz) + extracted Splunk app
```

After extraction `botsv1/` holds the Splunk app straight from the archive:

```
bots-data/botsv1/
├── default/                  ← indexes.conf (defines the botsv1 index), ...
├── metadata/
├── var/lib/splunk/botsv1/    ← pre-indexed Splunk buckets (the heavy bit, ~9 GB)
└── README, LICENSE, ...
```

## How it gets populated

**You don't have to fetch it manually** — `setup.*` does it for you. On the
first run, if `bots-data/botsv1/` has no extracted data, the script
**downloads the ~6 GB `.tgz` here (resumable), extracts it, and copies it into
the volume**:

```powershell
.\setup.ps1                  # downloads + extracts + loads BOTSv1
```
```bash
./setup.sh                   # same
```

### If you already have the archive (skip the download)

Drop `botsv1_data_set.tgz` into `bots-data/botsv1/` and run:

```powershell
.\setup.ps1 -SkipDownload
```
```bash
./setup.sh --skip-download
```

### Other options

| Flag (ps1 / sh) | Effect |
|---|---|
| `-SkipBots` / `--skip-bots` | set up without BOTSv1 at all |
| `-SkipDownload` / `--skip-download` | use a `.tgz` already in this folder (don't download) |
| `-UrlV1 <url>` / `--url-v1 <url>` | override the download URL (Splunk has moved it before) |
| `-Force` / `--force` | wipe + repopulate the BOTSv1 volume |

If the auto-download URL is dead, grab the archive by hand:
1. Open <https://github.com/splunk/botsv1>
2. Follow the current **Download** section
3. Save the `.tgz` into `bots-data/botsv1/`
4. Run `setup` with `-SkipDownload` / `--skip-download`

## Why this isn't in git

The archive and extracted buckets are ~15 GB combined — GitHub rejects single
files >100 MB. `.gitignore` keeps only this README and the `botsv1/.gitkeep`
placeholder; the data is downloaded on setup.

## Verify after setup

In Splunk (<http://localhost:8000>), time range **All time**:

```spl
index=botsv1 earliest=0 | stats count by sourcetype
```

Expect millions of events across `stream:dns`, `WinEventLog:Security`,
`fgt_traffic`, Sysmon, `iis`, and more. The `stream:dns` sourcetype is what the
DGA POC scores — see [`../dga/README.md`](../dga/README.md).
