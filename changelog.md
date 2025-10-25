# Changelog

## [0.3.0] (2025-10-25)

Fixed a bug where, on macOS only, the `${{ ... }}` expression were not being stripped from embedded scripts ([09d65fa]).

Also delayed processing matrix variables (for OS detection) until, and unless, strictly needed for each job ([c0ce39a]).

## [0.2.0] (2025-10-21)

Set shell options (`-e` and/or `-o pipefiail`) in the same manner that GitHub does ([6ecd126]).

## [0.1.1] (2025-10-21)

Exposed the script's `--set` option via a new `external-variables` action input ([0eac356]).

## [0.1.0] (2025-10-19)

Initial release.

[0.3.0]: https://github.com/pcolby/check-run-scripts/releases/tag/v0.3.0
[0.2.0]: https://github.com/pcolby/check-run-scripts/releases/tag/v0.2.0
[0.1.1]: https://github.com/pcolby/check-run-scripts/releases/tag/v0.1.1
[0.1.0]: https://github.com/pcolby/check-run-scripts/releases/tag/v0.1.0

[09d65fa]: https://github.com/pcolby/check-run-scripts/commit/09d65fa9363a834732b5fd5ee39b9d1e96ce4c73
[0eac356]: https://github.com/pcolby/check-run-scripts/commit/0eac3565190ca900e68c4126644ae3cf7cc321c1
[6ecd126]: https://github.com/pcolby/check-run-scripts/commit/6ecd1266ae6a38d718eeee7cb7e94e38e8d5f46f
[c0ce39a]: https://github.com/pcolby/check-run-scripts/commit/c0ce39a513fddf9f49795a7d16660987b4f07b15
