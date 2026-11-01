# Windows Larger Runner Inspector

A safe GitHub Actions project that reports the Windows runner's CPU, RAM, GPU adapter names, and local storage, then uploads JSON and Markdown reports as workflow artifacts.

## What it does

- Runs on a GitHub-hosted Windows runner.
- Collects hardware and Windows OS information using built-in PowerShell CIM commands.
- Writes `reports/hardware.json` and `reports/hardware.md`.
- Runs validation checks to confirm the report is complete.
- Uploads the reports to the Actions run as an artifact.

This project is a CI hardware-inspection workflow. It does **not** create a persistent desktop, enable Remote Desktop, open inbound ports, install Tailscale, or run downloaded batch files.

## Run it

1. Open the repository's **Actions** tab.
2. Select **Windows Hardware Inspector**.
3. Select **Run workflow** and keep the default runner label `windows-2022`.
4. Open the completed run and download the `hardware-report` artifact.

A push to the default branch also runs the workflow automatically.

## Larger runners

The workflow has an optional `runner_label` input. The default `windows-2022` uses the standard GitHub-hosted Windows runner. If your repository is allowed to use an Organization Larger Runner, enter the exact label copied from **Actions → Runners**.

GitHub's currently documented maximum general-purpose x64 Windows Larger Runner is 96 vCPU, 384 GB RAM, and 2,040 GB SSD. Larger Runners require an Organization or Enterprise on GitHub Team or GitHub Enterprise Cloud. They are not available to a personal-account repository merely by changing the YAML label. The runner must first be created by an Organization/Enterprise owner and made available to this repository.

## Files

- `.github/workflows/hardware-inspector.yml` — workflow definition.
- `scripts/Check-Hardware.ps1` — hardware report generator.
- `tests/Test-Hardware.ps1` — report validation.
