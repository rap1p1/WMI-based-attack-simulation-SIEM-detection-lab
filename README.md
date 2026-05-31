#  WMI Persistent-Based Attack Simulation & SIEM Detection Lab

 **DISCLAIMER:** This project is intended solely for defensive research (Blue Team / Detection Engineering). All techniques are simulated in an isolated lab environment. Do not use for real-world attacks.

##  Overview
Simulates a 7-phase attack chain on Windows 10 using Living-off-the-Land Binaries (LOLBins), spanning:
`Initial Access (encrypted RAR)` → `UAC Bypass` → `WMI Persistence` → `Collection/Exfiltration` → `Cleanup`

Simultaneously builds a set of **EQL Correlation Rules** on Elastic SIEM to detect the entire chain based on behavioral invariants.

## ️ Architecture
Windows 10 VM (Sysmon v15.15)
→ Elastic Agent 9.x
→ Kibana SIEM (EQL Rules)
→ Webhook → Telegram Bot Alert


##  Directory Structure
| Directory | Description |
|---|---|
| `scripts/` | `setup.bat` (UAC bypass), `payload.ps1` (WMI installer + exfiltration) |
| `config/` | `sysmon-config.xml` (Log source coverage) |
| `phishing/` | `landing_page.html` (Phishing landing page) |
| `docs/` | Full technical report |

##  Lab Deployment Guide
1. Prepare a Windows 10 VM + Elastic Agent Fleet + Sysmon
2. Apply Sysmon config: `sysmon64.exe -c config/sysmon-config-v3.xml`
3. Edit `scripts/payload.ps1`: replace `<YOUR_TELEGRAM_BOT_TOKEN>` & `<YOUR_CHAT_ID>` with your credentials
4. Run `scripts/setup.bat` with **standard user privileges**
5. Open `notepad.exe` to trigger the WMI Consumer
6. Observe real-time alerts in Kibana & Telegram

##  Detection Rules
| Rule | Technique | Sysmon Event Chain |
|------|-----------|-------------------|
| `C1` | UAC Bypass via Fodhelper | `EID 13 → 1 → 1` |
| `C2` | WMI Persistence Chain | `EID 19 → 20 → 21` |
| `C3` | WMI Consumer → Discovery | `EID 1 → 1` |
| `C4` | Collection → Archive → Exfiltration | `EID 11 → 11 → 3` |
| `C5` | Exfiltration → Indicator Removal | `EID 3 → 23` |

##  References
- **MITRE ATT&CK**: T1548.002, T1546.003, T1041, T1070.004
- **Elastic EQL Documentation**: https://www.elastic.co/guide/en/security/current/eql.html
- **Sysmon Official**: https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon
- **SigmaHQ Rules**: https://github.com/SigmaHQ/sigma
