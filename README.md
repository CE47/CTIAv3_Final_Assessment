# CTIA Scenario Lab — final_exam

A self-contained SOC analyst **final examination**. One student, one Elastic stack, six
months of telemetry, and no walkthrough: the student opens the Alerts page and the four data
views and works the incident out alone, then submits a report.

---

## The scenario

Northwind Industrial Systems — a mid-size industrial supplier — is the client. Between
**2026-04-27** and **2026-08-23** an external actor held valid credentials against the estate,
moved through two workstations, a file server and the Microsoft 365 tenant, and exfiltrated
10.39 GiB. Across 118 days they produced **exactly one failed logon**.

The point of the scenario is what it does *not* do: it does not put the answer on the Alerts
page. **671 alerts fire, and only 5 of them point at the attacker.** The loudest alert on
the page — critical severity, directory replication — belongs to an authorised vulnerability
assessment. Triage from the Alerts page reports the wrong incident.

Four synthetic, deterministic log sources are loaded into Elasticsearch:

| Data view | Index pattern | Documents | What it covers |
|---|---|---|---|
| `auth` | `auth-*` | 14,234 | Windows security events: logons and failed logons, logoffs, privilege assignment, lockouts, process creations, Kerberos ticket requests, directory-service access, credential caching, scheduled task creation |
| `network` | `network-*` | 4,906 | Connections between hosts and toward external peers: SMB, RPC, DNS, LDAP, Kerberos, HTTP/HTTPS, RDP, WinRM, SSH |
| `dns` | `dns-*` | 6,693 | Resolver queries with question name, record type, response code and answer |
| `cloud` | `cloud-*` | 1,132 | Microsoft 365 unified audit: sign-ins, MFA challenges, OAuth consents, inbox rules, file downloads |

Timestamps are stored in UTC. Kibana displays them in your own timezone — read the clock
times off your own screen and judge the gaps between events, not the absolute numbers.

---

## How to run the lab

### 1. Windows — set up Docker Desktop

1. Install **WSL**. In an elevated PowerShell window:

   ```powershell
   wsl --install
   ```

   Restart Windows when it asks, then run `wsl --install --no-distribution` again if needed.
   Verify with `wsl --status`.

2. Install **Docker Desktop for Windows** from <https://www.docker.com/products/docker-desktop/>.
   Let it finish installing WSL 2 backend updates, then launch Docker Desktop and wait until
   the whale icon reports **Engine running**.

### 2. Linux / macOS — set up Docker

Install **Docker Desktop** (<https://www.docker.com/products/docker-desktop/>) or Docker
Engine with the Compose plugin, make sure it is running, and skip to step 3.

### 3. Build the lab

Double-click **`setup-lab.cmd`** (Windows), or run `./setup-lab.sh` in a terminal
(Linux / macOS).

The script builds and verifies everything in ten stages: it starts Elasticsearch and Kibana in
Docker, installs four index templates, imports the four datasets, creates the four data views,
installs the five detection rules, and then **asserts every graded figure in the lab against
the live index** before it will call the lab ready. First run downloads over a gigabyte of
images, so be patient.

When it finishes it prints:

```
  The lab is ready.

  Kibana login   lab_kibana  /  LabKibana001
```

and it opens Kibana on the Alerts page together with `submission.html`.

> **Note, and it is deliberate:** unlike the practice labs, this script prints **no
> investigation queries and no expected counts**. Choosing what to run, and in what order, is
> the examination.

### 4. Perform the investigation

- **Telemetry covers `2026-03-25` to `2026-09-30`.** Set the Kibana time range picker to that
  whole window before you count anything, or every count you take will be wrong. Check the
  same way on **Security → Alerts**.
- Sign in with the lab credentials if prompted. They are throwaway credentials and protect
  nothing.
- Useful starting points: **Security → Alerts** (671 alerts from five rules) and the `auth` /
  `network` / `dns` / `cloud` data views under **Discover**.
- **Read `submission.html`.** It carries the brief — the asset register, the change calendar
  and the offboarding register — and the form you submit on. It contains no queries, no field
  hints and no answers.

### 5. Write it up and submit

`submission.html` is the deliverable. It has nine parts: a timeline, evidence per finding,
six look-alikes to rule out, attributed accounts and hosts, impact, twelve verdicts, a
response plan, an assessment of the five detection rules, and a narrative. Every field starts
empty on purpose.

Your work is kept in the browser as you type, so a closed tab will not cost you the paper.
When you are finished press **`EXPORT MY SUBMISSION`**: a PDF report is built in your browser
and saved to your **Downloads** folder. Nothing is uploaded. That PDF is your submission.

### 6. Clean up

- **Windows:** double-click `teardown.cmd`
- **Linux / macOS:** run `./teardown.sh`

Both remove exactly what the setup created, named after this folder, and never touch other
Docker resources or other labs.

---

## Files in this folder

| File | Description |
|---|---|
| `README.md` | this file |
| `submission.html` | **the examination paper and the submission form — open this in a browser** |
| `auth.ndjson` / `auth.json` | auth events and the `auth-*` index template |
| `network.ndjson` / `network.json` | network events and the `network-*` index template |
| `dns.ndjson` / `dns.json` | DNS queries and the `dns-*` index template |
| `cloud.ndjson` / `cloud.json` | cloud audit events and the `cloud-*` index template |
| `rule.json` … `rule-5.json` | the five detection rules the lab installs, so the Alerts page is not empty |
| `setup-lab.cmd` / `setup-lab.sh` | **Windows / Linux-macOS.** One-click lab build, fully verified |
| `teardown.cmd` / `teardown.sh` | **Windows / Linux-macOS.** Safe, scenario-scoped, idempotent removal |

`docker-compose.yml` is generated by the setup script; delete it and re-run setup to rebuild
it.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `docker` is not recognized | Install and start Docker Desktop, then reopen the terminal |
| Setup fails at the Docker check | Docker is not running — launch Docker Desktop and wait for **Engine running** |
| Setup fails later with a container error | `docker logs final_exam-elasticsearch` |
| Every query returns nothing | The time range picker is still on *Last 15 minutes*. Set it to `2026-03-25` → `2026-09-30` (UTC) |
| The Alerts page is empty | Security must be on or no rule can be created. Re-run `./setup-lab.sh`, which installs the five rules and waits for all 671 alerts |
| A KQL query is rejected with `missing ')' at 'or'` | This build does not accept `field: ("a" or "b")`. Repeat the field: `(field: "a" or field: "b")`. The brief says so |
| A date range is rejected | KQL has no `[from TO]` syntax. Use `@timestamp > "2026-03-25"` and `@timestamp < "2026-09-30"` |
| Want a clean slate | Run `teardown.cmd` / `./teardown.sh`, then setup again |
