<#
.SYNOPSIS
    Windows 11 kurulum sonrasi otomatik yapilandirma scripti.

.DESCRIPTION
    Yeni kurulan bir Windows 11 makinede elle yapilan ayarlari otomatiklestirir:
    taskbar/explorer duzeni, masaustu ikonlari, gereksiz UWP uygulamalarinin
    kaldirilmasi, gizlilik/telemetri ayarlari, ofis odakli performans ayarlari,
    donanim sagligi raporu (batarya + disk), Windows/surucu guncellemesi, uretici
    surucu araci ve winget ile uygulama kurulumu (Chrome resmi MSI ile en son surum).

    Performans ayarlari OFIS bilgisayari icin secildi: gorsel efekt/animasyon
    kapatma, saydamlik kapatma, masaustunde yuksek guc plani (laptopta dokunulmaz),
    otomatik depo temizleme. Oyun odakli tweak'ler (HAGS, shader cache, frame cap)
    bilerek DAHIL EDILMEDI -> ofiste getirisi yok, riski var.

    Per-user (HKCU) ayarlar hem o an giris yapmis tum kullanicilara hem de
    Default User hive'ina yazilir. Boylece SYSTEM baglaminda (NinjaOne, GPO,
    Intune, MDT) calistirildiginda da dogru sonuc verir ve makineye sonradan
    eklenen yeni kullanicilar da ayni ayarlari devralir.

.PARAMETER DryRun
    Hicbir degisiklik yapmaz, sadece ne yapacagini loglar.

.PARAMETER SkipApps
    winget ile uygulama kurulumunu atlar.

.EXAMPLE
    .\Win11-PostInstall.ps1
    .\Win11-PostInstall.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File .\Win11-PostInstall.ps1 -SkipApps

.NOTES
    Yonetici hakki gerekir. Script kendini otomatik yukseltir.
    Sonunda explorer.exe yeniden baslatilir.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipApps,
    [switch]$NoRestartExplorer
)

#region ============================ AYARLAR ============================
# Buradaki $true / $false degerlerini degistirerek scripti kendine gore ayarla.

$Config = @{
    # --- Taskbar / Gorev cubugu ---
    TaskbarSolaHizala          = $false  # $true: sola al (Win10 gibi) · $false: ortada birak (Win11 varsayilan)
    AramaKutusunuKaldir        = $true   # Baslat yanindaki arama kutusunu tamamen gizle
    GorevGorunumunuKaldir      = $true   # Task View butonu
    WidgetlariKaldir           = $true   # Hava durumu / haberler widget'i
    ChatKaldir                 = $true   # Teams (Chat) ikonu
    CopilotKaldir              = $true   # Copilot butonu + politika
    SaniyeGoster               = $false  # Saatte saniyeyi goster
    SagTikEndTask              = $true   # Taskbar sag tik menusune "End task" ekle

    # --- Masaustu ---
    MasaustuBuBilgisayar       = $true   # "Bu bilgisayar" ikonunu masaustune ekle

    # --- Baslat menusu ---
    StartWebAramaKapat         = $true   # Bing / web sonuclarini kapat
    StartOnerileriKapat        = $true   # "Onerilenler" bolumunu bosalt
    StartDahaFazlaPin          = $true   # Layout: daha fazla pin, daha az oneri

    # --- Dosya Gezgini ---
    DosyaUzantisiGoster        = $true
    GizliDosyaGoster           = $true
    KorumaliSistemDosyasiGoster= $false  # Dikkat: cok fazla dosya gorunur
    BuBilgisayaraAc            = $true   # Gezgin "Bu bilgisayar" ile acilsin
    KlasikSagTikMenu           = $true   # Win11'in "Daha fazla secenek" menusunu devre disi birak
    TamYolBaslikta             = $true
    OneDriveBildirimKapat      = $true   # "Sync provider notifications" reklamlari

    # --- Gizlilik ---
    TelemetriKisitla           = $true
    ReklamKimligiKapat         = $true
    OnerileriIpuclariKapat     = $true   # Kilit ekrani / Baslat / bildirim reklamlari
    AktiviteGecmisiKapat       = $true
    RecallKapat                = $true   # Windows AI / Recall veri analizi

    # --- Sistem ---
    UzunYolDestegi             = $true   # MAX_PATH 260 limitini kaldir
    HizliBaslatmaKapat         = $true   # Fast Startup (dual boot / servis icin sorunlu)
    YapiskanTuslarKapat        = $true   # 5 kez Shift uyarisi
    HibernasyonKapat           = $false  # Laptop'ta $false birak
    SaatDilimiOtomatik         = $true

    # --- Ofis performansi (guvenli, geri alinabilir; oyun tweak'leri BILEREK yok) ---
    GorselEfektlerPerformans   = $true   # Animasyon/golge kapat -> arayuz aninda acilir (yazi netligi KORUNUR)
    SaydamlikKapat             = $true   # Transparency efektini kapat (hafif GPU/islemci tasarrufu)
    OfisGucPlani               = $true   # Masaustunde Yuksek Performans; LAPTOP'ta Dengeli birakilir (pil/isi)
    DepoTemizlemeOtomatik      = $true   # Storage Sense: gecici dosyalari otomatik temizle
    SysMainKapat               = $false  # SSD'de disk yukunu azaltabilir; emin degilsen $false birak
    AramaIndeksiKapat          = $false  # OFISTE ACIK BIRAK -> dosya/e-posta aramasini hizlandirir

    # --- Donanim sagligi ---
    SaglikRaporu               = $true   # Batarya (laptop) + disk sagligi raporu + yorum

    # --- Denetim / kayit (sirket cihazi) ---
    USBDosyaDenetimi           = $true   # USB'ye kopyalanan/okunan dosyalari Guvenlik gunlugune yaz (Event 4663)
    SilmeDenetimiKlasor        = ''       # Bu klasorde silmeler denetlensin (bos=kapali). Orn: 'D:\Ortak'

    # --- Temizlik ---
    BloatwareKaldir            = $true

    # --- Guncelleme (kurulum sonunda calisir, uzun surebilir) ---
    WindowsUpdate              = $true   # Eksik Windows guncellemelerini indir + kur
    SuruculeriGuncelle         = $true   # Windows Update uzerinden surucu guncellemeleri
    OemSurucuAraci             = $true   # Ureticinin resmi surucu aracini kur (Dell/HP/Lenovo/Intel)
}

# Chrome ayri kuruluyor (asagidaki KurChrome) — winget'in Chrome paketi Google
# installer'i ayni URL'de guncelledigi icin sik sik "hash uyusmuyor" hatasi verir.
# Resmi Enterprise MSI her zaman en son surumu makine geneli kurar.
$Config_KurChrome = $true

# winget ile kurulacak uygulamalar (winget id)
$Apps = @(
    '7zip.7zip'
    'Notepad++.Notepad++'
    'VideoLAN.VLC'
    'Microsoft.PowerShell'
    # 'Mozilla.Firefox'
    # 'Adobe.Acrobat.Reader.64-bit'
    # 'Microsoft.VisualStudioCode'
    # 'WinSCP.WinSCP'
    # 'PuTTY.PuTTY'
    # 'AnyDeskSoftwareGmbH.AnyDesk'
)

# Kaldirilacak UWP uygulamalar (paket adinda gecen ifade)
$Bloatware = @(
    'Clipchamp.Clipchamp'
    'Microsoft.3DBuilder'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingSearch'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.Messaging'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MixedReality.Portal'
    'Microsoft.News'
    'Microsoft.Office.OneNote'
    'Microsoft.OneConnect'
    'Microsoft.People'
    'Microsoft.Print3D'
    'Microsoft.SkypeApp'
    'Microsoft.Todos'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'MicrosoftTeams'
    'MSTeams'
    'Microsoft.Copilot'
    'Microsoft.549981C3F5F10'      # Cortana
    'MicrosoftCorporationII.QuickAssist'
)
# NOT: Kalmasi gerekenler bilerek listede yok ->
# Photos, Calculator, Store, Terminal, Notepad, Paint, ScreenSketch, WebpImage,
# VCLibs/UI.Xaml (bagimlilik), SecHealthUI (Defender arayuzu)

#endregion

#region ========================= ALTYAPI =========================

$ErrorActionPreference = 'Stop'
$script:LogFile = Join-Path $env:ProgramData "Win11-PostInstall_$(Get-Date -f yyyyMMdd-HHmmss).log"
$script:Degisen = 0
$script:Hata    = 0

function Write-Log {
    param([string]$Msg, [ValidateSet('INFO','OK','WARN','ERR','SKIP')][string]$Level = 'INFO')
    $line = "[{0}] [{1,-4}] {2}" -f (Get-Date -f 'HH:mm:ss'), $Level, $Msg
    $color = switch ($Level) { 'OK'{'Green'} 'WARN'{'Yellow'} 'ERR'{'Red'} 'SKIP'{'DarkGray'} default{'Gray'} }
    Write-Host $line -ForegroundColor $color
    try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch {}
}

function Write-Baslik {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 64) -ForegroundColor Cyan
    try { Add-Content -Path $script:LogFile -Value "`n=== $Text ===" -Encoding UTF8 } catch {}
}

# Yonetici kontrolu + otomatik yukseltme
$kimlik = [Security.Principal.WindowsIdentity]::GetCurrent()
$yonetici = ([Security.Principal.WindowsPrincipal]$kimlik).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $yonetici) {
    Write-Host "Yonetici hakki gerekiyor, yeniden baslatiliyor..." -ForegroundColor Yellow
    # Switch parametreleri $PSBoundParameters'tan yeniden kurulur. UnboundArguments
    # bunlari icermez (tanimli olduklari icin bound olurlar) -> yukseltme sonrasi
    # -DryRun/-SkipApps sessizce dusup istenmeyen degisiklik yapilirdi.
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        if ($PSBoundParameters[$k] -is [switch] -and $PSBoundParameters[$k]) { $argList += "-$k" }
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

<#
    Set-Reg: tek bir registry degerini guvenli sekilde yazar.
#>
function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord','QWord','String','ExpandString','Binary')][string]$Type = 'DWord'
    )
    try {
        if ($DryRun) { Write-Log "[DRY] $Path\$Name = $Value" 'SKIP'; return }
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        $script:Degisen++
    }
    catch {
        Write-Log "Yazilamadi: $Path\$Name -> $($_.Exception.Message)" 'ERR'
        $script:Hata++
    }
}

<#
    Invoke-ForEachUserHive: verilen scriptblock'u tum gercek kullanici hive'lari
    ve Default User hive'i icin calistirir. Scriptblock'a hive kok yolu ($args[0])
    parametre olarak gecer, orn: "Registry::HKEY_USERS\S-1-5-21-..."
#>
function Invoke-ForEachUserHive {
    param([Parameter(Mandatory)][scriptblock]$Script)

    $hedefler = @()

    # 1) Yuklu (giris yapmis) kullanici hive'lari
    Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-[\d\-]+$' -and $_.PSChildName -notmatch '_Classes$' } |
        ForEach-Object { $hedefler += "Registry::HKEY_USERS\$($_.PSChildName)" }

    foreach ($h in $hedefler) { & $Script $h }

    # 2) Default User hive'i -> bundan sonra olusturulacak profiller
    $defDat = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if ((Test-Path $defDat) -and -not $DryRun) {
        $yuklendi = $false
        try {
            $null = reg.exe load "HKU\W11Default" "$defDat" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $yuklendi = $true
                & $Script "Registry::HKEY_USERS\W11Default"
            }
        }
        catch { Write-Log "Default hive islenemedi: $($_.Exception.Message)" 'WARN' }
        finally {
            if ($yuklendi) {
                [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 400
                $null = reg.exe unload "HKU\W11Default" 2>&1
            }
        }
    }
    elseif ($DryRun) { & $Script "Registry::HKEY_USERS\W11Default(DRY)" }
}

# Cihaz laptop mu? Sasi tipi (ChassisTypes) tasinabilir sinifindaysa ya da
# batarya varsa laptop kabul edilir.
function Test-Laptop {
    try {
        $laptopSasi = 8,9,10,11,12,14,18,21,30,31,32   # portable/laptop/notebook/tablet
        $sasi = (Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes
        foreach ($c in $sasi) { if ($laptopSasi -contains [int]$c) { return $true } }
    } catch {}
    return [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
}

<#
    Show-BatteryHealth: powercfg batarya raporundan tasarim kapasitesi ve mevcut
    tam sarj kapasitesini okuyup saglik yuzdesini yorumlar. Yalniz laptoplarda.
#>
function Show-BatteryHealth {
    $xml = Join-Path $env:TEMP "batt_$PID.xml"
    try {
        powercfg.exe /batteryreport /xml /output "$xml" | Out-Null
        if (-not (Test-Path $xml)) { Write-Log "Batarya raporu olusturulamadi" 'WARN'; return }
        $icerik = Get-Content $xml -Raw

        # Bir cihazda birden fazla batarya olabilir -> topla
        $tasarim = ([regex]::Matches($icerik, '<DesignCapacity>(\d+)</DesignCapacity>') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum).Sum
        $tam     = ([regex]::Matches($icerik, '<FullChargeCapacity>(\d+)</FullChargeCapacity>') | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Sum).Sum
        $dongu   = [regex]::Match($icerik, '<CycleCount>(\d+)</CycleCount>').Groups[1].Value

        if (-not $tasarim -or -not $tam) { Write-Log "Batarya kapasite verisi okunamadi (masaustu/desteklemeyen cihaz olabilir)" 'WARN'; return }

        $saglik = [math]::Round(($tam / $tasarim) * 100)
        Write-Log ("Batarya tasarim kapasitesi : {0:N0} mWh" -f $tasarim)
        Write-Log ("Batarya mevcut kapasitesi  : {0:N0} mWh" -f $tam)
        if ($dongu) { Write-Log "Sarj dongusu               : $dongu" }
        Write-Log  "Batarya sagligi            : %$saglik"

        if     ($saglik -ge 80) { Write-Log "YORUM: Batarya saglikli (>=%80). Bir sorun yok." 'OK' }
        elseif ($saglik -ge 60) { Write-Log "YORUM: Batarya normal yaslanmis (%60-80). Takip edin, aciliyet yok." 'INFO' }
        elseif ($saglik -ge 40) { Write-Log "YORUM: Batarya yipranmis (%40-60). Sarj suresi belirgin kisalmistir." 'WARN' }
        else                    { Write-Log "YORUM: Batarya kritik (<%40). Degisim dusunulmeli." 'ERR' }
    }
    catch { Write-Log "Batarya sagligi okunamadi: $($_.Exception.Message)" 'WARN' }
    finally { Remove-Item $xml -ErrorAction SilentlyContinue }
}

<#
    Show-DiskHealth: fiziksel disklerin SMART saglik durumunu ve (SSD icin)
    asinma/omur ile sicaklik degerlerini yorumlar.
#>
function Show-DiskHealth {
    try {
        $diskler = Get-PhysicalDisk -ErrorAction Stop
    } catch { Write-Log "Disk bilgisi alinamadi: $($_.Exception.Message)" 'WARN'; return }

    foreach ($d in $diskler) {
        $boyutGB = [math]::Round($d.Size / 1GB)
        $tur = $d.MediaType   # SSD / HDD / Unspecified
        Write-Log ("Disk: {0} ({1} GB, {2})" -f $d.FriendlyName, $boyutGB, $tur)

        $durum = "$($d.HealthStatus)"   # Healthy / Warning / Unhealthy
        switch ($durum) {
            'Healthy' { Write-Log "  SMART durumu: Healthy" 'OK' }
            'Warning' { Write-Log "  SMART durumu: Warning -> yedek alin, disk izlenmeli" 'WARN' }
            default   { Write-Log "  SMART durumu: $durum -> ACIL yedek + degisim" 'ERR' }
        }

        $rc = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($rc) {
            if ($null -ne $rc.Wear) {
                $kalan = 100 - [int]$rc.Wear
                $seviye = if ($rc.Wear -lt 20) {'OK'} elseif ($rc.Wear -lt 80) {'INFO'} else {'WARN'}
                Write-Log ("  SSD omru: ~%{0} kaldi (asinma %{1})" -f $kalan, [int]$rc.Wear) $seviye
            }
            if ($rc.Temperature) {
                $ts = if ($rc.Temperature -lt 55) {'OK'} elseif ($rc.Temperature -lt 70) {'INFO'} else {'WARN'}
                Write-Log ("  Sicaklik: {0} C" -f [int]$rc.Temperature) $ts
            }
            if ($rc.ReadErrorsUncorrected -gt 0 -or $rc.WriteErrorsUncorrected -gt 0) {
                Write-Log ("  Duzeltilemeyen hata: okuma {0}, yazma {1} -> disk yipraniyor" -f $rc.ReadErrorsUncorrected, $rc.WriteErrorsUncorrected) 'WARN'
            }
        }
    }
}

#endregion

Write-Baslik "Windows 11 Post-Install"
Write-Log "Makine  : $env:COMPUTERNAME"
Write-Log "Kullanici: $($kimlik.Name)"
Write-Log "Surum   : $((Get-CimInstance Win32_OperatingSystem).Caption) / Build $([Environment]::OSVersion.Version.Build)"
Write-Log "Log     : $script:LogFile"
if ($DryRun) { Write-Log "DRY RUN modu - hicbir degisiklik yapilmayacak" 'WARN' }

# Laptop mu? Guc plani ve batarya raporu buna gore davranir.
$script:Laptop = Test-Laptop
Write-Log "Cihaz tipi: $(if ($script:Laptop) {'Laptop / tasinabilir'} else {'Masaustu / sabit'})"

#region ==================== DONANIM SAGLIGI ====================

if ($Config.SaglikRaporu) {
    Write-Baslik "Donanim sagligi"
    if ($script:Laptop) { Show-BatteryHealth }
    else { Write-Log "Masaustu cihaz -> batarya raporu atlandi" 'SKIP' }
    Show-DiskHealth
}

#endregion

#region ==================== PER-USER AYARLAR ====================

Write-Baslik "Taskbar / Baslat / Gezgin ayarlari"

Invoke-ForEachUserHive {
    param($U)

    $Adv      = "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $Search   = "$U\Software\Microsoft\Windows\CurrentVersion\Search"
    $CDM      = "$U\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $PolExp   = "$U\Software\Policies\Microsoft\Windows\Explorer"

    # --- Taskbar ---
    # Hiza her zaman yazilir (0=sol, 1=orta): onceki calistirmada sola alinmissa
    # $false yapilinca geri ortalanabilsin. Sadece atlamak eski degeri birakirdi.
    Set-Reg $Adv 'TaskbarAl' $(if ($Config.TaskbarSolaHizala) { 0 } else { 1 })
    if ($Config.AramaKutusunuKaldir) { Set-Reg $Search 'SearchboxTaskbarMode' 0 }   # 0=gizli 1=ikon 2=kutu
    if ($Config.GorevGorunumunuKaldir) { Set-Reg $Adv 'ShowTaskViewButton' 0 }
    if ($Config.WidgetlariKaldir)    { Set-Reg $Adv 'TaskbarDa' 0 }
    if ($Config.ChatKaldir)          { Set-Reg $Adv 'TaskbarMn' 0 }
    if ($Config.CopilotKaldir) {
        Set-Reg $Adv 'ShowCopilotButton' 0
        Set-Reg "$U\Software\Policies\Microsoft\Windows\WindowsCopilot" 'TurnOffWindowsCopilot' 1
    }
    if ($Config.SaniyeGoster)        { Set-Reg $Adv 'ShowSecondsInSystemClock' 1 }
    if ($Config.SagTikEndTask)       { Set-Reg "$Adv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1 }

    # --- Masaustu ikonlari ---
    # "Bu bilgisayar" ikonu (CLSID). 0=goster, 1=gizle. Hem klasik hem yeni
    # masaustu anahtarina yazilir ki her iki kabuk yolunda da gorunsun.
    if ($Config.MasaustuBuBilgisayar) {
        $buPC = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
        Set-Reg "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"  $buPC 0
        Set-Reg "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" $buPC 0
    }

    # --- Baslat menusu ---
    if ($Config.StartWebAramaKapat) {
        Set-Reg $Search 'BingSearchEnabled' 0
        Set-Reg $Search 'CortanaConsent'    0
        Set-Reg $PolExp 'DisableSearchBoxSuggestions' 1
    }
    if ($Config.StartOnerileriKapat) {
        Set-Reg $Adv 'Start_TrackDocs'  0
        Set-Reg $Adv 'Start_TrackProgs' 0
        Set-Reg $Adv 'Start_IrisRecommendations' 0
    }
    if ($Config.StartDahaFazlaPin) { Set-Reg $Adv 'Start_Layout' 1 }  # 0=varsayilan 1=daha fazla pin 2=daha fazla oneri

    # --- Dosya Gezgini ---
    if ($Config.DosyaUzantisiGoster)         { Set-Reg $Adv 'HideFileExt' 0 }
    if ($Config.GizliDosyaGoster)            { Set-Reg $Adv 'Hidden' 1 }
    if ($Config.KorumaliSistemDosyasiGoster) { Set-Reg $Adv 'ShowSuperHidden' 1 }
    if ($Config.BuBilgisayaraAc)             { Set-Reg $Adv 'LaunchTo' 1 }
    if ($Config.TamYolBaslikta)              { Set-Reg "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" 'FullPath' 1 }
    if ($Config.OneDriveBildirimKapat)       { Set-Reg $Adv 'ShowSyncProviderNotifications' 0 }

    # Win11 "Daha fazla secenek goster" ara menusunu kaldir -> klasik sag tik
    if ($Config.KlasikSagTikMenu -and -not $DryRun) {
        $clsid = "$U\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        try {
            if (-not (Test-Path $clsid)) { New-Item -Path $clsid -Force | Out-Null }
            Set-ItemProperty -Path $clsid -Name '(default)' -Value '' -Force
        } catch { }
    }

    # --- Gizlilik (per-user) ---
    if ($Config.ReklamKimligiKapat) {
        Set-Reg "$U\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" 'Enabled' 0
    }
    if ($Config.OnerileriIpuclariKapat) {
        foreach ($v in @(
            'SubscribedContent-338388Enabled'   # Baslat onerileri
            'SubscribedContent-338389Enabled'   # Ipuclari / oneriler
            'SubscribedContent-310093Enabled'   # Hosgeldin ekrani
            'SubscribedContent-338393Enabled'   # Ayarlar onerileri
            'SubscribedContent-353694Enabled'
            'SubscribedContent-353696Enabled'
            'SubscribedContent-88000326Enabled' # Kilit ekrani Spotlight reklamlari
            'SystemPaneSuggestionsEnabled'
            'SilentInstalledAppsEnabled'        # Sessiz "onerilen" uygulama kurulumu
            'PreInstalledAppsEnabled'
            'OemPreInstalledAppsEnabled'
            'SoftLandingEnabled'
            'RotatingLockScreenOverlayEnabled'
        )) { Set-Reg $CDM $v 0 }
    }
    if ($Config.YapiskanTuslarKapat) {
        Set-Reg "$U\Control Panel\Accessibility\StickyKeys"    'Flags' '506' 'String'
        Set-Reg "$U\Control Panel\Accessibility\Keyboard Response" 'Flags' '122' 'String'
        Set-Reg "$U\Control Panel\Accessibility\ToggleKeys"    'Flags' '58'  'String'
    }

    # --- Ofis performansi (per-user) ---
    # Gorsel efektler: "en iyi performans" ama YAZI NETLIGI (ClearType) korunur.
    # VisualFXSetting=3 (ozel) + animasyon/golge kapatilir; FontSmoothing'e dokunulmaz.
    if ($Config.GorselEfektlerPerformans) {
        Set-Reg "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" 'VisualFXSetting' 3
        Set-Reg "$U\Control Panel\Desktop\WindowMetrics" 'MinAnimate' '0' 'String'
        Set-Reg $Adv 'TaskbarAnimations'    0
        Set-Reg $Adv 'ListviewAlphaSelect'  0
        Set-Reg $Adv 'ListviewShadow'       0
    }
    if ($Config.SaydamlikKapat) {
        Set-Reg "$U\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'EnableTransparency' 0
    }
}
Write-Log "Per-user ayarlar uygulandi (aktif kullanicilar + Default profil)" 'OK'

#endregion

#region ==================== MAKINE AYARLARI ====================

Write-Baslik "Sistem ve gizlilik ayarlari"

if ($Config.TelemetriKisitla) {
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    # Not: Home/Pro'da minimum "Basic" seviyesidir, 0 tam olarak uygulanmayabilir.
    Write-Log "Telemetri kisitlandi" 'OK'
}

if ($Config.AktiviteGecmisiKapat) {
    $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-Reg $sys 'EnableActivityFeed' 0
    Set-Reg $sys 'PublishUserActivities' 0
    Set-Reg $sys 'UploadUserActivities' 0
    Write-Log "Aktivite gecmisi kapatildi" 'OK'
}

if ($Config.WidgetlariKaldir) {
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Write-Log "Widget/haberler politika ile kapatildi" 'OK'
}

if ($Config.RecallKapat) {
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Write-Log "Recall (AI veri analizi) kapatildi" 'OK'
}

if ($Config.UzunYolDestegi) {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
    Write-Log "Uzun dosya yolu destegi acildi" 'OK'
}

if ($Config.HizliBaslatmaKapat) {
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
    Write-Log "Hizli baslatma kapatildi" 'OK'
}

if ($Config.SaatDilimiOtomatik -and -not $DryRun) {
    # Saat dilimini bolgeden bul + saati NTP'den senkronla.
    # "Otomatik saat dilimi" (tzautoupdate) cografi konuma dayanir; konum servisi
    # kapaliysa calismaz. Bu yuzden once bolgeye gore ACIKCA ayarlanir (guvenilir),
    # sonra otomatik guncelleme de acilir (tasinirsa kendi duzeltsin).
    try {
        # Windows bolge/GeoID -> saat dilimi. Bilinen bolgeler eslenir, digerinde
        # otomatik tespit + NTP devreye girer.
        $geoTz = @{ 235 = 'Turkey Standard Time'; 244 = 'Eastern Standard Time' } # 235=Turkiye
        $geo = try { (Get-WinHomeLocation -ErrorAction Stop).GeoId } catch { $null }
        if ($geo -and $geoTz.ContainsKey([int]$geo)) {
            Set-TimeZone -Id $geoTz[[int]$geo] -ErrorAction Stop
            Write-Log "Saat dilimi bolgeye gore ayarlandi: $($geoTz[[int]$geo])" 'OK'
        } else {
            Set-TimeZone -Id 'Turkey Standard Time' -ErrorAction SilentlyContinue
            Write-Log "Bolge okunamadi -> Turkiye saat dilimi varsayildi" 'INFO'
        }

        # Konum servisi + otomatik saat dilimi (tasinan cihaz kendini duzeltsin)
        Set-Service tzautoupdate -StartupType Automatic -ErrorAction SilentlyContinue

        # Saati NTP ile senkronla -> guncel yerel saat
        Set-Service w32time -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service w32time -ErrorAction SilentlyContinue
        w32tm.exe /config /manualpeerlist:"time.windows.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /update 2>&1 | Out-Null
        w32tm.exe /resync /force 2>&1 | Out-Null
        Write-Log "Saat NTP ile senkronlandi (guncel yerel saat)" 'OK'
    } catch { Write-Log "Saat/dilim ayarlanamadi: $($_.Exception.Message)" 'WARN' }
}

if ($Config.HibernasyonKapat -and -not $DryRun) {
    powercfg.exe /hibernate off | Out-Null
    Write-Log "Hibernasyon kapatildi (hiberfil.sys silindi)" 'OK'
}

if ($Config.OfisGucPlani -and -not $DryRun) {
    # Laptop'ta Yuksek Performans zorlamak pili ve isiyi kotu etkiler -> Dengeli
    # birakilir. Masaustunde islemci uyku (core parking) engellenip menu/uygulama
    # acilislarindaki mikro gecikmeler kaldirilir.
    if ($script:Laptop) {
        Write-Log "Laptop -> guc plani Dengeli birakildi (pil/isi icin dogru secim)" 'INFO'
    } else {
        try {
            powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null  # High performance
            Write-Log "Guc plani: Yuksek performans (masaustu)" 'OK'
        } catch { Write-Log "Guc plani degistirilemedi" 'WARN' }
    }
}

if ($Config.DepoTemizlemeOtomatik) {
    # Storage Sense: gecici dosyalari ve geri donusum kutusunu otomatik temizler.
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' 'AllowStorageSenseGlobal' 1
    Write-Log "Otomatik depo temizleme (Storage Sense) acildi" 'OK'
}

if ($Config.SysMainKapat -and -not $DryRun) {
    # SSD'li sistemlerde SysMain (SuperFetch) bazen gereksiz disk G/C uretir.
    # Varsayilan $false -> yalniz bilinerek acildiginda calisir.
    try {
        Stop-Service SysMain -Force -ErrorAction SilentlyContinue
        Set-Service  SysMain -StartupType Disabled -ErrorAction Stop
        Write-Log "SysMain kapatildi (SSD icin)" 'OK'
    } catch { Write-Log "SysMain kapatilamadi: $($_.Exception.Message)" 'WARN' }
}

if ($Config.AramaIndeksiKapat -and -not $DryRun) {
    # DIKKAT ofis: kapatmak dosya/e-posta aramasini yavaslatir. Varsayilan $false.
    try {
        Stop-Service WSearch -Force -ErrorAction SilentlyContinue
        Set-Service  WSearch -StartupType Disabled -ErrorAction Stop
        Write-Log "Arama indeksleme kapatildi (Windows Search)" 'OK'
    } catch { Write-Log "WSearch kapatilamadi: $($_.Exception.Message)" 'WARN' }
}

#endregion

#region ==================== DENETIM / KAYIT ====================

# Sirket cihazinda "kim neyi USB'ye kopyaladi / neyi sildi" kaydi.
# ONEMLI: Bu kayitlar YEREL Guvenlik gunlugune yazilir. Uzun vadeli takip icin
# NinjaOne (veya bir log toplayici) ile merkezi olarak toplanmalidir; yoksa
# gunluk dolunca eski kayitlar doner.
if ($Config.USBDosyaDenetimi -and -not $DryRun) {
    Write-Baslik "USB dosya denetimi"
    # "Removable Storage" alt kategorisi tam bu is icin: USB/harici diske her
    # dosya erisimini otomatik denetler, klasor SACL'i gerekmez.
    # Sonuc: Guvenlik gunlugu Event ID 4663 (kim, hangi dosya, hangi surec).
    & auditpol.exe /set /subcategory:"Removable Storage" /success:enable /failure:enable | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "USB dosya erisimi denetimi acildi (Guvenlik gunlugu, Event 4663)" 'OK'
        Write-Log "Uzun vade: kayitlari NinjaOne'a aktarin, yerel gunluk sinirlidir" 'INFO'
    } else { Write-Log "USB denetimi acilamadi (auditpol exit $LASTEXITCODE)" 'WARN' }
}

# Silme denetimi bir KLASORE hedeflenir (tum diski denetlemek asiri gurultu uretir).
if ($Config.SilmeDenetimiKlasor -and -not $DryRun) {
    if (-not (Test-Path $Config.SilmeDenetimiKlasor)) {
        Write-Log "Silme denetimi klasoru yok: $($Config.SilmeDenetimiKlasor)" 'WARN'
    } else {
        Write-Baslik "Silme denetimi: $($Config.SilmeDenetimiKlasor)"
        & auditpol.exe /set /subcategory:"File System" /success:enable /failure:enable | Out-Null
        try {
            # SACL: Herkes icin silme islemlerini basari olarak denetle (Event 4660/4663)
            $acl = Get-Acl -Path $Config.SilmeDenetimiKlasor -Audit
            $kural = New-Object System.Security.AccessControl.FileSystemAuditRule(
                'Everyone', 'Delete,DeleteSubdirectoriesAndFiles',
                'ContainerInherit,ObjectInherit', 'None', 'Success')
            $acl.AddAuditRule($kural)
            Set-Acl -Path $Config.SilmeDenetimiKlasor -AclObject $acl
            Write-Log "Silme denetimi kuruldu (Event 4660)" 'OK'
        } catch { Write-Log "Silme denetimi kurulamadi: $($_.Exception.Message)" 'WARN' }
    }
}

#endregion

#region ==================== BLOATWARE ====================

if ($Config.BloatwareKaldir) {
    Write-Baslik "Gereksiz uygulamalarin kaldirilmasi"
    $kaldirilan = 0

    # ONEMLI: Get-AppxPackage -AllUsers ve ozellikle Get-AppxProvisionedPackage
    # yavas komutlardir (DISM/bilesen deposu taramasi). Eskiden bunlar 34 kalibin
    # HER BIRI icin ayri cagriliyordu -> ekran dakikalarca "takili" gorunuyordu.
    # Simdi ikisi de TEK KEZ okunup bellekte filtreleniyor.
    Write-Log "Yuklu paketler taraniyor (bir kez)..."
    $tumPaket = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Write-Log "Provision paketleri taraniyor (bir kez, biraz surebilir)..."
    $tumProv  = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    $toplam = $Bloatware.Count; $sayac = 0
    foreach ($app in $Bloatware) {
        $sayac++
        Write-Log ("[{0,2}/{1}] {2}" -f $sayac, $toplam, $app)
        try {
            foreach ($p in ($tumPaket | Where-Object Name -like "*$app*")) {
                if ($DryRun) { Write-Log "  [DRY] Kaldirilacak: $($p.Name)" 'SKIP'; continue }
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                Write-Log "  Kaldirildi: $($p.Name)" 'OK'
                $kaldirilan++
            }
            # Provisioned paket -> yeni kullanicilara bir daha kurulmasin
            foreach ($pp in ($tumProv | Where-Object DisplayName -like "*$app*")) {
                if ($DryRun) { Write-Log "  [DRY] Provision kaldirilacak: $($pp.DisplayName)" 'SKIP'; continue }
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction SilentlyContinue | Out-Null
                Write-Log "  Provision kaldirildi: $($pp.DisplayName)" 'OK'
            }
        }
        catch { Write-Log "  $app kaldirilamadi: $($_.Exception.Message)" 'WARN' }
    }
    Write-Log "Toplam $kaldirilan paket kaldirildi" 'OK'
}

#endregion

#region ==================== UYGULAMA KURULUMU ====================

if (-not $SkipApps -and $Apps.Count -gt 0) {
    Write-Baslik "Uygulama kurulumu (winget)"

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        # SYSTEM baglaminda winget PATH'te olmayabilir, elle bul
        $wp = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue |
              Sort-Object FullName -Descending | Select-Object -First 1
        if ($wp) { $winget = $wp.FullName } 
    } else { $winget = $winget.Source }

    if (-not $winget) {
        Write-Log "winget bulunamadi. App Installer'i Store'dan kurup tekrar calistir." 'WARN'
    }
    else {
        # Kaynak sozlesmesini kabul et
        & $winget source update --disable-interactivity 2>&1 | Out-Null

        foreach ($id in $Apps) {
            if ($DryRun) { Write-Log "[DRY] Kurulacak: $id" 'SKIP'; continue }
            Write-Log "Kuruluyor: $id ..."
            $out = & $winget install --id $id --exact --silent --scope machine `
                        --accept-package-agreements --accept-source-agreements `
                        --disable-interactivity 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Kuruldu: $id" 'OK'
            }
            elseif ("$out" -match 'already installed|zaten yuklu') {
                Write-Log "Zaten kurulu: $id" 'SKIP'
            }
            else {
                # Bazi paketler machine scope desteklemez, user scope dene
                $out2 = & $winget install --id $id --exact --silent `
                            --accept-package-agreements --accept-source-agreements `
                            --disable-interactivity 2>&1
                if ($LASTEXITCODE -eq 0) { Write-Log "Kuruldu (user scope): $id" 'OK' }
                else { Write-Log "Kurulamadi: $id (exit $LASTEXITCODE)" 'WARN'; $script:Hata++ }
            }
        }
    }
}

#endregion

#region ==================== CHROME (EN SON SURUM) ====================

if ($Config_KurChrome -and -not $SkipApps) {
    Write-Baslik "Google Chrome (en son surum)"

    # Once winget dene (varsa hizli ve temiz). Basarisiz olursa resmi MSI'a dus.
    $kuruldu = $false
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wg -and -not $DryRun) {
        $out = & $wg.Source install --id Google.Chrome --exact --silent --scope machine `
                    --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        if ($LASTEXITCODE -eq 0 -or "$out" -match 'already installed|zaten') {
            Write-Log "Chrome winget ile kuruldu/guncel" 'OK'; $kuruldu = $true
        } else {
            Write-Log "winget Chrome'u kuramadi (muhtemelen hash uyusmazligi), MSI'a geciliyor" 'WARN'
        }
    }

    # Resmi Enterprise MSI — her zaman en son surum, makine geneli, sessiz.
    if (-not $kuruldu) {
        $msiUrl = 'https://dl.google.com/tag/s/dl/chrome/install/googlechromestandaloneenterprise64.msi'
        $msi    = Join-Path $env:TEMP 'chrome_enterprise.msi'
        if ($DryRun) {
            Write-Log "[DRY] Chrome MSI indirilip kurulacak: $msiUrl" 'SKIP'
        } else {
            try {
                Write-Log "Chrome MSI indiriliyor..."
                $eskiPB = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $msiUrl -OutFile $msi -UseBasicParsing
                $ProgressPreference = $eskiPB

                $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
                    '/i', "`"$msi`"", '/qn', '/norestart'
                )
                if ($p.ExitCode -eq 0) { Write-Log "Chrome kuruldu (Enterprise MSI, en son surum)" 'OK' }
                else { Write-Log "Chrome MSI kurulumu basarisiz (exit $($p.ExitCode))" 'ERR'; $script:Hata++ }
            }
            catch { Write-Log "Chrome kurulamadi: $($_.Exception.Message)" 'ERR'; $script:Hata++ }
            finally { Remove-Item $msi -ErrorAction SilentlyContinue }
        }
    }
}

#endregion

#region ==================== WINDOWS + SURUCU GUNCELLEME ====================

# ARKA PLANDA calisir: guncelleme uzun surdugu icin script BEKLEMEZ. Guncelleme
# mantigi ayri bir gizli PowerShell surecine yazilir ve baslatilir; bu surec ana
# script kapansa da devam eder. Windows Update Agent COM API kullanir (harici
# modul yok, SYSTEM baglaminda guvenilir). Surucu guncellemeleri de WU'dan gelir.
if (($Config.WindowsUpdate -or $Config.SuruculeriGuncelle) -and -not $DryRun) {
    Write-Baslik "Windows ve surucu guncellemeleri (arka planda)"

    $wuScript = Join-Path $env:ProgramData 'Win11-PostInstall-Update.ps1'
    $wuLog    = Join-Path $env:ProgramData "Win11-Update_$(Get-Date -f yyyyMMdd-HHmmss).log"
    $suruculerDahil = [bool]$Config.SuruculeriGuncelle

    # Arka plan surecinin calistiracagi bagimsiz betik. $suruculerDahil degeri
    # buraya gomulur; ana scriptin degiskenlerine erisimi yoktur.
    $wuBody = @"
`$ErrorActionPreference = 'SilentlyContinue'
function L(`$m){ "[{0}] {1}" -f (Get-Date -f 'HH:mm:ss'), `$m | Add-Content -Path '$wuLog' -Encoding UTF8 }
`$suruculerDahil = `$$suruculerDahil
try {
    L 'Guncelleme araniyor...'
    `$s = New-Object -ComObject Microsoft.Update.Session
    `$sonuc = `$s.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
    if (`$sonuc.Updates.Count -eq 0) { L 'Sistem guncel, guncelleme yok'; return }
    `$col = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach (`$u in `$sonuc.Updates) {
        `$surucuMu = (`$u.Categories | Where-Object { `$_.Name -match 'Driver|Surucu' }).Count -gt 0
        if (`$surucuMu -and -not `$suruculerDahil) { continue }
        if (-not `$u.EulaAccepted) { try { `$u.AcceptEula() } catch {} }
        [void]`$col.Add(`$u); L ('Sirada: ' + `$u.Title)
    }
    if (`$col.Count -eq 0) { L 'Uygulanacak guncelleme yok'; return }
    L ('' + `$col.Count + ' guncelleme indiriliyor...')
    `$d = `$s.CreateUpdateDownloader(); `$d.Updates = `$col; [void]`$d.Download()
    L 'Kuruluyor...'
    `$i = `$s.CreateUpdateInstaller(); `$i.Updates = `$col; `$ir = `$i.Install()
    L ('Sonuc kodu: ' + `$ir.ResultCode + '  YenidenBaslatma: ' + `$ir.RebootRequired)
} catch { L ('HATA: ' + `$_.Exception.Message) }
"@
    try {
        Set-Content -Path $wuScript -Value $wuBody -Encoding UTF8
        # -Wait YOK -> fire-and-forget. Ayri surec, ana script kapansa da surer.
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$wuScript`""
        )
        Write-Log "Guncelleme arka planda BASLATILDI (beklenmiyor)" 'OK'
        Write-Log "Ilerleme: $wuLog" 'INFO'
    } catch { Write-Log "Guncelleme arka plan sureci baslatilamadi: $($_.Exception.Message)" 'WARN' }
}
elseif ($DryRun) {
    Write-Log "[DRY] Windows/surucu guncellemesi arka planda baslatilacak" 'SKIP'
}

#endregion

#region ==================== OEM SURUCU ARACI ====================

# En son ve DOGRU surucu, ureticinin kendi aracindan gelir (WU her zaman en yeniyi
# vermez). Makinenin markasi okunur, resmi guncelleme araci winget ile kurulur.
# Dell'de ayrica komut satiriyla (dcu-cli) suruculer otomatik uygulanabilir.
if ($Config.OemSurucuAraci -and -not $SkipApps) {
    Write-Baslik "Uretici surucu araci"

    $marka = ''
    try { $marka = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Manufacturer } catch {}
    Write-Log "Uretici: $marka"

    # Marka -> resmi winget araci. Substring eslesme (ornek: 'Dell Inc.').
    $arac = switch -Regex ($marka) {
        'Dell'              { 'Dell.CommandUpdate';   break }
        'HP|Hewlett'        { 'HP.Support.Assistant'; break }
        'Lenovo'            { 'Lenovo.SystemUpdate';  break }
        'Microsoft'         { '';                     break }  # Surface -> WU yeterli
        default             { '' }
    }

    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $arac) {
        Write-Log "Bu marka icin ozel arac yok; suruculer Windows Update'ten gelir" 'INFO'
    }
    elseif (-not $wg) {
        Write-Log "winget yok, OEM araci kurulamadi: $arac" 'WARN'
    }
    elseif ($DryRun) {
        Write-Log "[DRY] OEM araci kurulacak: $arac" 'SKIP'
    }
    else {
        Write-Log "Kuruluyor: $arac ..."
        & $wg.Source install --id $arac --exact --silent --accept-package-agreements `
              --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log "OEM araci kuruldu: $arac" 'OK' }
        else { Write-Log "OEM araci kurulamadi (exit $LASTEXITCODE); elle kurulabilir" 'WARN' }

        # Dell: dcu-cli ile suruculeri otomatik tara + uygula (yeniden baslatma yok).
        if ($marka -match 'Dell') {
            $dcu = Get-ChildItem "$env:ProgramFiles*\Dell\CommandUpdate\dcu-cli.exe" -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($dcu) {
                Write-Log "Dell Command Update ile suruculer taraniyor + uygulaniyor..."
                & $dcu.FullName /applyUpdates -reboot=disable 2>&1 | Out-Null
                Write-Log "Dell surucu guncellemesi tetiklendi (log: dcu-cli)" 'OK'
            }
        } else {
            Write-Log "NOT: HP/Lenovo araci kuruldu; en son suruculeri cekmek icin aracı bir kez calistirin" 'INFO'
        }
    }
}

#endregion

#region ==================== BITIS ====================

if (-not $NoRestartExplorer -and -not $DryRun) {
    Write-Baslik "Explorer yeniden baslatiliyor"
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Write-Log "Explorer yeniden baslatildi" 'OK'
}

Write-Baslik "Tamamlandi"
Write-Log "Yazilan registry degeri : $script:Degisen"
Write-Log "Hata / uyari            : $script:Hata"
Write-Log "Log dosyasi             : $script:LogFile"
Write-Host ""
Write-Host "Bazi ayarlar (uzun yol destegi, hizli baslatma, telemetri, guncellemeler)" -ForegroundColor Yellow
Write-Host "icin yeniden baslatma gerekir." -ForegroundColor Yellow

exit 0

#endregion
