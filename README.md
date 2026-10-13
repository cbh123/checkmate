# Checkmate

A tiny macOS menu bar app that shows how far along your latest GitHub Actions run is. A progress bar fills toward the workflow's usual duration and turns green or red when the run finishes. Click it for the last 10 runs; click a run to open it on GitHub.

![Checkmate icon](design/icon/AppIcon.png)

## Download

Requires macOS 14 or later.

1. Download [Checkmate.zip](https://github.com/cbh123/checkmate/releases/latest/download/Checkmate.zip) and unzip it.
2. Drag **Checkmate.app** into Applications and open it.
3. Checkmate isn't notarized by Apple, so macOS blocks the first launch. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Checkmate.

## Setup

Click the menu bar icon:

1. **Token**: if you use the GitHub CLI, run `gh auth token | pbcopy` and click **Paste**. Otherwise [create a classic token](https://github.com/settings/tokens/new?scopes=repo&description=Checkmate) with the `repo` scope. The token is stored in your Keychain.
2. **Repository**: type `owner/repo` or pick one from the menu.
3. **Workflow**: pick the workflow to watch.
4. Optional: a branch filter, **Only my runs**, and **Launch at login**.

## How it works

- Polls `GET /repos/{repo}/actions/workflows/{id}/runs` every 10 s while a run is active and every 30 s otherwise.
- The usual duration is the median of the last 10 successful runs that match your filters. GitHub has no end timestamp for runs, so duration is `updated_at - run_started_at`.

## Build from source

Requires Xcode or the Command Line Tools.

```sh
./install.sh            # build, install to /Applications, and launch
./release.sh v0.2       # build and publish a GitHub release
```

Design specs: open `design/mockups.html?s=a` (menu bar and popover) or `?s=s` (setup) in a browser.
