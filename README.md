# WMI Persistence Threat Simulation & ELK Detection Lab

A comprehensive detection engineering project simulating a multi-stage attack chain using 100% Living-off-the-Land (LOLBins) techniques, paired with custom behavioral detection rules engineered in Elastic SIEM.

**Domain:** Blue Team / Detection Engineering / SOC Operations  
**Tech Stack:** Windows 10, Sysmon, Elastic Stack (Elasticsearch, Kibana, Fleet), EQL, PowerShell  

---

## Overview

Signature-based detection mechanisms frequently fail against attacks that exclusively utilize native operating system utilities. This project addresses that gap by simulating a sophisticated, multi-phase attack chain and engineering detection rules based on **behavioral invariants** - architectural constraints of the Windows operating system that attackers cannot alter without abandoning the technique.

The project demonstrates end-to-end detection engineering: from attack simulation and telemetry collection (Sysmon) to log normalization (ECS), EQL correlation rule development, and real-time alerting.

---

## System Architecture & Data Pipeline

The detection pipeline is designed for high-fidelity telemetry collection and low-latency alerting:

```text
[Windows 10 Endpoint]
   ├─ Attack Execution (LOLBins)
   └─ Telemetry: Sysmon v15.15 (EID 1, 3, 11, 13, 19-21, 23)
          ↓ Windows Event Log
[Elastic Agent] → ECS Normalization → HTTPS/TLS 1.3
          ↓
[Elastic Cloud]
   ├─ Elasticsearch (Index: logs-windows.sysmon_operational-*)
   ├─ Kibana Detection Engine (EQL Rules evaluated every 60s)
   └─ Webhook → Telegram Bot (Real-time SOC Triage)
```

---

## Attack Simulation (Red Team Perspective)

The simulated kill chain consists of 7 phases, utilizing zero third-party malware or custom executables:

1. **Initial Access:** Delivery via password-protected RAR archive to bypass gateway AV scanning of encrypted content.
2. **Execution:** VBScript proxy (`wscript.exe`) spawns a hidden PowerShell session to execute the payload without flashing a console window (T1059.005).
3. **Privilege Escalation:** UAC Bypass via `fodhelper.exe` (T1548.002). The attack hijacks the `HKCU\Software\Classes\ms-settings\Shell\Open\command` registry key. Because `fodhelper.exe` has `autoElevate=true` in its manifest, Windows grants Administrator privileges silently. The registry key is deleted 3 seconds post-execution to narrow the forensic window.
4. **Persistence:** WMI Event Subscription (T1546.003). The payload installs an `__EventFilter`, a `CommandLineEventConsumer`, and a `__FilterToConsumerBinding` in the `root\subscription` namespace. This ensures the payload executes under `NT AUTHORITY\SYSTEM` whenever `notepad.exe` is launched, surviving reboots without leaving executable artifacts on disk.
5. **Discovery & Collection:** System enumeration (`arp.exe`, `Get-WmiObject`) and copying sensitive files to a staging directory (`C:\Windows\Temp\wdmp\`).
6. **Exfiltration:** Archiving the staging directory and uploading it via `curl.exe` to the Telegram Bot API over HTTPS (port 443), blending in with legitimate corporate traffic.
7. **Defense Evasion:** Detached `cmd.exe` processes are used to delete the staging directory, archives, payload scripts, and PowerShell history to hinder forensic analysis (T1070.004).

---

## Detection Engineering (Blue Team Perspective)

Nine custom EQL (Event Query Language) rules were engineered (5 Correlation, 4 Signal). The design philosophy prioritizes behavioral sequences over static artifact matching.

### Key Engineering Decisions:

- **Behavioral Invariants:** Rules are anchored to unchangeable OS behaviors. For example, WMI Consumer execution invariantly spawns from `WmiPrvSE.exe` under the `SYSTEM` user context. The UAC bypass invariantly requires writing to the `ms-settings` registry key prior to `fodhelper.exe` execution.
- **Sequence Logic with Timing Constraints:** Correlation rules (e.g., Rule C2 for WMI Persistence) require a strict sequence of events (EID 19 → 20 → 21) within a 30-second `maxspan`. This drastically reduces false positives compared to single-event alerts.
- **Fallback Detection Logic:** Native PowerShell cmdlets like `Copy-Item` do not spawn child processes, creating a blind spot for Process Creation (EID 1). The detection logic compensates by monitoring File Creation (EID 11) in known staging directories as a reliable fallback indicator for data collection.
- **ECS Mapping Resolution:** Addressed real-world inconsistencies where Elastic Agent does not consistently populate `process.parent.name` for network events. The detection logic was adjusted to use `user.name: SYSTEM` as the primary discriminator for elevated WMI execution.
- **Precision Tuning:** Excluded known security tool subscriptions (e.g., Defender, Elastic, Malwarebytes) from WMI persistence alerts and implemented CIDR-based IP filtering to eliminate internal network noise.

---

## Detection Rules & Metrics

| Rule ID | Type | Targeted Technique | Logic Summary | Severity |
| :--- | :--- | :--- | :--- | :--- |
| **C1** | Correlation | T1548.002 (UAC Bypass) | Sequence: `ms-settings` registry write → `fodhelper.exe` → shell interpreter (maxspan: 30s) | High |
| **C2** | Correlation | T1546.003 (WMI Persistence) | Sequence: WMI Filter (EID 19) → Consumer (EID 20) → Binding (EID 21) (maxspan: 30s) | Critical |
| **C3** | Correlation | T1546.003 + T1082/T1016 | Sequence: `WmiPrvSE.exe` spawns PowerShell (SYSTEM) → discovery binary or file staging (maxspan: 30s) | High |
| **C4** | Correlation | T1005 + T1560.001 + T1041 | Sequence: File staging → ZIP creation → outbound HTTPS from SYSTEM context (maxspan: 2m) | Critical |
| **C5** | Correlation | T1041 + T1070.004 | Sequence: Outbound HTTPS → immediate file deletion in staging paths (maxspan: 120s) | High |
| **S1-S4** | Signal | Various LOLBins | Standalone indicators (e.g., VBScript proxy, suspicious PS flags, SYSTEM outbound HTTPS) | Med-Crit |

**Performance Metrics:**

- **True Positive Rate:** 100% (All 7 phases of the kill chain triggered corresponding alerts).
- **False Positive Rate:** ~0% (Achieved by correlating multi-event sequences and leveraging user context discriminators).
- **Time to Detect (TTD):** 1–2 minutes from initial execution to alert generation.

---

## MITRE ATT&CK Mapping

This project maps directly to the following Enterprise Matrix techniques:

- **TA0001 Initial Access:** T1566.002, T1204.002
- **TA0002 Execution:** T1059.005
- **TA0003 Persistence:** T1546.003
- **TA0004 Privilege Escalation:** T1548.002
- **TA0007 Discovery:** T1082, T1016
- **TA0009 Collection:** T1005, T1560.001
- **TA0010 Exfiltration:** T1041
- **TA0005 Defense Evasion:** T1070.004

---

## Incident Response Playbook

Standard operating procedure for SOC analysts responding to Critical severity alerts (C2, C4, C5):

### Phase 1: Triage & Validation
1. Verify alert context: `host.name`, `user.name`, and `@timestamp`. Confirm the host is a production endpoint and the user is a standard employee.
2. Correlate events in Kibana SIEM. Verify that the sequence logic holds (e.g., for C2: EID 19 → 20 → 21 occurred within 30 seconds).
3. Exclude known false positives: ensure `winlog.event_data.Name` does not match approved security tools and the destination IP is not a known internal management server.

### Phase 2: Containment
1. **Network Isolation:** Immediately isolate the affected endpoint via EDR or switch port shutdown to prevent lateral movement. Do not power off the machine to preserve volatile memory.
2. **Account Suspension:** Temporarily disable the compromised user account in Active Directory to prevent credential reuse.

### Phase 3: Investigation & Pivoting

**Pivot 1 - Identify the initial execution vector:**
```text
process where
  winlog.event_id : "1" and
  host.name : "<affected_host>" and
  process.parent.name : "WmiPrvSE.exe" and
  user.name : "SYSTEM"
| sort @timestamp desc
| head 10
```

**Pivot 2 - Hunt for lateral movement or additional persistence:**
```text
any where
  host.name : "<affected_host>" and
  (
    (winlog.event_id : "13" and registry.path : "*\\Software\\Microsoft\\Windows\\CurrentVersion\\Run*") or
    (winlog.event_id : "1" and process.name : ("psexec.exe", "wmic.exe", "winrs.exe"))
  )
```

**Pivot 3 - Recover exfiltrated file hashes (post-cleanup):**
```text
file where
  winlog.event_id : "23" and
  host.name : "<affected_host>" and
  file.path : ("*\\Windows\\Temp\\*", "*\\Users\\Public\\*")
| keep file.path, file.hash.sha256, process.name
```

### Phase 4: Eradication & Recovery
1. **Remove WMI Persistence** via PowerShell:
   ```powershell
   Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -Filter "Filter LIKE '%NotepadFilter%'" | Remove-WmiObject
   Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='SystemDumpConsumer'" | Remove-WmiObject
   Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='NotepadFilter'" | Remove-WmiObject
   ```
2. **Credential Reset:** Force a password reset for the compromised user and any accounts that interacted with the affected host.
3. **Restore & Patch:** Re-image the endpoint if integrity is in doubt. Block the initial delivery domain/IP at the perimeter firewall.

---

## Threat Analysis & Behavioral Insights

### 1. The "Living-off-the-Land" Blind Spot
The entire kill chain executed without dropping a single third-party executable. Gateway AVs failed at Phase 1 because the initial payload was delivered via a password-protected RAR archive. Traditional signature-based EDRs failed because tools like `fodhelper.exe`, `wscript.exe`, and `curl.exe` are natively trusted and Microsoft-signed. This validates that **detection must rely on the context of execution** (parent-child relationships, user context, sequence), not the reputation of the binary.

### 2. The 3-Second Forensic Window
The UAC Bypass (Phase 3) demonstrates a highly evasive technique. The attacker writes to the `ms-settings` registry key, triggers `fodhelper.exe`, and deletes the registry key within approximately 3 seconds. A manual forensic investigator checking the registry post-incident would find nothing. However, Sysmon Event ID 13 captures the registry write at the exact moment it happens, proving that high-fidelity, real-time telemetry is the only reliable defense against rapid cleanup techniques.

### 3. Overcoming Telemetry Gaps (The `Copy-Item` Blind Spot)
During the design of Rule C4 (Collection), a significant telemetry gap was identified: native PowerShell cmdlets like `Copy-Item` do not spawn child processes, meaning Sysmon Event ID 1 (Process Creation) will not fire. Relying solely on process trees would result in a false negative. The detection logic was adjusted to use Sysmon Event ID 11 (File Creation) as a fallback indicator. Monitoring for the creation of multiple files in staging directories (`C:\Windows\Temp\`) by `powershell.exe` successfully bridges this gap.

### 4. Limitations and Telemetry Requirements
While this pipeline achieved a 100% detection rate for this specific chain, a sophisticated attacker could evade it by obfuscating the PowerShell payload. Currently, the WMI `CommandLineTemplate` is visible, but the actual script content executed by that template is not fully captured. Enabling **PowerShell Script Block Logging (Event ID 4104)** is a mandatory next step for enterprise environments. This would allow analysts to inspect the de-obfuscated script content in memory, providing definitive proof of malicious intent beyond just the execution mechanism.

---

## How to Reproduce

1. **Environment Setup:** Deploy a Windows 10 VM and an Elastic Stack 9.x instance (Kibana Cloud or local Docker).
2. **Telemetry Configuration:** Install Sysmon v15.15 using the provided `sysmon-config.xml` to ensure coverage of EID 1, 3, 11, 13, 19, 20, 21, and 23.
3. **Ingestion:** Install Elastic Agent 9.3.1 and enroll it in a Fleet policy with Sysmon integration enabled.
4. **Rule Deployment:** Import the EQL rules from the `rules/` directory into the Kibana Detection Engine.
5. **Simulation:** Execute the `setup.bat` script as a standard user, followed by launching `notepad.exe` to trigger the WMI Consumer.
6. **Validation:** Observe the sequence of alerts firing in Kibana SIEM and the corresponding webhook notifications.

---

*Disclaimer: This project was developed strictly for educational and Blue Team research purposes. All attack simulations were executed in an isolated, controlled laboratory environment.*
