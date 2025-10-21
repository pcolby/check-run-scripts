# Check `run` Scripts

[![Test](https://github.com/pcolby/check-run-scripts/actions/workflows/test.yaml/badge.svg)](
https://github.com/pcolby/check-run-scripts/actions/workflows/test.yaml)
[![Lint](https://github.com/pcolby/check-run-scripts/actions/workflows/lint.yaml/badge.svg)](
https://github.com/pcolby/check-run-scripts/actions/workflows/lint.yaml)

GitHub Action, and stand-alone script, for running ShellCheck against scripts embedded in GitHub Actions [workflow] and
[composite action] files.

## Why

Testing stand-alone scripts is easy. You can simply run [ShellCheck] on them directly. Likewise, testing them in GitHub
Actions as some sort of CI process is easy: just add a step that runs [ShellCheck].

However, if you have scripts _embedded_ into GitHub Actions files, checking them is not so easy. This project can help
with that.

> [!TIP]
> Because this Action/script uses [ShellCheck], only scripts for shells supported by [ShellCheck] are checked.
> Specifically both GitHub Actions, and [ShellCheck] support `bash` and `sh`, so only those are checked. Run steps using
> `cmd`, `pwsh`, etc are simply logged, and skipped.

## Running Locally

### Dependencies

The script depends on [Bash], [jq] and [yq], so install those first, if you don't have them already.

### Installation

To install, simply download the `check-run-scripts.sh` script to somewhere you like, and make it executable.

```sh
curl -O 'https://raw.githubusercontent.com/pcolby/check-run-scripts/v0.2/check-run-scripts.sh'
chmod u+x check-run-scripts.sh
./check-run-scripts.sh --version
```

### Command-Line

Once installed, run either:

1. in a project's root folder, with a `.github/workflows/` folder containing `*.yaml` or `*.yml` files; or
2. in a folder containing workflow `*.yaml` or `*.yml` files; or
3. with positional arguments listing one or more files or directories to search.

You can use the `--help` option for more details.

```text
Usage: ./check-run-scripts.sh [<options>] [<path> [...]]

Options:
  -c,--color=<when> Use color (auto, always, never). Defaults to auto.
  -d,--debug        Enable debug output.
  -h,--help         Show this help text and exit.
  -s,--set=<names>  Set <names> in each extracted script, so ShellCheck treats
                    them as assigned.
  -v,--version      Show the script's version, and exit.
  -                 Treat the remaining arguments as positional.

Additionally, any options that start with --sc- will be passed to ShellCheck
with the --sc prefix removed. For example, '--sc--norc'. See the ShellCheck
manual for the range of options available. If no ShellCheck options are set,
the following options are used by default:
  --check-sourced --enable=all --external-sources --norc
```

### Examples

```sh
# Checking the ./.github/workflows directory.
$ ./check-run-scripts.sh
2025-10-18 17:28:46 Checking directory: ./.github/workflows
2025-10-18 17:28:46 Checking: ./.github/workflows/test.yaml
2025-10-18 17:28:46 Checking job: test
2025-10-18 17:28:46 Checking step: test[1]
...
2025-10-18 17:28:46 Checking step: test[5]
2025-10-18 17:28:46 Checking: ./.github/workflows/lint.yaml
2025-10-18 17:28:46 Checking job: check
2025-10-18 17:28:46 Checking step: check[1]
...
$
# Checking one or more specific files (or directories).
$ ./check-run-scripts.sh action.yaml
2025-10-18 17:30:46 Checking: action.yaml
...
$
```

## GitHub Action

> [!NOTE]
> The action requires `shellcheck`, `jq` and `yq` commands. While GitHub includes these commands on Ubuntu runners
> already, one or more of those need to be installed on macOS and Windows. See the [macOS](#macos) and
> [Windows](#windows) sections below for details.

### Action Usage

```yaml
- uses: pcolby/check-run-scripts@v0.2
  with:
    # Files or directories containing workflow/action files to check. If not specified, files under the
    # `./.github/workflows` folder will be checked, otherwise files in the current working directory itself.
    # Paths must be new-line separated. Hint: use YAML's `|-` block scalar syntax.
    paths: |-
      ${{ github.workspace }}/.github/workflows
      action.yaml

    # Emit warnings in sourced files. Normally, `shellcheck` will only warn about issues in the specified files. With
    # this input set to `true`, any issues in sourced files will also be reported. Defaults to `true`.
    check-sourced: true

    # Comma-separated list of codes to include, for example `SC2016,SC2310`.
    # Optional. Defaults to `all`.
    include: all

    # Comma-separated list of codes to exclude, for example, `SC2016,SC2310`.
    # Optional. Defaults is '' (none).
    exclude: SC2016,SC2310

    # Follow source statements even when the file is not specified as input. By default, `shellcheck` will only follow
    # files specified on the command line (plus `/dev/null`). This option allows following any file the script may
    # source.
    # Optional. Default is `true`.
    external-sources: true

    # Comma-separated list of variables to assume are defined elsewhere. Useful, for example, if earlier steps create
    # environment variables by writing to `${GITHUB_ENV}`.
    external-variables: SOME_ENV_VAR,SOME_OTHER_VAR

    # Configuration file to prefer over searching for one in the default locations.
    # Optional. Default is '' (none).
    rc-file: some/preferred/shellcheck.rc

    # Additional paths to search for sourced files. Paths must be new-line separated. Hint: use YAML's `|-` block scalar
    # syntax.
    # Optional. Default is '' (none).
    source-path: |-
      some/extra/path
      another/path

    # Override shell dialect. Valid values are `sh`, `bash`, `dash`, `ksh`, and `busybox`.
    # Optional. Defaults to auto-detecting from the action/workflow file/s.
    shell: bash

    # Minimum severity of errors to report. Must be one of the levels supported by `shellcheck`; currently: `error`,
    # `warning`, `info` and `style`.
    # Optional. Defaults to allowing `shellcheck` to use it's own default, which is currently `style`.
    severity: info

    # Set to `true` to enable debug output.
    # Optional. Default is '' (non-true).
    debug: true
```

[composite action]: https://docs.github.com/en/actions/concepts/workflows-and-actions/custom-actions#composite-actions
[ShellCheck]: https://github.com/koalaman/shellcheck
[workflow]: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax

### macOS

For GitHub's macOS runners, `bash` must be upgraded (macOS's Bash is ancient), and `shellcheck` installed.

```yaml
- run: brew install bash shellcheck
- uses: pcolby/check-run-scripts@v0.2
```

### Windows

For GitHub's Windows runners, both `shellcheck` and `yq` must be installed.

```yaml
- run: choco install shellcheck yq
- uses: pcolby/check-run-scripts@v0.2
```

[Bash]: https://www.gnu.org/software/bash/
[jq]: https://jqlang.org/
[yq]: https://mikefarah.gitbook.io/yq
