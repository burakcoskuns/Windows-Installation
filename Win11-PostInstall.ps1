<#
.SYNOPSIS
    Windows 11 kurulum sonrasi otomatik yapilandirma scripti.

.DESCRIPTION
    Yeni kurulan bir Windows 11 makinede elle yapilan ayarlari otomatiklestirir:
    taskbar/explorer duzeni, masaustu ikonlari, gereksiz UWP uygulamalarinin
    kaldirilmasi, gizlilik/telemetri ayarlari, ofis odakli performans ayarlari,
    donanim sagligi raporu (batarya + disk), Windows guncellemesi, uretici
    surucu araci ve winget ile uygulama kurulumu (Chrome kurulu degilse en son
    surum resmi MSI ile; kuruluysa tekrar indirilmez).

    SURUCULER: her cihazin donanim kimligi (hardware ID) Windows Update'e
    sorulur; yalniz kurulu olandan DAHA YENI suruculer indirilip kurulur.
    Microsoft Update servisi kaydedilerek "istege bagli surucu guncellemeleri"
    de kapsanir, ayrica Dell/HP/Lenovo araci komut satirindan calistirilir.

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

.PARAMETER NoPause
    Sonunda ozet raporu gosterip beklemez, pencereyi kapatir. Otomasyon
    (NinjaOne / GPO / Intune / zamanlanmis gorev) icin kullanin.

.EXAMPLE
    .\Win11-PostInstall.ps1
    .\Win11-PostInstall.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File .\Win11-PostInstall.ps1 -SkipApps

.NOTES
    Yonetici hakki gerekir. Script kendini otomatik yukseltir.
    Sonunda explorer.exe yeniden baslatilir.
    Is bitince pencere KENDILIGINDEN KAPANMAZ: ozet rapor gosterilir ve
    kullanici kapatana kadar acik kalir (-NoPause ile kapali).
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipApps,
    [switch]$NoRestartExplorer,
    [switch]$NoPause          # Otomasyonda (NinjaOne/GPO/Intune) sonda bekleme
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
    MasaustuKontrolPaneli      = $true   # "Denetim Masasi" (Kontrol Paneli) ikonunu masaustune ekle

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
    OyunOzellikleriKapat       = $true   # Oyun Cubugu (Win+G), Game DVR kaydi ve Xbox servisleri -> ofiste gereksiz, arka planda kaynak yer
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
    SuruculeriGuncelle         = $true   # Surucu guncellemeleri (donanim ID'sine gore, asagiya bak)
    SurucuTamTarama            = $true   # Microsoft Update'teki ISTEGE BAGLI suruculeri de al (onemli: en son surumler burada)
    SurucuOnPlanda             = $true   # $true: bekle + sonucu rapora yaz (10-30 dk uzatir) · $false: arka planda calissin, script hemen bitsin
    SurucuRaporu               = $true   # Kurulan surumleri ve hala eski kalan suruculeri listele
    OemSurucuAraci             = $true   # Ureticinin resmi surucu aracini kur (Dell/HP/Lenovo/Intel)
    OemSurucuOtoUygula         = $true   # Kurulan OEM aracini komut satiriyla calistirip suruculeri uygula
}

# Chrome ayri kuruluyor (asagidaki KurChrome) — winget'in Chrome paketi Google
# installer'i ayni URL'de guncelledigi icin sik sik "hash uyusmuyor" hatasi verir.
# Resmi Enterprise MSI her zaman en son surumu makine geneli kurar.
$Config_KurChrome = $true
$Config_ChromeZorlaKur = $false               # $true: kurulu olsa da MSI'i indirip uzerine kur
$Config['ChromeVarsayilanTarayici'] = $true   # Chrome'u varsayilan tarayici yap (yeni profiller)

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

# Kaldirilacak UWP uygulamalar. Eslesme paket adinda GECEN ifadeye gore yapilir
# (ornek: 'Xbox' yazarsan tum Xbox paketleri gider). Ofis bilgisayari icin
# secildi: is uretmeyen, oyun/eglence/reklam amacli her sey kaldirilir.
$Bloatware = @(
    # --- Oyun / Xbox (ofiste tamamen gereksiz) ---
    'Microsoft.GamingApp'                  # Win11'deki YENI Xbox uygulamasi (Store oyunlari)
    'Microsoft.XboxApp'                    # Eski Xbox uygulamasi (Win10)
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'          # Oyun Cubugu (Win+G)
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.XboxIdentityProvider'       # Xbox oturum acma
    'Microsoft.GamingServices'             # Store oyun servisi
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MinecraftUWP'
    'king.com.'                            # Candy Crush ve digerleri
    'Microsoft.MicrosoftMahjong'
    'Microsoft.MicrosoftJigsaw'
    'Microsoft.MicrosoftSudoku'
    'Microsoft.BingCasual'

    # --- Eglence / medya ---
    'Clipchamp.Clipchamp'                  # Video editor
    'Microsoft.ZuneMusic'                  # Media Player / Groove
    'Microsoft.ZuneVideo'                  # Filmler ve TV
    'SpotifyAB.SpotifyMusic'
    'Netflix'
    'AmazonVideo.PrimeVideo'
    'Disney'
    'TikTok'
    'Facebook'
    'Instagram'
    'Twitter'
    'Duolingo'
    'ACGMediaPlayer'
    'EclipseManager'
    'ActiproSoftware'

    # --- Haber / reklam / Bing icerikleri ---
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingSearch'
    'Microsoft.BingFinance'
    'Microsoft.BingSports'
    'Microsoft.BingTravel'
    'Microsoft.BingHealthAndFitness'
    'Microsoft.BingFoodAndDrink'
    'Microsoft.BingTranslator'
    'Microsoft.News'
  # 'Microsoft.Advertising.Xaml'           # KAPALI: bazi Store uygulamalarinin bagimliligi; kaldirinca o uygulamalar acilmayabilir

    # --- Yapay zeka / asistan / oneri ---
    'Microsoft.Copilot'
    'Microsoft.549981C3F5F10'              # Cortana
    'Microsoft.Windows.DevHome'            # Gelistirici paneli
    'Microsoft.PowerAutomateDesktop'       # Onceden yuklu, lisanssiz kullanilmiyor

    # --- Iletisim / kisisel (kurumsal hesapla islevsiz) ---
    'Microsoft.SkypeApp'
    'Microsoft.Messaging'
    'Microsoft.People'
    'Microsoft.YourPhone'                  # Telefon Baglantisi
    'MicrosoftWindows.CrossDevice'         # Telefon entegrasyonu bileseni
    'Microsoft.WindowsCommunicationsApps'  # Mail ve Takvim (Outlook varsa gereksiz)
    'Microsoft.OutlookForWindows'          # "Yeni Outlook" (reklamli, kurumsal Outlook varken karisiklik yaratir)
    'MicrosoftTeams'                       # Kisisel Teams (Chat)
    'MSTeams'                              # Yeni Teams -> kurumsal Teams kuruluyorsa bunu listeden cikarin
    'LinkedInforWindows'
    'MicrosoftCorporationII.MicrosoftFamily'

    # --- 3D / karma gerceklik (eski, kullanilmiyor) ---
    'Microsoft.3DBuilder'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.Print3D'
    'Microsoft.MixedReality.Portal'

    # --- Diger gereksizler ---
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'                 # "Ipuclari"
    'Microsoft.Office.OneNote'             # Store surumu (Office'in OneNote'u ayri)
    'Microsoft.OneConnect'                 # Mobil planlar
    'Microsoft.Todos'
    'Microsoft.Whiteboard'
    'Microsoft.MicrosoftJournal'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.NetworkSpeedTest'
    'Microsoft.Wallet'
    'Microsoft.MicrosoftPowerBIForWindows'
    'Microsoft.Sway'
    'MicrosoftCorporationII.QuickAssist'   # Uzak yardim (kurumda AnyDesk/Ninja kullaniliyorsa gereksiz)
)
# NOT: Kalmasi gerekenler bilerek listede yok ->
# Photos, Calculator, Store, Terminal, Notepad, Paint, ScreenSketch, WebpImage,
# StickyNotes, Camera (Teams/kamera testi), VCLibs/UI.Xaml (bagimlilik),
# SecHealthUI (Defender arayuzu), RemoteDesktop (uzak masaustu).
#
# Kurumda Teams kullaniliyorsa 'MSTeams' satirini silin; yoksa yeni Teams de kalkar.

#endregion

#region ========================= ALTYAPI =========================

$ErrorActionPreference = 'Stop'
$script:LogFile = Join-Path $env:ProgramData "Win11-PostInstall_$(Get-Date -f yyyyMMdd-HHmmss).log"
$script:Degisen = 0
$script:Hata    = 0
$script:Basla   = Get-Date

# Sondaki rapor icin: bolum -> tek satirlik sonuc, ve tum uyari/hatalarin listesi.
$script:Ozet     = [ordered]@{}
$script:Uyarilar = New-Object System.Collections.ArrayList

function Add-Ozet {
    param([string]$Baslik, [string]$Sonuc)
    $script:Ozet[$Baslik] = $Sonuc
}

function Write-Log {
    param([string]$Msg, [ValidateSet('INFO','OK','WARN','ERR','SKIP')][string]$Level = 'INFO')
    $line = "[{0}] [{1,-4}] {2}" -f (Get-Date -f 'HH:mm:ss'), $Level, $Msg
    $color = switch ($Level) { 'OK'{'Green'} 'WARN'{'Yellow'} 'ERR'{'Red'} 'SKIP'{'DarkGray'} default{'Gray'} }
    Write-Host $line -ForegroundColor $color
    try { Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 } catch {}
    # Sondaki raporda "neye bakmam gerek" listesi olusabilsin diye biriktir.
    if ($Level -eq 'WARN' -or $Level -eq 'ERR') { [void]$script:Uyarilar.Add("[$Level] $Msg") }
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

# Adim: baslangicta "-> ..." yazar, is bitince "OK (Xsn)" yazar. Boylece ekranda
# o an ne yapildigi ve ne kadar surdugu net gorunur (eski loglar "kuruluyor" der,
# is bitse de mesaj degismezdi).
function Invoke-Step {
    param([string]$Ad, [scriptblock]$Is)
    Write-Host ("  -> {0} ..." -f $Ad) -ForegroundColor Gray
    Add-Content -Path $script:LogFile -Value ("[{0}] -> {1}" -f (Get-Date -f 'HH:mm:ss'), $Ad) -Encoding UTF8 -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { & $Is; $sw.Stop(); Write-Log ("{0} - bitti ({1:N1} sn)" -f $Ad, $sw.Elapsed.TotalSeconds) 'OK' }
    catch { $sw.Stop(); Write-Log ("{0} - HATA ({1:N1} sn): {2}" -f $Ad, $sw.Elapsed.TotalSeconds, $_.Exception.Message) 'ERR'; $script:Hata++ }
}

<#
    Invoke-Yerel: harici bir exe'yi GUVENLI calistirir; cikis kodunu ve ciktisini
    doner.

    Neden: $ErrorActionPreference = 'Stop' iken harici bir program stderr'e tek
    satir yazsa PowerShell bunu "NativeCommandError" sayip SCRIPTI KOMPLE
    DURDURUYOR. auditpol Turkce Windows'ta tam bunu yapip kurulumu yarida kesti.
    Burada stderr, cikti akisina alinir (2>&1) ve tercih gecici olarak
    'Continue' yapilir -> hata artik sadece rapor edilir, akis surer.
#>
function Invoke-Yerel {
    param(
        [Parameter(Mandatory)][string]$Dosya,
        [string[]]$Argumanlar = @()
    )
    $eski = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $cikti = & $Dosya @Argumanlar 2>&1
        # Cikis kodu uretmeyen cagrilarda $LASTEXITCODE $null kalir; bunu
        # "hata" saymak yanlis uyari uretirdi -> 0 kabul edilir.
        $kod = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        return [pscustomobject]@{
            Kod    = $kod
            Cikti  = ($cikti | Out-String).Trim()
            Basari = ($kod -eq 0)
        }
    }
    catch {
        return [pscustomobject]@{ Kod = -1; Cikti = $_.Exception.Message; Basari = $false }
    }
    finally { $ErrorActionPreference = $eski }
}

<#
    Invoke-ZamanAsimiyla: verilen isi ayri bir surecte calistirir ve en fazla
    $Saniye kadar bekler. Bitirirse $true, sure dolarsa $false doner.

    Neden gerekli: Remove-AppxPackage bazi paketlerde (ozellikle Xbox/GamingApp,
    Teams) AppX dagitim servisi mesgulken DAKIKALARCA geri donmez. Script o
    sirada donmus gibi gorunur ve kullanici pencereyi kapatir. Boylece en kotu
    ihtimalle o paket atlanir, script akmaya devam eder.
#>
function Invoke-ZamanAsimiyla {
    param(
        [Parameter(Mandatory)][scriptblock]$Is,
        [int]$Saniye = 120,
        $Arg
    )
    $job = $null
    try {
        $job = Start-Job -ScriptBlock $Is -ArgumentList $Arg
        if (Wait-Job $job -Timeout $Saniye) {
            Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
            return $true
        }
        # Sure doldu: isi birak, script devam etsin (islem arka planda surebilir)
        Stop-Job $job -ErrorAction SilentlyContinue
        return $false
    }
    catch {
        Write-Log "Is calistirilamadi: $($_.Exception.Message)" 'WARN'
        return $false
    }
    finally { if ($job) { Remove-Job $job -Force -ErrorAction SilentlyContinue } }
}

# winget'i her yerde ayni sekilde bulur. Bulamazsa App Installer'i yeniden
# kaydetmeyi dener ("winget bulunamadi" cogunlukla kayit eksikligindendir,
# ozellikle SYSTEM baglaminda) ve tekrar arar. Bulursa exe yolunu, bulamazsa
# $null doner.
function Resolve-Winget {
    # 1) Dogrudan surumlu WindowsApps yolu (en guncel)
    $glob = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName | Select-Object -Last 1
    if ($glob) { return $glob.FullName }
    # 2) PATH
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # 3) App Installer makinede var ama kayitli degil -> yeniden kaydet
    $pkg = Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        Write-Log "winget kayitli degil, App Installer yeniden kaydediliyor..." 'INFO'
        try { Add-AppxPackage -DisableDevelopmentMode -Register "$($pkg.InstallLocation)\AppXManifest.xml" -ErrorAction Stop } catch {}
        $glob = Get-ChildItem "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName | Select-Object -Last 1
        if ($glob) { Write-Log "winget yeniden kayittan sonra bulundu" 'OK'; return $glob.FullName }
    }
    return $null
}

<#
    Get-ChromeSurum: Chrome kurulu mu? Kuruluysa surum numarasini, degilse $null
    doner. Boylece her calistirmada ~120 MB MSI bosuna indirilmez.

    Uc yere birden bakilir:
      1) Makine geneli kurulum (Program Files / Program Files (x86))
      2) Kayit defteri App Paths (baska bir dizine kurulmus olabilir)
      3) Kullanici bazli kurulum (her profilin AppData'si) -> SYSTEM baglaminda
         $env:LOCALAPPDATA SYSTEM profilini gosterdigi icin C:\Users taranir.
#>
function Get-ChromeSurum {
    $adaylar = New-Object System.Collections.ArrayList
    foreach ($kok in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($kok) { [void]$adaylar.Add((Join-Path $kok 'Google\Chrome\Application\chrome.exe')) }
    }

    # Kayit defterindeki kayitli yol (varsayilan disi kurulum dizinleri icin)
    foreach ($rp in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
    )) {
        try {
            $v = (Get-ItemProperty -Path $rp -ErrorAction Stop).'(default)'
            if ($v) { [void]$adaylar.Add($v.Trim('"')) }
        } catch {}
    }

    # Kullanici bazli kurulumlar
    try {
        Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$adaylar.Add((Join-Path $_.FullName 'AppData\Local\Google\Chrome\Application\chrome.exe'))
        }
    } catch {}

    foreach ($p in $adaylar) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            try   { return (Get-Item -LiteralPath $p).VersionInfo.ProductVersion }
            catch { return 'bilinmiyor' }
        }
    }
    return $null
}

<#
    Get-SurucuEnvanteri: sistemdeki TUM cihazlarin surucu envanterini cikarir.
    Anahtar = DeviceID (PNP kimligi), deger = surum/tarih/saglayici/donanim ID.

    Guncelleme oncesi ve sonrasi iki kez cagrilip karsilastirilir -> hangi
    surucunun hangi surumden hangi surume ciktigi net raporlanir.
#>
function Get-SurucuEnvanteri {
    $liste = @{}
    try {
        foreach ($d in (Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)) {
            if (-not $d.DeviceID -or -not $d.DriverVersion) { continue }
            $liste[$d.DeviceID] = [pscustomobject]@{
                Ad        = $d.DeviceName
                Surum     = $d.DriverVersion
                Tarih     = $d.DriverDate
                Saglayici = $d.DriverProviderName
                DonanimID = $d.HardWareID
                Sinif     = $d.DeviceClass
            }
        }
    } catch { Write-Log "Surucu envanteri okunamadi: $($_.Exception.Message)" 'WARN' }
    return $liste
}

<#
    Invoke-SurucuGuncelleme: Windows Update Agent (WUA) uzerinden SURUCU
    guncellemesi yapar.

    Nasil calisir: WUA, makinedeki her cihazin DONANIM KIMLIGINI (hardware ID:
    orn. PCI\VEN_8086&DEV_9A49&...) sunucuya gonderir; sunucu yalniz o kimlige
    UYAN ve kurulu olandan DAHA YENI suruculeri dondurur. Yani "surum karsilastirma"
    isini WU kendisi yapar -> yanlis/uyumsuz surucu kurma riski olmaz.

    TamTarama: Microsoft Update servisini kaydeder ve oradan arar. Onemli, cunku
    "istege bagli surucu guncellemeleri" (Ayarlar > Windows Update > Gelismis >
    Istege bagli guncellemeler) yalniz bu servis uzerinden gorunur; normal
    otomatik guncelleme bunlari HIC indirmez. Kullanicinin istedigi "hep en son
    surucu" davranisini saglayan kisim budur.
#>
function Invoke-SurucuGuncelleme {
    param([bool]$TamTarama = $true)

    $rapor = [ordered]@{ Bulunan = 0; Kurulan = 0; Basarisiz = 0; YenidenBaslat = $false; Basliklar = @() }

    try { $session = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop }
    catch {
        Write-Log "Windows Update servisine baglanilamadi: $($_.Exception.Message)" 'ERR'
        $script:Hata++; return $rapor
    }

    $searcher = $session.CreateUpdateSearcher()

    if ($TamTarama) {
        $msUpdateId = '7971f918-a847-4430-9279-4a52d1efe18d'   # Microsoft Update
        try {
            $sm = New-Object -ComObject Microsoft.Update.ServiceManager
            if (-not ($sm.Services | Where-Object { $_.ServiceID -eq $msUpdateId })) {
                [void]$sm.AddService2($msUpdateId, 7, '')      # 7 = kayit + online + AU'ya ekle
                Write-Log "Microsoft Update servisi kaydedildi (istege bagli suruculer icin)" 'OK'
            }
            $searcher.ServerSelection = 3    # ssOthers
            $searcher.ServiceID       = $msUpdateId
        } catch {
            Write-Log "Microsoft Update servisi kullanilamadi, varsayilan WU ile devam: $($_.Exception.Message)" 'WARN'
        }
    }

    Write-Host "  -> Donanim kimlikleri Windows Update'e soruluyor (1-3 dk surebilir) ..." -ForegroundColor Gray
    $sonuc = $null
    try { $sonuc = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0") }
    catch {
        # ServiceID/ServerSelection nedeniyle patladiysa varsayilan servisle tekrar dene
        Write-Log "Microsoft Update ile surucu taramasi basarisiz, varsayilan WU deneniyor: $($_.Exception.Message)" 'WARN'
        try { $sonuc = $session.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver' and IsHidden=0") }
        catch {
            Write-Log "Surucu taramasi basarisiz: $($_.Exception.Message)" 'ERR'
            $script:Hata++; return $rapor
        }
    }

    $rapor.Bulunan = $sonuc.Updates.Count
    if ($rapor.Bulunan -eq 0) {
        Write-Log "Tum suruculer guncel - Windows Update'te daha yeni surucu yok" 'OK'
        return $rapor
    }

    Write-Log "$($rapor.Bulunan) adet daha yeni surucu bulundu" 'INFO'

    # Kurulu surumlerle karsilastirip ekrana "neyi neyle degistiriyoruz" yaz
    $envanter = Get-SurucuEnvanteri
    $col = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $sonuc.Updates) {
        $hw = ''; $yeniTarih = $null; $saglayici = ''
        try { $hw = "$($u.DriverHardwareID)"; $yeniTarih = $u.DriverVerDate; $saglayici = "$($u.DriverProvider)" } catch {}

        $mevcut = $null
        if ($hw) {
            $mevcut = $envanter.Values | Where-Object {
                $_.DonanimID -and ("$($_.DonanimID)" -eq $hw)
            } | Select-Object -First 1
        }

        $satir = "  + $($u.Title)"
        if ($saglayici) { $satir += " [$saglayici]" }
        Write-Log $satir
        if ($mevcut) {
            Write-Log ("      kurulu: v{0} ({1:yyyy-MM-dd})  ->  yeni surucu tarihi: {2:yyyy-MM-dd}" -f `
                        $mevcut.Surum, $mevcut.Tarih, $yeniTarih)
        }

        if (-not $u.EulaAccepted) { try { $u.AcceptEula() } catch {} }
        [void]$col.Add($u)
        $rapor.Basliklar += "$($u.Title)"
    }

    try {
        Write-Host "  -> Suruculer indiriliyor ..." -ForegroundColor Gray
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $d = $session.CreateUpdateDownloader(); $d.Updates = $col; [void]$d.Download()
        Write-Log ("Suruculer indirildi ({0:N1} sn)" -f $sw.Elapsed.TotalSeconds) 'OK'

        # Suruculer TEK TEK kuruluyor. Hepsini tek Install() cagrisiyla kurmak
        # daha hizli ama o cagri bitene kadar (10-30 dk) ekranda hicbir sey
        # degismiyor ve script donmus gibi gorunuyor. Tek tek kurunca hangi
        # surucude olundugu ve ne kadar surdugu aninda gorunur.
        Write-Log ("{0} surucu kurulacak. Her biri 1-5 dk surebilir; toplam 10-30 dk." -f $col.Count) 'WARN'
        Write-Log "Bu sirada cihazlar kisa sure kaybolabilir, ekran titreyebilir - normaldir." 'INFO'

        $sw2 = [Diagnostics.Stopwatch]::StartNew()
        for ($n = 0; $n -lt $col.Count; $n++) {
            $u = $col.Item($n)
            $tek = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$tek.Add($u)

            Write-Host ("     -> [{0}/{1}] {2} kuruluyor ..." -f ($n + 1), $col.Count, $u.Title) -ForegroundColor DarkGray
            $swk = [Diagnostics.Stopwatch]::StartNew()
            try {
                $i = $session.CreateUpdateInstaller(); $i.Updates = $tek
                $ir = $i.Install()
                $swk.Stop()
                if ($ir.RebootRequired) { $rapor.YenidenBaslat = $true }

                $kod = $ir.GetUpdateResult(0).ResultCode   # 2 = basarili, 3 = uyarili, 4 = hata
                if ($kod -eq 2 -or $kod -eq 3) {
                    $rapor.Kurulan++
                    Write-Log ("  [{0}/{1}] OK ({2:N0} sn) {3}" -f ($n + 1), $col.Count, $swk.Elapsed.TotalSeconds, $u.Title) 'OK'
                } else {
                    $rapor.Basarisiz++
                    Write-Log ("  [{0}/{1}] HATA kod {2} ({3:N0} sn) {4}" -f ($n + 1), $col.Count, $kod, $swk.Elapsed.TotalSeconds, $u.Title) 'WARN'
                }
            }
            catch {
                # Tek surucunun patlamasi digerlerini durdurmasin
                $swk.Stop(); $rapor.Basarisiz++
                Write-Log ("  [{0}/{1}] kurulamadi: {2}" -f ($n + 1), $col.Count, $_.Exception.Message) 'WARN'
            }
        }
        $sw2.Stop()

        Write-Log ("Surucu kurulumu bitti: {0} basarili, {1} basarisiz ({2:N1} dk)" -f `
                    $rapor.Kurulan, $rapor.Basarisiz, $sw2.Elapsed.TotalMinutes) 'OK'
        if ($rapor.YenidenBaslat) { Write-Log "Suruculerin tam etkili olmasi icin YENIDEN BASLATMA gerekiyor" 'WARN' }
    }
    catch {
        Write-Log "Surucu indirme/kurulum hatasi: $($_.Exception.Message)" 'ERR'
        $script:Hata++
    }

    return $rapor
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
        Invoke-Yerel powercfg.exe @('/batteryreport','/xml','/output',"$xml") | Out-Null
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

        if     ($saglik -ge 80) { Write-Log "YORUM: Batarya saglikli (>=%80). Bir sorun yok." 'OK';   Add-Ozet 'Batarya' "%$saglik - saglikli" }
        elseif ($saglik -ge 60) { Write-Log "YORUM: Batarya normal yaslanmis (%60-80). Takip edin, aciliyet yok." 'INFO'; Add-Ozet 'Batarya' "%$saglik - normal yaslanma" }
        elseif ($saglik -ge 40) { Write-Log "YORUM: Batarya yipranmis (%40-60). Sarj suresi belirgin kisalmistir." 'WARN'; Add-Ozet 'Batarya' "%$saglik - YIPRANMIS" }
        else                    { Write-Log "YORUM: Batarya kritik (<%40). Degisim dusunulmeli." 'ERR';  Add-Ozet 'Batarya' "%$saglik - KRITIK, degisim gerekir" }
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

    $sorunlu = @()
    foreach ($d in $diskler) {
        $boyutGB = [math]::Round($d.Size / 1GB)
        $tur = $d.MediaType   # SSD / HDD / Unspecified
        Write-Log ("Disk: {0} ({1} GB, {2})" -f $d.FriendlyName, $boyutGB, $tur)

        $durum = "$($d.HealthStatus)"   # Healthy / Warning / Unhealthy
        switch ($durum) {
            'Healthy' { Write-Log "  SMART durumu: Healthy" 'OK' }
            'Warning' { Write-Log "  SMART durumu: Warning -> yedek alin, disk izlenmeli" 'WARN'; $sorunlu += "$($d.FriendlyName): Warning" }
            default   { Write-Log "  SMART durumu: $durum -> ACIL yedek + degisim" 'ERR';        $sorunlu += "$($d.FriendlyName): $durum" }
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
                $sorunlu += "$($d.FriendlyName): duzeltilemeyen okuma/yazma hatasi"
            }
        }
    }

    if ($sorunlu.Count -eq 0) { Add-Ozet 'Diskler' "$($diskler.Count) disk - hepsi saglikli" }
    else                      { Add-Ozet 'Diskler' ("DIKKAT -> " + ($sorunlu -join '; ')) }
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
    $hideNew    = "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    $hideClasik = "$U\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"

    if ($Config.MasaustuBuBilgisayar) {
        $buPC = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
        Set-Reg $hideNew    $buPC 0
        Set-Reg $hideClasik $buPC 0
    }

    # Denetim Masasi (Kontrol Paneli) ikonu. Win10/11 masaustu ikon ayarlarindaki
    # CLSID {5399E694-...}; {21EC2020-...} eski kabuk yolunun kullandigi klasik
    # CLSID. Ikisi de yazilir ki her iki durumda da ikon gorunsun.
    if ($Config.MasaustuKontrolPaneli) {
        foreach ($cp in @('{5399E694-6CE5-48C6-8AFE-2A0B9BCF4C7B}', '{21EC2020-3AEA-1069-A2DD-08002B30309D}')) {
            Set-Reg $hideNew    $cp 0
            Set-Reg $hideClasik $cp 0
        }
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

    # --- Oyun ozellikleri (per-user) ---
    # Xbox uygulamasi kaldirilsa bile Oyun Cubugu/Game DVR kabugun icinde durur:
    # arka planda kayit servisi calisir ve Win+G ile acilir. Burada kapatilir.
    if ($Config.OyunOzellikleriKapat) {
        Set-Reg "$U\System\GameConfigStore" 'GameDVR_Enabled' 0
        Set-Reg "$U\Software\Microsoft\GameBar" 'AutoGameModeEnabled'      0
        Set-Reg "$U\Software\Microsoft\GameBar" 'ShowStartupPanel'         0
        Set-Reg "$U\Software\Microsoft\GameBar" 'UseNexusForGameBarEnabled' 0
        Set-Reg "$U\Software\Microsoft\Windows\CurrentVersion\GameDVR" 'AppCaptureEnabled' 0
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
    $hib = Invoke-Yerel powercfg.exe @('/hibernate','off')
    if ($hib.Basari) { Write-Log "Hibernasyon kapatildi (hiberfil.sys silindi)" 'OK' }
    else { Write-Log "Hibernasyon kapatilamadi: $($hib.Cikti)" 'WARN' }
}

if ($Config.OfisGucPlani -and -not $DryRun) {
    # Laptop'ta Yuksek Performans zorlamak pili ve isiyi kotu etkiler -> Dengeli
    # birakilir. Masaustunde islemci uyku (core parking) engellenip menu/uygulama
    # acilislarindaki mikro gecikmeler kaldirilir.
    if ($script:Laptop) {
        Write-Log "Laptop -> guc plani Dengeli birakildi (pil/isi icin dogru secim)" 'INFO'
    } else {
        # High performance plan GUID'i
        $gp = Invoke-Yerel powercfg.exe @('/setactive','8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c')
        if ($gp.Basari) { Write-Log "Guc plani: Yuksek performans (masaustu)" 'OK' }
        else { Write-Log "Guc plani degistirilemedi: $($gp.Cikti)" 'WARN' }
    }
}

if ($Config.DepoTemizlemeOtomatik) {
    # Storage Sense: gecici dosyalari ve geri donusum kutusunu otomatik temizler.
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' 'AllowStorageSenseGlobal' 1
    Write-Log "Otomatik depo temizleme (Storage Sense) acildi" 'OK'
}

if ($Config.OyunOzellikleriKapat) {
    # Politika ile Game DVR tamamen kapatilir (per-user ayardan bagimsiz, kalici).
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0

    # Xbox servisleri: uygulama kaldirilsa bile servisler otomatik baslamaya devam
    # eder. Ofiste hicbir islevi yok -> devre disi.
    if (-not $DryRun) {
        foreach ($svc in @('XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc')) {
            try {
                Stop-Service $svc -Force -ErrorAction SilentlyContinue
                Set-Service  $svc -StartupType Disabled -ErrorAction Stop
            } catch { Write-Log "$svc devre disi birakilamadi: $($_.Exception.Message)" 'WARN' }
        }
    }
    Write-Log "Oyun Cubugu / Game DVR ve Xbox servisleri kapatildi" 'OK'
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
    #
    # ADI DEGIL GUID KULLANILIYOR: auditpol alt kategori adlarini SISTEM DILINDE
    # bekler. Turkce Windows'ta /subcategory:"Removable Storage" hata 0x57
    # (gecersiz parametre) verir. GUID her dilde ayni:
    #   {0CCE9245-...} = Removable Storage / Cikarilabilir Depolama
    $sonuc = Invoke-Yerel auditpol.exe @(
        '/set', '/subcategory:{0CCE9245-69AE-11D9-BED3-505054503030}',
        '/success:enable', '/failure:enable'
    )
    if ($sonuc.Basari) {
        Write-Log "USB dosya erisimi denetimi acildi (Guvenlik gunlugu, Event 4663)" 'OK'
        Write-Log "Uzun vade: kayitlari NinjaOne'a aktarin, yerel gunluk sinirlidir" 'INFO'
    } else {
        Write-Log "USB denetimi acilamadi (auditpol kod $($sonuc.Kod)): $($sonuc.Cikti)" 'WARN'
    }
}

# Silme denetimi bir KLASORE hedeflenir (tum diski denetlemek asiri gurultu uretir).
if ($Config.SilmeDenetimiKlasor -and -not $DryRun) {
    if (-not (Test-Path $Config.SilmeDenetimiKlasor)) {
        Write-Log "Silme denetimi klasoru yok: $($Config.SilmeDenetimiKlasor)" 'WARN'
    } else {
        Write-Baslik "Silme denetimi: $($Config.SilmeDenetimiKlasor)"
        # {0CCE921D-...} = File System / Dosya Sistemi (dil bagimsiz GUID)
        $fsSonuc = Invoke-Yerel auditpol.exe @(
            '/set', '/subcategory:{0CCE921D-69AE-11D9-BED3-505054503030}',
            '/success:enable', '/failure:enable'
        )
        if (-not $fsSonuc.Basari) {
            Write-Log "Dosya sistemi denetimi acilamadi (kod $($fsSonuc.Kod)): $($fsSonuc.Cikti)" 'WARN'
        }
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

    # Xbox/oyun paketleri AppX dagitim servisini kilitleyebiliyor: GamingServices
    # servisleri calisirken Microsoft.GamingApp kaldirmak dakikalarca asili kalir.
    # Servisleri once durdurunca kaldirma saniyeler icinde biter.
    if (-not $DryRun -and ($Bloatware -match 'Gaming|Xbox')) {
        foreach ($svc in @('GamingServices','GamingServicesNet')) {
            try {
                if (Get-Service $svc -ErrorAction SilentlyContinue) {
                    Stop-Service $svc -Force -ErrorAction SilentlyContinue
                    Write-Log "$svc durduruldu (Xbox paketleri takilmasin diye)" 'INFO'
                }
            } catch {}
        }
    }

    $toplam = $Bloatware.Count; $sayac = 0
    $askidaKalan = 0
    foreach ($app in $Bloatware) {
        $sayac++
        $eslesen = @($tumPaket | Where-Object Name -like "*$app*")
        $eslesenProv = @($tumProv | Where-Object DisplayName -like "*$app*")

        # Bu kalip hic eslesmiyorsa tek satir yaz ve gec: 75 kalip x bos islem
        # ekrani doldurmasin, ama atlandigi da gorunsun.
        if ($eslesen.Count -eq 0 -and $eslesenProv.Count -eq 0) {
            Write-Log ("[{0,2}/{1}] {2} - yok, atlandi" -f $sayac, $toplam, $app) 'SKIP'
            continue
        }
        Write-Log ("[{0,2}/{1}] {2} ({3} paket)" -f $sayac, $toplam, $app, ($eslesen.Count + $eslesenProv.Count))

        try {
            foreach ($p in $eslesen) {
                if ($DryRun) { Write-Log "  [DRY] Kaldirilacak: $($p.Name)" 'SKIP'; continue }
                # Hangi paketin uzerinde oldugumuz ANINDA gorunsun; asili kalirsa
                # hangisinde kaldigi belli olsun.
                Write-Host ("     -> {0} kaldiriliyor ..." -f $p.Name) -ForegroundColor DarkGray
                $sonuc = Invoke-ZamanAsimiyla -Saniye 120 -Is {
                    param($pfn)
                    Remove-AppxPackage -Package $pfn -AllUsers -ErrorAction SilentlyContinue
                } -Arg $p.PackageFullName

                if ($sonuc) { Write-Log "  Kaldirildi: $($p.Name)" 'OK'; $kaldirilan++ }
                else {
                    Write-Log "  $($p.Name) 120 sn'de bitmedi, atlandi (arka planda surebilir)" 'WARN'
                    $askidaKalan++
                }
            }
            # Provisioned paket -> yeni kullanicilara bir daha kurulmasin
            foreach ($pp in $eslesenProv) {
                if ($DryRun) { Write-Log "  [DRY] Provision kaldirilacak: $($pp.DisplayName)" 'SKIP'; continue }
                Write-Host ("     -> {0} (provision) kaldiriliyor ..." -f $pp.DisplayName) -ForegroundColor DarkGray
                $sonuc = Invoke-ZamanAsimiyla -Saniye 120 -Is {
                    param($pn)
                    Remove-AppxProvisionedPackage -Online -PackageName $pn -ErrorAction SilentlyContinue | Out-Null
                } -Arg $pp.PackageName

                if ($sonuc) { Write-Log "  Provision kaldirildi: $($pp.DisplayName)" 'OK' }
                else { Write-Log "  $($pp.DisplayName) provision kaldirmasi zaman asimina ugradi" 'WARN'; $askidaKalan++ }
            }
        }
        catch { Write-Log "  $app kaldirilamadi: $($_.Exception.Message)" 'WARN' }
    }
    Write-Log "Toplam $kaldirilan paket kaldirildi" 'OK'
    $ozetMetin = "$kaldirilan paket kaldirildi"
    if ($askidaKalan -gt 0) { $ozetMetin += ", $askidaKalan tanesi zaman asimina ugradi" }
    Add-Ozet 'Bloatware' $ozetMetin
}

#endregion

#region ==================== UYGULAMA KURULUMU ====================

if (-not $SkipApps -and $Apps.Count -gt 0) {
    Write-Baslik "Uygulama kurulumu (winget)"

    $winget = Resolve-Winget
    if (-not $winget) {
        Write-Log "winget bulunamadi ve kaydedilemedi. Bu uygulamalar atlandi." 'WARN'
        Write-Log "Cozum: Store'dan 'App Installer' kurup scripti tekrar calistirin." 'INFO'
        Add-Ozet 'Uygulamalar' 'winget bulunamadi -> hicbiri kurulmadi'
    }
    else {
        Write-Log "winget: $winget" 'INFO'
        & $winget source update --disable-interactivity 2>&1 | Out-Null

        $sayKurulan = 0; $sayAtlanan = 0; $sayHata = 0
        $toplam = $Apps.Count; $sira = 0
        foreach ($id in $Apps) {
            $sira++
            $etiket = "[{0}/{1}] {2}" -f $sira, $toplam, $id
            if ($DryRun) { Write-Log "$etiket [DRY] kurulacak" 'SKIP'; continue }

            # Zaten kurulu mu? Once bunu soyle -> "kuruluyor" derken aslinda kurulu
            # olmasi yanilgisini onler.
            & $winget list --id $id --exact --accept-source-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Log "$etiket zaten kurulu, atlandi" 'SKIP'; $sayAtlanan++; continue }

            $sw = [Diagnostics.Stopwatch]::StartNew()
            Write-Host ("  -> {0} indiriliyor + kuruluyor ..." -f $etiket) -ForegroundColor Gray
            $out = & $winget install --id $id --exact --silent --scope machine `
                        --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
            if ($LASTEXITCODE -ne 0 -and "$out" -notmatch 'already installed|zaten') {
                # machine scope desteklemeyen paketler icin user scope dene
                $out = & $winget install --id $id --exact --silent `
                            --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
            }
            $sw.Stop(); $sn = "{0:N1} sn" -f $sw.Elapsed.TotalSeconds
            if ($LASTEXITCODE -eq 0)                              { Write-Log "$etiket kuruldu ($sn)" 'OK'; $sayKurulan++ }
            elseif ("$out" -match 'already installed|zaten')      { Write-Log "$etiket zaten kurulu ($sn)" 'SKIP'; $sayAtlanan++ }
            else { Write-Log "$etiket KURULAMADI (exit $LASTEXITCODE, $sn)" 'WARN'; $script:Hata++; $sayHata++ }
        }
        Add-Ozet 'Uygulamalar' "$sayKurulan kuruldu, $sayAtlanan zaten vardi, $sayHata basarisiz"
    }
}

#endregion

#region ==================== CHROME (EN SON SURUM) ====================

if ($Config_KurChrome -and -not $SkipApps) {
    Write-Baslik "Google Chrome (en son surum)"

    # 1) ZATEN KURULU MU? Kuruluysa hicbir sey indirilmez. Chrome kendi
    #    guncelleyicisiyle (GoogleUpdate) zaten en son surume ciktigi icin
    #    her calistirmada ~120 MB MSI indirmek gereksiz.
    $mevcutChrome = Get-ChromeSurum
    $kuruldu = $false
    if ($mevcutChrome -and -not $Config_ChromeZorlaKur) {
        Write-Log "Chrome zaten kurulu (surum $mevcutChrome) -> indirme/kurulum atlandi" 'SKIP'
        Write-Log "Yeniden kurmak icin: `$Config_ChromeZorlaKur = `$true" 'INFO'
        Add-Ozet 'Chrome' "zaten kurulu (v$mevcutChrome) - indirilmedi"
        $kuruldu = $true
    }
    elseif ($mevcutChrome) {
        Write-Log "Chrome kurulu (v$mevcutChrome) ama zorla kurulum acik -> uzerine kurulacak" 'INFO'
    }

    # Once winget dene (varsa hizli ve temiz). Basarisiz olursa resmi MSI'a dus.
    $wg = if ($kuruldu) { $null } else { Resolve-Winget }
    if ($wg -and -not $DryRun) {
        Write-Host "  -> Chrome winget ile deneniyor ..." -ForegroundColor Gray
        $out = & $wg install --id Google.Chrome --exact --silent --scope machine `
                    --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
        if ($LASTEXITCODE -eq 0 -or "$out" -match 'already installed|zaten') {
            Write-Log "Chrome winget ile kuruldu/guncel" 'OK'; $kuruldu = $true
            Add-Ozet 'Chrome' 'winget ile kuruldu'
        } else {
            Write-Log "winget Chrome'u kuramadi (muhtemelen hash uyusmazligi) -> resmi MSI'a geciliyor" 'WARN'
        }
    }

    # Resmi Enterprise MSI — her zaman en son surum, makine geneli, sessiz.
    if (-not $kuruldu) {
        $msiUrl = 'https://dl.google.com/tag/s/dl/chrome/install/googlechromestandaloneenterprise64.msi'
        $msi    = Join-Path $env:TEMP 'chrome_enterprise.msi'
        if ($DryRun) {
            Write-Log "[DRY] Chrome MSI indirilip kurulacak: $msiUrl" 'SKIP'
            Add-Ozet 'Chrome' '[DRY] kurulacakti'
        } else {
            try {
                # Indirme ve kurulum AYRI adimlar olarak loglaniyor -> ekranda o an
                # ne oldugu net (eskiden "indiriliyor" der, kurulmus bile olurdu).
                $sw = [Diagnostics.Stopwatch]::StartNew()
                Write-Host "  -> Chrome MSI indiriliyor ..." -ForegroundColor Gray
                $eskiPB = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $msiUrl -OutFile $msi -UseBasicParsing
                $ProgressPreference = $eskiPB
                $mb = [math]::Round((Get-Item $msi).Length / 1MB, 1)
                Write-Log ("Chrome MSI indirildi ({0} MB, {1:N1} sn)" -f $mb, $sw.Elapsed.TotalSeconds) 'OK'

                Write-Host "  -> Chrome kuruluyor (msiexec) ..." -ForegroundColor Gray
                $sw2 = [Diagnostics.Stopwatch]::StartNew()
                $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @('/i', "`"$msi`"", '/qn', '/norestart')
                $sw2.Stop()
                if ($p.ExitCode -eq 0) {
                    Write-Log ("Chrome kuruldu (en son surum, {0:N1} sn)" -f $sw2.Elapsed.TotalSeconds) 'OK'
                    Add-Ozet 'Chrome' "MSI ile kuruldu (v$(Get-ChromeSurum))"
                }
                else {
                    Write-Log "Chrome MSI kurulumu basarisiz (exit $($p.ExitCode))" 'ERR'; $script:Hata++
                    Add-Ozet 'Chrome' "KURULAMADI (msiexec exit $($p.ExitCode))"
                }
            }
            catch {
                Write-Log "Chrome kurulamadi: $($_.Exception.Message)" 'ERR'; $script:Hata++
                Add-Ozet 'Chrome' 'KURULAMADI (indirme/kurulum hatasi)'
            }
            finally { Remove-Item $msi -ErrorAction SilentlyContinue }
        }
    }

    # --- Chrome'u varsayilan tarayici yap ---
    # Win11 tarayici varsayilanini UserChoice hash'i ile korur; tek registry
    # anahtariyla zorlanamaz. Desteklenen yontem: DefaultAppAssociations XML'i
    # DISM ile ice aktarmak. Bu YENI kullanici profilleri icin gecerlidir
    # (ilk kurulum senaryosunda dogru olan budur). Chrome kurulu olmali (ustte).
    if ($Config.ChromeVarsayilanTarayici -and -not $DryRun -and (Get-ChromeSurum)) {
        $xml = Join-Path $env:TEMP 'defaultapps.xml'
        @'
<?xml version="1.0" encoding="UTF-8"?>
<DefaultAssociations>
  <Association Identifier="http"   ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier="https"  ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".htm"   ProgId="ChromeHTML" ApplicationName="Google Chrome" />
  <Association Identifier=".html"  ProgId="ChromeHTML" ApplicationName="Google Chrome" />
</DefaultAssociations>
'@ | Set-Content -Path $xml -Encoding UTF8
        try {
            $dism = Invoke-Yerel Dism.exe @('/Online',"/Import-DefaultAppAssociations:$xml")
            if ($dism.Basari) {
                Write-Log "Chrome varsayilan tarayici yapildi (yeni profiller icin)" 'OK'
                Write-Log "NOT: Zaten Edge kullanmis mevcut kullanicida Windows secimi koruyabilir" 'INFO'
                Add-Ozet 'Varsayilan tarayici' 'Chrome (yeni profiller icin)'
            } else {
                Write-Log "Varsayilan tarayici ayarlanamadi (DISM kod $($dism.Kod))" 'WARN'
                Add-Ozet 'Varsayilan tarayici' "ayarlanamadi (DISM kod $($dism.Kod))"
            }
        } catch { Write-Log "Varsayilan tarayici ayarlanamadi: $($_.Exception.Message)" 'WARN' }
        finally { Remove-Item $xml -ErrorAction SilentlyContinue }
    }
}

#endregion

#region ==================== SURUCU GUNCELLEME (DONANIM ID) ====================

# Amac: makinedeki TUM suruculer her zaman en son surumde olsun.
#
# Yontem: her cihazin DONANIM KIMLIGI (hardware ID) Windows Update'e sorulur,
# yalniz o kimlige uyan ve KURULU OLANDAN YENI suruculer indirilip kurulur.
# "Istege bagli surucu guncellemeleri" de dahil edilir (Config.SurucuTamTarama)
# -> Ayarlar ekranindan elle yapilacak isin tamami otomatiklesir.
#
# Bu bolum ON PLANDA calisir (Config.SurucuOnPlanda) cunku sonucun rapora
# girmesi isteniyor. Windows Update ayni anda iki kurulum kabul etmedigi icin
# bu bolum, arka plandaki Windows guncellemesi BASLATILMADAN ONCE biter.
$script:SurucuSonuc = $null
if ($Config.SuruculeriGuncelle -and $Config.SurucuOnPlanda -and -not $DryRun) {
    Write-Baslik "Surucu guncelleme (donanim ID'lerine gore)"

    $surucuOncesi = Get-SurucuEnvanteri
    Write-Log ("Sistemde kayitli surucu sayisi: {0}" -f $surucuOncesi.Count)

    $script:SurucuSonuc = Invoke-SurucuGuncelleme -TamTarama $Config.SurucuTamTarama

    # Gercekten NE degisti? Kurulum sonrasi envanter tekrar okunur ve surumler
    # karsilastirilir. WU'nun "basarili" demesi bazen surumun degismedigi anlamina
    # gelir; bu karsilastirma gercegi gosterir.
    if ($script:SurucuSonuc.Kurulan -gt 0) {
        $surucuSonrasi = Get-SurucuEnvanteri
        $degisenler = @()
        foreach ($id in $surucuSonrasi.Keys) {
            $yeni = $surucuSonrasi[$id]
            $eski = $surucuOncesi[$id]
            if ($eski -and $eski.Surum -ne $yeni.Surum) {
                $degisenler += ("{0}: v{1} -> v{2}" -f $yeni.Ad, $eski.Surum, $yeni.Surum)
            }
        }
        if ($degisenler.Count -gt 0) {
            Write-Log "Surumu degisen suruculer:" 'OK'
            foreach ($d in $degisenler) { Write-Log "  $d" 'OK' }
            $script:SurucuDegisen = $degisenler
        } else {
            Write-Log "Kurulum yapildi ama surum degisimi gorulmedi (yeniden baslatma sonrasi gorunebilir)" 'INFO'
        }
    }

    $r = $script:SurucuSonuc
    if ($r.Bulunan -eq 0) { Add-Ozet 'Suruculer' 'hepsi guncel - yeni surucu yok' }
    else {
        $metin = "{0} bulundu, {1} kuruldu, {2} basarisiz" -f $r.Bulunan, $r.Kurulan, $r.Basarisiz
        if ($r.YenidenBaslat) { $metin += " (yeniden baslatma gerekli)" }
        Add-Ozet 'Suruculer' $metin
    }
}
elseif ($Config.SuruculeriGuncelle -and $DryRun) {
    Write-Baslik "Surucu guncelleme (donanim ID'lerine gore)"
    Write-Log "[DRY] Donanim ID'leri WU'ya sorulup eski suruculer guncellenecekti" 'SKIP'
}

# Hala eski kalan suruculer: WU'da karsiligi olmayan, ureticiden gelmesi gereken
# suruculer burada gorunur -> OEM araci / elle mudahale gerekebilir.
if ($Config.SurucuRaporu -and -not $DryRun) {
    $esik = (Get-Date).AddYears(-3)
    $eskiler = @((Get-SurucuEnvanteri).Values |
        Where-Object {
            $_.Tarih -and $_.Tarih -lt $esik -and
            $_.Saglayici -and $_.Saglayici -notmatch 'Microsoft' -and   # Microsoft'un jenerik suruculeri hep eski tarihlidir
            $_.Sinif -notmatch 'Volume|LegacyDriver|SoftwareDevice|System|PrintQueue'
        } | Sort-Object Tarih)

    if ($eskiler.Count -gt 0) {
        Write-Log "3 yildan eski kalan suruculer (WU'da yenisi yok, ureticiden bakilmali):" 'INFO'
        # Ekran/log sismesin: en eski 12 tanesi yazilir, sayinin tamami ozette.
        foreach ($e in ($eskiler | Select-Object -First 12)) {
            Write-Log ("  {0,-45} v{1} ({2:yyyy-MM-dd}) [{3}]" -f `
                        ($e.Ad -replace '(.{45}).+','$1'), $e.Surum, $e.Tarih, $e.Saglayici)
        }
        if ($eskiler.Count -gt 12) { Write-Log ("  ... ve {0} tane daha" -f ($eskiler.Count - 12)) 'INFO' }
        Add-Ozet 'Eski kalan surucu' ("{0} adet 3 yildan eski (detay logda)" -f $eskiler.Count)
    } else {
        Write-Log "3 yildan eski surucu yok" 'OK'
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
    # Suruculer on planda halledildiyse arka planda TEKRAR aranmaz: Windows Update
    # ayni anda iki kurulum yurutmez (0x80240016) ve is bosuna iki kez yapilirdi.
    $suruculerDahil = [bool]($Config.SuruculeriGuncelle -and -not $Config.SurucuOnPlanda)

    # Arka plan surecinin calistiracagi bagimsiz betik. $suruculerDahil degeri
    # buraya gomulur; ana scriptin degiskenlerine erisimi yoktur.
    $wuBody = @"
`$ErrorActionPreference = 'SilentlyContinue'
function L(`$m){ "[{0}] {1}" -f (Get-Date -f 'HH:mm:ss'), `$m | Add-Content -Path '$wuLog' -Encoding UTF8 }
`$suruculerDahil = `$$suruculerDahil
`$s = `$null
try {
    L 'Guncelleme araniyor...'
    `$s = New-Object -ComObject Microsoft.Update.Session
    `$sonuc = `$s.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
    if (`$sonuc.Updates.Count -eq 0) { L 'Sistem guncel, guncelleme yok' }
    else {
        `$col = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach (`$u in `$sonuc.Updates) {
            `$surucuMu = (`$u.Categories | Where-Object { `$_.Name -match 'Driver|Surucu' }).Count -gt 0
            if (`$surucuMu -and -not `$suruculerDahil) { continue }
            if (-not `$u.EulaAccepted) { try { `$u.AcceptEula() } catch {} }
            [void]`$col.Add(`$u); L ('Sirada: ' + `$u.Title)
        }
        if (`$col.Count -eq 0) { L 'Uygulanacak guncelleme yok' }
        else {
            L ('' + `$col.Count + ' guncelleme indiriliyor...')
            `$d = `$s.CreateUpdateDownloader(); `$d.Updates = `$col; [void]`$d.Download()
            L 'Kuruluyor...'
            `$i = `$s.CreateUpdateInstaller(); `$i.Updates = `$col; `$ir = `$i.Install()
            L ('Sonuc kodu: ' + `$ir.ResultCode + '  YenidenBaslatma: ' + `$ir.RebootRequired)
        }
    }
} catch { L ('HATA: ' + `$_.Exception.Message) }

# Suruculer arka planda isteniyorsa: donanim ID'lerine gore ayri bir tarama.
# Istege bagli surucu guncellemeleri yalniz Microsoft Update servisinden gelir.
if (`$suruculerDahil -and `$s) {
    try {
        L 'Surucu taramasi (donanim ID) basliyor...'
        `$sm = New-Object -ComObject Microsoft.Update.ServiceManager
        `$msid = '7971f918-a847-4430-9279-4a52d1efe18d'
        if (-not (`$sm.Services | Where-Object { `$_.ServiceID -eq `$msid })) { [void]`$sm.AddService2(`$msid, 7, '') }
        `$ds = `$s.CreateUpdateSearcher()
        `$ds.ServerSelection = 3
        `$ds.ServiceID = `$msid
        `$dr = `$ds.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
        if (`$dr.Updates.Count -eq 0) { L 'Tum suruculer guncel' }
        else {
            `$dcol = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach (`$u in `$dr.Updates) {
                if (-not `$u.EulaAccepted) { try { `$u.AcceptEula() } catch {} }
                [void]`$dcol.Add(`$u); L ('Surucu: ' + `$u.Title)
            }
            `$dd = `$s.CreateUpdateDownloader(); `$dd.Updates = `$dcol; [void]`$dd.Download()
            `$di = `$s.CreateUpdateInstaller(); `$di.Updates = `$dcol; `$dir = `$di.Install()
            L ('Surucu sonucu: ' + `$dir.ResultCode + '  YenidenBaslatma: ' + `$dir.RebootRequired)
        }
    } catch { L ('SURUCU HATASI: ' + `$_.Exception.Message) }
}
L 'Bitti.'
"@
    try {
        Set-Content -Path $wuScript -Value $wuBody -Encoding UTF8
        # -Wait YOK -> fire-and-forget. Ayri surec, ana script kapansa da surer.
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$wuScript`""
        )
        Write-Log "Guncelleme arka planda BASLATILDI (beklenmiyor)" 'OK'
        Write-Log "Ilerleme: $wuLog" 'INFO'
        $script:UpdateLog = $wuLog
        Add-Ozet 'Windows guncelleme' 'arka planda calisiyor (asagidaki loga bakin)'
    } catch {
        Write-Log "Guncelleme arka plan sureci baslatilamadi: $($_.Exception.Message)" 'WARN'
        Add-Ozet 'Windows guncelleme' 'BASLATILAMADI'
    }
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

    $wg = Resolve-Winget
    if (-not $arac) {
        Write-Log "Bu marka icin ozel arac yok; suruculer Windows Update'ten gelir" 'INFO'
        Add-Ozet 'OEM surucu araci' 'bu marka icin gerekmiyor'
    }
    elseif (-not $wg) {
        Write-Log "winget yok, OEM araci kurulamadi: $arac" 'WARN'
        Add-Ozet 'OEM surucu araci' "winget yok -> $arac kurulamadi"
    }
    elseif ($DryRun) {
        Write-Log "[DRY] OEM araci kurulacak: $arac" 'SKIP'
    }
    else {
        Write-Host "  -> $arac kuruluyor ..." -ForegroundColor Gray
        & $wg install --id $arac --exact --silent --accept-package-agreements `
              --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Log "OEM araci kuruldu: $arac" 'OK'; Add-Ozet 'OEM surucu araci' "$arac kuruldu" }
        else { Write-Log "OEM araci kurulamadi (exit $LASTEXITCODE); elle kurulabilir" 'WARN'; Add-Ozet 'OEM surucu araci' "$arac KURULAMADI" }

        # --- Ureticinin aracini komut satirindan calistir ---
        # WU her zaman ureticinin en son surucusunu tasimaz (ozellikle BIOS, dok,
        # tus takimi, guc yonetimi surucusu). OEM araci bu boslugu kapatir.
        if ($Config.OemSurucuOtoUygula) {
            switch -Regex ($marka) {

                # Dell Command Update: tam otomatik, sessiz, yeniden baslatmasiz.
                'Dell' {
                    $dcu = Get-ChildItem "$env:ProgramFiles*\Dell\CommandUpdate\dcu-cli.exe" -ErrorAction SilentlyContinue |
                           Select-Object -First 1
                    if ($dcu) {
                        Write-Host "  -> Dell Command Update suruculeri uyguluyor ..." -ForegroundColor Gray
                        & $dcu.FullName /applyUpdates -reboot=disable 2>&1 | Out-Null
                        Write-Log "Dell surucu guncellemesi calistirildi (exit $LASTEXITCODE)" 'OK'
                        Add-Ozet 'OEM surucu guncellemesi' 'Dell Command Update calistirildi'
                    } else { Write-Log "dcu-cli bulunamadi; Dell araci elle calistirilmali" 'WARN' }
                    break
                }

                # Lenovo System Update: /CM ile sessiz tarama + kurulum.
                # -includerebootpackages 1,3,4 -> yeniden baslatma gerektirenler de
                # kurulur ama -noreboot ile makine kendiliginden kapanmaz.
                'Lenovo' {
                    $tvsu = Get-ChildItem "$env:ProgramFiles*\Lenovo\System Update\Tvsu.exe" -ErrorAction SilentlyContinue |
                            Select-Object -First 1
                    if ($tvsu) {
                        Write-Host "  -> Lenovo System Update suruculeri uyguluyor ..." -ForegroundColor Gray
                        & $tvsu.FullName /CM -search A -action INSTALL -includerebootpackages 1,3,4 -noicon -noreboot 2>&1 | Out-Null
                        Write-Log "Lenovo surucu guncellemesi calistirildi (exit $LASTEXITCODE)" 'OK'
                        Add-Ozet 'OEM surucu guncellemesi' 'Lenovo System Update calistirildi'
                    } else { Write-Log "Tvsu.exe bulunamadi; Lenovo araci elle calistirilmali" 'WARN' }
                    break
                }

                # HP: Support Assistant'in sessiz komut satiri yok. Bunun yerine HP'nin
                # resmi PowerShell kutuphanesi (HPCMSL) ile surucu Softpaq'leri
                # sessizce kurulur. Kutuphane yoksa/erisim yoksa sadece uyarilir.
                'HP|Hewlett' {
                    try {
                        if (-not (Get-Module -ListAvailable -Name HPCMSL)) {
                            Write-Host "  -> HP surucu kutuphanesi (HPCMSL) kuruluyor ..." -ForegroundColor Gray
                            Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction Stop | Out-Null
                            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
                            Install-Module HPCMSL -Force -AcceptLicense -Scope AllUsers -ErrorAction Stop
                        }
                        Import-Module HPCMSL -ErrorAction Stop
                        Write-Host "  -> HP surucu listesi (Softpaq) taraniyor ..." -ForegroundColor Gray
                        $sp = Get-SoftpaqList -Category Driver -ErrorAction Stop
                        Write-Log "HP: $($sp.Count) surucu paketi bulundu, kuruluyor..." 'INFO'
                        $hpOk = 0
                        foreach ($s in $sp) {
                            try { Get-Softpaq -Number $s.Id -Action Install -Overwrite yes -ErrorAction Stop | Out-Null; $hpOk++ }
                            catch { Write-Log "  HP paketi kurulamadi: $($s.Name)" 'WARN' }
                        }
                        Write-Log "HP surucu paketi kuruldu: $hpOk/$($sp.Count)" 'OK'
                        Add-Ozet 'OEM surucu guncellemesi' "HP: $hpOk surucu paketi kuruldu"
                    }
                    catch {
                        Write-Log "HP otomatik surucu guncellemesi yapilamadi: $($_.Exception.Message)" 'WARN'
                        Write-Log "HP Support Assistant kuruldu -> bir kez elle calistirin" 'INFO'
                        Add-Ozet 'OEM surucu guncellemesi' 'HP: elle calistirilmali'
                    }
                    break
                }

                default { Write-Log "Bu marka icin otomatik OEM surucu uygulamasi yok" 'INFO' }
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

#region ---------------------- SON RAPOR ----------------------

$sure = (Get-Date) - $script:Basla

Write-Host ""
Write-Host ("#" * 64) -ForegroundColor Green
Write-Host "  ISLEM TAMAMLANDI - OZET RAPOR" -ForegroundColor Green
Write-Host ("#" * 64) -ForegroundColor Green
Write-Host ""

Write-Host ("  Makine        : {0}" -f $env:COMPUTERNAME)
Write-Host ("  Cihaz tipi    : {0}" -f $(if ($script:Laptop) {'Laptop'} else {'Masaustu'}))
Write-Host ("  Sure          : {0:N0} dk {1:N0} sn" -f [math]::Floor($sure.TotalMinutes), $sure.Seconds)
Write-Host ("  Registry yazim: {0} deger" -f $script:Degisen)
Write-Host ""

if ($script:Ozet.Count -gt 0) {
    Write-Host "  YAPILANLAR" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
    foreach ($k in $script:Ozet.Keys) {
        $renk = if ("$($script:Ozet[$k])" -match 'KURULAMADI|BASLATILAMADI|DIKKAT|KRITIK|YIPRANMIS|bulunamadi|ayarlanamadi') { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,-26}: {1}" -f $k, $script:Ozet[$k]) -ForegroundColor $renk
    }
    Write-Host ""
}

if ($script:SurucuDegisen -and $script:SurucuDegisen.Count -gt 0) {
    Write-Host "  GUNCELLENEN SURUCULER" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
    foreach ($d in ($script:SurucuDegisen | Select-Object -First 15)) { Write-Host "  * $d" -ForegroundColor Green }
    if ($script:SurucuDegisen.Count -gt 15) {
        Write-Host ("  ... ve {0} tane daha (tamami log dosyasinda)" -f ($script:SurucuDegisen.Count - 15)) -ForegroundColor DarkGray
    }
    Write-Host ""
}

if ($script:Uyarilar.Count -gt 0) {
    Write-Host ("  BAKILMASI GEREKENLER ({0} uyari/hata)" -f $script:Uyarilar.Count) -ForegroundColor Yellow
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
    # Cok uzamasin: ilk 15 tanesi ekranda, tamami log dosyasinda.
    $goster = $script:Uyarilar | Select-Object -First 15
    foreach ($u in $goster) { Write-Host "  * $u" -ForegroundColor Yellow }
    if ($script:Uyarilar.Count -gt 15) {
        Write-Host ("  ... ve {0} tane daha (tamami log dosyasinda)" -f ($script:Uyarilar.Count - 15)) -ForegroundColor DarkGray
    }
    Write-Host ""
} else {
    Write-Host "  Uyari/hata yok - her sey temiz." -ForegroundColor Green
    Write-Host ""
}

Write-Host "  LOG DOSYALARI" -ForegroundColor Cyan
Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
Write-Host ("  Kurulum logu  : {0}" -f $script:LogFile)
if ($script:UpdateLog) {
    Write-Host ("  Guncelleme    : {0}" -f $script:UpdateLog)
    Write-Host "  (Windows guncellemesi ARKA PLANDA devam ediyor;" -ForegroundColor DarkGray
    Write-Host "   bu pencereyi kapatsaniz da surer.)" -ForegroundColor DarkGray
}
if ($script:SurucuSonuc -and $script:SurucuSonuc.YenidenBaslat) {
    Write-Host ""
    Write-Host "  ! Kurulan suruculerin devreye girmesi icin yeniden baslatma sart." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  YENIDEN BASLATMA GEREKIR" -ForegroundColor Yellow
Write-Host "  Uzun yol destegi, hizli baslatma, telemetri ve guncellemeler" -ForegroundColor Yellow
Write-Host "  ancak yeniden baslatmadan sonra tam etkili olur." -ForegroundColor Yellow
Write-Host ""
Write-Host ("#" * 64) -ForegroundColor Green

# Log dosyasina da ayni ozet yazilsin (sonradan bakildiginda ekran kaybolmus olur)
try {
    Add-Content -Path $script:LogFile -Encoding UTF8 -Value @(
        ""
        "===================== OZET RAPOR ====================="
        ("Sure: {0:N1} dk | Registry yazim: {1} | Uyari/hata: {2}" -f $sure.TotalMinutes, $script:Degisen, $script:Uyarilar.Count)
        ($script:Ozet.Keys | ForEach-Object { "  {0,-26}: {1}" -f $_, $script:Ozet[$_] })
        ($script:Uyarilar  | ForEach-Object { "  ! $_" })
    )
} catch {}

#endregion

#region ---------------------- BEKLEME ----------------------
# Pencere KENDILIGINDEN KAPANMAZ. Rapor okunabilsin diye kullanici kapatana
# kadar acik kalir. Otomasyonda (NinjaOne/GPO/Intune -> etkilesimsiz oturum,
# ya da -NoPause) beklemez; yoksa surec sonsuza kadar asili kalirdi.
if ($NoPause) {
    Write-Log "-NoPause verildi -> beklemeden kapaniyor" 'SKIP'
}
elseif (-not [Environment]::UserInteractive) {
    Write-Log "Etkilesimsiz oturum -> beklemeden kapaniyor" 'SKIP'
}
else {
    Write-Host ""
    Write-Host "  Bu pencere kendiliginden KAPANMAYACAK." -ForegroundColor Cyan
    Write-Host "  Raporu okuduktan sonra sag ustteki (X) ile kapatabilirsiniz." -ForegroundColor Cyan
    Write-Host "  Ya da kapatmak icin Enter'a basin." -ForegroundColor DarkGray
    Write-Host ""
    try { $null = Read-Host "  Devam etmek icin Enter" } catch { }
}

#endregion

exit 0

#endregion
