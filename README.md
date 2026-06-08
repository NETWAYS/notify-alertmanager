# Icinga Notifications to Prometheus Alertmanager

Send Icinga2 notifications to the Prometheus Alertmanager.

It transforms the Icinga2 notification into JSON data and sends this data to the Alertmanager API: https://prometheus.io/docs/alerting/latest/alerts_api/

Other Icinga and Prometheus integrations we provide:

* https://github.com/NETWAYS/check_prometheus/
* https://github.com/NETWAYS/icinga2-exporter
* https://github.com/NETWAYS/icingaweb2-module-perfdatagraphs-prometheus
* https://github.com/NETWAYS/alertmanager-icinga-bridge

## Installation

`notify-alertmanager.sh` is a shell script. Requirements:

- `curl` for sending the alert to the Alertmanager
- `date` for the alert's `startsAt/endsAt` timestamp

## Usage

```
Usage: notify-alertmanager.sh [OPTIONS]

Options:
  -t TYPE              Object type: host | service
  -T NOTIFICATION_TYPE Icinga notification type: PROBLEM | RECOVERY | ACKNOWLEDGEMENT | FLAPPINGSTART | FLAPPINGSTOP | DOWNTIMESTART | DOWNTIMEEND
  -H HOST_NAME         Icinga host name
  -u ALERTMANAGER_URL  Alertmanager base URL (default: http://localhost:9093)
  -c COMMENT           Notification comment
  -a AUTHOR            Notification author
  -i ICINGA_URL        Icinga URL for the object (used in annotations)
  -l LABELS            Extra labels as comma-separated key=value pairs
  -s STATE             Object state: UP | DOWN | UNREACHABLE | OK | WARNING | CRITICAL | UNKNOWN
  -v                   Verbose output
  -h                   Show this help

Host options:
  -d DISPLAY_NAME      Host display name (optional)
  -A ADDRESS           Host address (optional)

Service options:
  -n SERVICE_NAME         Service name (required when TYPE is service)
  -N SERVICE_DISPLAY_NAME Service display name (optional)
```

Examples:

```bash
# Service
notify-alertmanager.sh -t service -T PROBLEM -H myhost \
-d "My Host" -A 192.168.1.1 -s CRITICAL -n "ping" -N "Ping Check" -u http://localhost:9093 -l severity=critical

notify-alertmanager.sh -t service -T RECOVERY -H myhost \
-d "My Host" -A 192.168.1.1 -s CRITICAL -n "ping" -N "Ping Check" -u http://localhost:9093 -l severity=critical

# Host
notify-alertmanager.sh -t host -T DOWN -H myhost \
-d "My Host" -A 192.168.1.1 -s CRITICAL -u http://localhost:9093 -l severity=critical,priority=high

notify-alertmanager.sh -t host -T UP -H myhost \
-d "My Host" -A 192.168.1.1 -s CRITICAL -u http://localhost:9093 -l severity=critical,priority=high
```

Note that the Icinga notification type (PROBLEM, RECOVERY, etc.) and state (OK, CRITICAL, etc.) are not used a labels in the final alert.
This is because the Prometheus Alertmanager uses labels to match firing-resolved alerts, using changing type/state as labels would hinder this matching.

Use the `-l` flag to add additional static labels to add further information: `-l severity=critical`.
