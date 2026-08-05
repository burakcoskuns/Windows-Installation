<#
.SYNOPSIS
    Windows 11 kurulum sonrasi otomatik yapilandirma scripti.

.DESCRIPTION
    Yeni kurulan bir Windows 11 makinede elle yapilan ayarlari otomatiklestirir:
    taskbar/explorer duzeni, gereksiz UWP uygulamalarinin kaldirilmasi,
    gizlilik/telemetri ayarlari, sistem tweak'leri ve winget ile uygulama kurulumu.

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
    TaskbarSolaHizala          = $true   # Ikonlari sola al (Win10 gibi)
    AramaKutusunuKaldir        = $true   # Baslat yanindaki arama kutusunu tamamen gizle
    GorevGorunumunuKaldir      = $true   # Task View butonu
    WidgetlariKaldir           = $true   # Hava durumu / haberler widget'i
    ChatKaldir                 = $true   # Teams (Chat) ikonu
    CopilotKaldir              = $true   # Copilot butonu + politika
    SaniyeGoster               = $false  # Saatte saniyeyi goster
    SagTikEndTask              = $true   # Taskbar sag tik menusune "End task" ekle

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
    GucPlaniYuksekPerformans   = $false  # Sunucu / masaustu icin $true
    SaatDilimiOtomatik         = $true

    # --- Temizlik ---
    BloatwareKaldir            = $true
}

# winget ile kurulacak uygulamalar (winget id)
$Apps = @(
    'Google.Chrome'
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
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") + $MyInvocation.UnboundArguments
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

#endregion

Write-Baslik "Windows 11 Post-Install"
Write-Log "Makine  : $env:COMPUTERNAME"
Write-Log "Kullanici: $($kimlik.Name)"
Write-Log "Surum   : $((Get-CimInstance Win32_OperatingSystem).Caption) / Build $([Environment]::OSVersion.Version.Build)"
Write-Log "Log     : $script:LogFile"
if ($DryRun) { Write-Log "DRY RUN modu - hicbir degisiklik yapilmayacak" 'WARN' }

#region ==================== PER-USER AYARLAR ====================

Write-Baslik "Taskbar / Baslat / Gezgin ayarlari"

Invoke-ForEachUserHive {
    param($U)

    $Adv      = "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $Search   = "$U\Software\Microsoft\Windows\CurrentVersion\Search"
    $CDM      = "$U\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $PolExp   = "$U\Software\Policies\Microsoft\Windows\Explorer"

    # --- Taskbar ---
    if ($Config.TaskbarSolaHizala)   { Set-Reg $Adv 'TaskbarAl' 0 }
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
    try {
        Set-Service tzautoupdate -StartupType Automatic -ErrorAction Stop
        Write-Log "Otomatik saat dilimi servisi etkinlestirildi" 'OK'
    } catch { Write-Log "tzautoupdate ayarlanamadi: $($_.Exception.Message)" 'WARN' }
}

if ($Config.HibernasyonKapat -and -not $DryRun) {
    powercfg.exe /hibernate off | Out-Null
    Write-Log "Hibernasyon kapatildi (hiberfil.sys silindi)" 'OK'
}

if ($Config.GucPlaniYuksekPerformans -and -not $DryRun) {
    try {
        powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null  # High performance
        Write-Log "Guc plani: Yuksek performans" 'OK'
    } catch { Write-Log "Guc plani degistirilemedi" 'WARN' }
}

#endregion

#region ==================== BLOATWARE ====================

if ($Config.BloatwareKaldir) {
    Write-Baslik "Gereksiz uygulamalarin kaldirilmasi"
    $kaldirilan = 0

    foreach ($app in $Bloatware) {
        try {
            $paketler = Get-AppxPackage -AllUsers -Name "*$app*" -ErrorAction SilentlyContinue
            foreach ($p in $paketler) {
                if ($DryRun) { Write-Log "[DRY] Kaldirilacak: $($p.Name)" 'SKIP'; continue }
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                Write-Log "Kaldirildi: $($p.Name)" 'OK'
                $kaldirilan++
            }

            # Provisioned paket -> yeni kullanicilara bir daha kurulmasin
            $prov = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$app*"
            foreach ($pp in $prov) {
                if ($DryRun) { Write-Log "[DRY] Provision kaldirilacak: $($pp.DisplayName)" 'SKIP'; continue }
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction SilentlyContinue | Out-Null
                Write-Log "Provision kaldirildi: $($pp.DisplayName)" 'OK'
            }
        }
        catch { Write-Log "$app kaldirilamadi: $($_.Exception.Message)" 'WARN' }
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
Write-Host "Bazi ayarlar (uzun yol destegi, hizli baslatma, telemetri) icin yeniden baslatma gerekir." -ForegroundColor Yellow

exit 0

#endregion
