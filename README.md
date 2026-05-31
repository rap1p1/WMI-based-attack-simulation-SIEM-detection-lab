# 🛡️ WMI-Based APT Simulation & SIEM Detection Lab

> ⚠️ **DISCLAIMER**: Dự án này chỉ phục vụ mục đích **nghiên cứu phòng thủ (Blue Team / Detection Engineering)**. Toàn bộ kỹ thuật được mô phỏng trong môi trường lab isolated. Không sử dụng cho mục đích tấn công thực tế.

## 📖 Tổng quan
Mô phỏng chuỗi tấn công APT 7 phases trên Windows 10 sử dụng LOLBins, từ Initial Access (RAR encrypted) → UAC Bypass → WMI Persistence → Collection/Exfiltration → Cleanup. 
Đồng thời xây dựng bộ **EQL Correlation Rules** trên Elastic SIEM để phát hiện toàn bộ chain dựa trên behavioral invariants.

## ️ Kiến trúc
Windows 10 VM (Sysmon v15.15)
→ Elastic Agent 9.x
→ Kibana SIEM (EQL Rules)
→ Webhook → Telegram Bot Alert

## 📁 Cấu trúc thư mục
| Thư mục | Mô tả |
|---------|-------|
| `scripts/` | `setup.bat` (UAC bypass), `payload.ps1` (WMI installer + exfil) |
| `config/` | `sysmon-config-v3.xml` (Log source coverage) |
| `phishing/` | `index.html` (Landing page giả mạo) |
| `docs/` | Báo cáo kỹ thuật đầy đủ |

## 🚀 Hướng dẫn triển khai (Lab)
1. Chuẩn bị Windows 10 VM + Elastic Agent Fleet + Sysmon
2. Áp dụng config: `sysmon64.exe -c config/sysmon-config-v3.xml`
3. Chỉnh sửa `scripts/payload.ps1`: thay `<YOUR_TELEGRAM_BOT_TOKEN>` & `<YOUR_CHAT_ID>`
4. Chạy `scripts/setup.bat` với quyền user thường
5. Mở `notepad.exe` để trigger WMI Consumer
6. Quan sát alert trên Kibana & Telegram

##  Detection Rules
- `C1`: UAC Bypass via Fodhelper (EID 13→1→1)
- `C2`: WMI Persistence Chain (EID 19→20→21)
- `C3`: WMI Consumer → Discovery (EID 1→1)
- `C4`: Collection → Archive → Exfil (EID 11→11→3)
- `C5`: Exfil → Indicator Removal (EID 3→23)

## 📚 Tài liệu tham khảo
- MITRE ATT&CK: T1548.002, T1546.003, T1041, T1070.004
- Elastic EQL Documentation: https://www.elastic.co/guide/en/security/current/eql.html
- Sysmon Official: https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon
- SigmaHQ Rules: https://github.com/SigmaHQ/sigma