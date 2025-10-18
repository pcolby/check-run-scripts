
# Check 'Run' Scripts

GitHub Action, and standalone script, for running ShellCheck against scripts embedded in GitHub Actions [workflow] and
[composite action] files.

> [!TIP]
> Because this Action/script uses [ShellCheck], only scripts for shells supported by [ShellCheck] are checked.
> Specifically both GitHub Actions, and [ShellCheck] support `bash` and `sh`, so only those are checked. Run steps using
> `cmd`, `pwsh`, etc are simply logged, and skipped.

## Why

Testing standalone scripts is easy. You can simply run [ShellCheck] on them directly. Likewise, testing them in GitHub
Actions as some sort of CI process is easy: just add a step that runs [ShellCheck].

However, if you have scripts embedded into GitHub Actions files, checking them is not so easy. This project can help
with that.

## Running Locally

### Dependencies

The script depends on [Bash], [jq] and [yq], so install those first, if you don't have them already.

### Installation

To install, simply download the `check-run-scripts.sh` script to somehwere you like, and make it executable.

```sh
curl ... \todo
chmod u+x check-run-scripts.sh
```

### Usage

Once installed, run either:

1. in a folder containing workflow `*.yaml` files; or
2. in a project's root folder, with a `.github/workflows/` folder containing `*.yaml` files; or
3. with positional arguments listing one or more files or directories to search.

You can use the `--help` option for more details.

```text
Usage: [SHELLCHECK_OPTS=...] ./check-run-scripts.sh <options> [<path> [...]]

Options:
  -d,--debug        Enable debug output.
  -h,--help         Show this help text and exit.
  -s,--set <names>  Set <names> in each extracted script, so ShellCheck treats
                    them as assigned.
  -v,--version      Show the script's version, and exit.
  -                 Treat the remaining arguments as positional.

See ShellCheck manual for SHELLCHECK_OPTS. If not already set, this script
defaults it to: --check-sourced --enable=all --external-sources --norc
```

## Using GitHub Action

> [!WARNING]
> The GitHub Action is currently in development, and will be available soon. The information here is likely to change.

### Inputs

> [!NOTE]
> The action requires `shellcheck`, `jq` and `yq` commands. While GitHub includes these commands on Ubuntu runners
> already, one of more of those need to be installed on [macOS](#macos) and [Windows](#windows) runners. See below.

```yaml
- use: pcolby/check-run-scripts@v0.1
  with:
    # One or more paths to check \todo new-line separated?
    # Default is the current directoy.
    paths:

    \todo All shellcheck options?
```

[composite action]: https://docs.github.com/en/actions/concepts/workflows-and-actions/custom-actions#composite-actions
[ShellCheck]: https://github.com/koalaman/shellcheck
[workflow]: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

### macOS

For GitHub's macOS runners, `bash` must be upgraded (macOS's Bash is ancient), and `shellcheck` installed.

```yaml
- run: brew install bash shellcheck
- use: pcolby/check-run-scripts@v0.1
```

### Windows

For GitHub's Windows runners, both `jq` and `yq` must be installed.

```yaml
- run: choco install shellcheck yq
- use: pcolby/check-run-scripts@v0.1
```

[Bash]: https://www.gnu.org/software/bash/
[jq]: https://jqlang.org/
[yq]: https://mikefarah.gitbook.io/yq
