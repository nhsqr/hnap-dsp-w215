# hnap-dsp-w215

Lightweight **Bash** client for the D-Link DSP-W215 Wi-Fi Smart Plug using the HNAP protocol.

**Version 2.0.0** – major usability, robustness and feature update.

## Features

- Get / set socket state (on/off)
- Current power consumption (W)
- Temperature (°C)
- Monthly total energy (kWh)
- Device information (model, firmware, MAC…)
- Schedule settings readout (`GetScheduleSettings` + `GetRecursiveSchedule`)
- Optional JSON output for easy integration (Node-RED, Home Assistant, cron, etc.)
- Clean CLI with environment variable / flag configuration
- Portable (no `grep -P`), proper error handling and timeouts
- Pure Bash + common Unix tools only

## Requirements

- `bash` ≥ 4
- `curl`
- `openssl`
- `xxd` (or `od` as fallback)
- Optional: `xmllint` (for pretty-printed schedule XML)

## Installation

```bash
git clone https://github.com/nhsqr/hnap-dsp-w215.git
cd hnap-dsp-w215
chmod +x hnap-dsp-w215.sh
```

You can also copy just the script to any directory in your `$PATH`.

## Configuration

The device IP and PIN can be supplied in three ways (highest priority first):

1. Command-line flags: `-i` / `--ip` and `-p` / `--pin`
2. Environment variables: `DSP_W215_IP` and `DSP_W215_PIN`
3. (Legacy) edit the two variables at the top of the script

The PIN is the 6-digit code printed on the device or on the setup card.

**Security note:** Do not commit your real PIN. Prefer environment variables or a local config that is excluded from version control.

## Usage

```text
hnap-dsp-w215.sh [OPTIONS] COMMAND [ARGS]

Options:
  -i, --ip IP          Device IP address
  -p, --pin PIN        Device PIN
  -j, --json           Machine-readable JSON output
  -q, --quiet          Suppress progress messages
  -f, --force          Confirm destructive actions (reboot)
  -h, --help
  -v, --version

Commands:
  state [on|off]       Get or set the socket state
  power                Current power (W)
  temp                 Temperature (°C)
  total                Total energy this month (kWh)
  info                 Device information
  schedule             Show schedule settings
  reboot               Reboot the device (needs --force)
```

### Examples

```bash
# Simple status
./hnap-dsp-w215.sh -i 192.168.1.50 -p 123456 state

# Turn on
./hnap-dsp-w215.sh -i 192.168.1.50 -p 123456 state on

# JSON for automation
./hnap-dsp-w215.sh --ip 192.168.1.50 --pin 123456 --json power
# → {"power_w":12.4}

# Using environment variables
export DSP_W215_IP=192.168.1.50
export DSP_W215_PIN=123456
./hnap-dsp-w215.sh temp
./hnap-dsp-w215.sh --json info
./hnap-dsp-w215.sh schedule
```

### Backward compatibility

The old long options still work:

```bash
./hnap-dsp-w215.sh --state
./hnap-dsp-w215.sh --state on
./hnap-dsp-w215.sh --power
./hnap-dsp-w215.sh --temp
./hnap-dsp-w215.sh --total
```

## Integration ideas

- **Node-RED** – `exec` node calling the script with `--json`
- **cron** – periodic logging of power/temperature
- **Home Assistant** – command-line sensor or shell command
- **Grafana / Influx** – scrape JSON and push metrics

## Notes & limitations

- The DSP-W215 reached End-of-Life years ago; no new official firmware is expected.
- Full *writing* of complex schedules (`SetScheduleSettings` / `SetRecursiveSchedule`) is not implemented – the XML structures are non-trivial. Reading is supported.
- Tested primarily with hardware revision B1 and firmware 2.x series. Other revisions may work but are untested.
- The original protocol research was done by [bikerp/dsp-w215-hnap](https://github.com/bikerp/dsp-w215-hnap).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

GNU General Public License v3.0 – see [LICENSE](LICENSE).
