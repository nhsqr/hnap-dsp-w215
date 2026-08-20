# Changelog

All notable changes to this project are documented in this file.

## [2.0.0] – 2026-08-20

### Added
- Modern CLI with short/long options (`-i/--ip`, `-p/--pin`, `-j/--json`, …)
- Configuration via environment variables `DSP_W215_IP` / `DSP_W215_PIN`
- JSON output mode for easy scripting and automation
- `info` command (GetDeviceSettings)
- `schedule` command (GetScheduleSettings + GetRecursiveSchedule)
- `reboot` command (requires `--force`)
- Proper exit codes and clear error messages
- Timeouts and `--fail` on all curl calls
- XML escaping for nickname/description when setting state
- Portable value extraction (no longer depends on `grep -P`)
- Version flag (`-v` / `--version`)
- Quiet mode

### Changed
- Complete rewrite for clarity, maintainability and robustness
- Login and SOAP helpers are now modular
- Fresh timestamp is generated for every SOAP call
- Help text and documentation significantly expanded

### Fixed
- Fragile XML parsing on systems without Perl-compatible grep
- Silent failures when the device is unreachable
- Potential XML injection when nickname/description contain special characters

### Backward compatibility
- Old-style `--state`, `--power`, `--temp`, `--total` still accepted

## [1.x] – 2017–2022

- Original script by nhsqr
- Basic state / power / temperature / total consumption support
