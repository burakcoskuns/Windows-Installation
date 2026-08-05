<#
.SYNOPSIS
    Windows 11 (24H2/25H2) uyumluluk denetimini gecemeyen makineler icin
    tani + atlatma (bypass) yardimcisi.

.DESCRIPTION
    Once makinenin HANGI gereksinimden kaldigini tespit eder, sonra o duruma
    uyan atlatma yontemini uygular:

      1) YERINDE YUKSELTME (makine acikken, Windows uzerinden kurulum)
         Uc anahtar birden yazilir:
         - HKLM\SYSTEM\Setup\MoSetup -> AllowUpgradesWithUnsupportedTPMOrCPU = 1
           Microsoft'un kendi belgeledigi (sonra yayindan kaldirdigi) anahtar.
         - HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\
           HwReqChk -> HwReqChkVars (MULTI_SZ) = SecureBoot/TPM 2.0/8 GB "var"
           24H2'nin yeni denetimi burayi okur; asil ise yarayan budur.
         - LabConfig (zarari yok, bazi senaryolarda setup bunu da okur)

      1b) SETUPPREP YOLU (en pratik yontem)
         sources\setupprep.exe /product server
         24H2'de eski `setup.exe /product server` "unknown command" verir;
         calisan komut setupprep.exe'dir. -SetupBaslat ile otomatik yapilir.

      2) TEMIZ KURULUM (USB'den kurulum, setup ekraninda)
         HKLM\SYSTEM\Setup\LabConfig -> BypassTPMCheck / BypassSecureBootCheck /
         BypassRAMCheck / BypassStorageCheck / BypassCPUCheck = 1
         Bunlar kurulum ortaminda (WinPE) gecerlidir. Iki yolu var:
           a) -UsbHazirla ile USB'ye autounattend.xml yazilir -> hicbir sey
              yapmadan, kurulum acilir acilmaz denetim atlanir (onerilen).
           b) Kurulum ekraninda Shift+F10 -> bu script -WinPE ile calistirilir.

    ATLANMAYAN TEK SEY: 24H2 ve sonrasi, islemcide SSE4.2 + POPCNT komut
    kumesini ZORUNLU tutar (yaklasik 2009 oncesi islemcilerde yoktur). Bu bir
    kurulum denetimi degil, cekirdegin kullandigi komuttur; hicbir registry
    hilesi ise yaramaz. Script bunu kernel32!IsProcessorFeaturePresent ile
    kesin olarak olcer ve bosuna ugrasmanizi engeller.

.PARAMETER YerindeYukseltme
    Calisan Windows'a MoSetup + HwReqChk + LabConfig anahtarlarini yazar.
    Ardindan ISO'yu baglayip setup.exe calistirin (ya da -SetupBaslat kullanin).

.PARAMETER SetupBaslat
    Yukseltmeyi dogrudan baslatir: ISO dosyasinin yolu (orn: C:\Win11.iso) ya da
    bagli ISO'nun surucu harfi (orn: F:). ISO yolunu verirseniz baglanir, isi
    bitince cikarilir. Icerideki sources\setupprep.exe /product server calisir.

.PARAMETER IsoIndir
    ISO'yu Microsoft'un sunucusundan indirir. Varsayilan hedef C:\Temp; klasor
    yoksa olusturulur. Orada 3 GB'tan buyuk bir ISO zaten varsa TEKRAR
    INDIRILMEZ, mevcut dosya kullanilir. Indirme basarisiz olursa elle indirme
    yonergesi yazilir. -SetupBaslat verilmediyse indirilen ISO otomatik kullanilir.
    FILO NOTU: her makineye 5-6 GB indirmek yerine bir kez indirip ag payina
    koyun; -SetupBaslat \\sunucu\pay\Win11.iso cok daha hizli ve guvenilirdir.

.PARAMETER IsoKlasor
    ISO'nun inecegi klasor (varsayilan: C:\Temp). Yoksa olusturulur.

.PARAMETER IsoDil
    Indirilecek ISO'nun dili (varsayilan: Turkish). Orn: 'English (United States)'.

.PARAMETER Sessiz
    -SetupBaslat ile birlikte: hicbir soru sormadan yukseltir. Dosyalar ve
    kurulu programlar KORUNUR (/auto upgrade). Makine kendiliginden yeniden
    baslatilmaz. Toplu/uzaktan (NinjaOne) kullanim icin.

.PARAMETER UsbHazirla
    Kurulum USB'sinin surucu harfi (orn: E:). Koke autounattend.xml yazar.

.PARAMETER WinPE
    Kurulum ekranindan (Shift+F10) calistirildiginda LabConfig anahtarlarini
    dogrudan yazar.

.PARAMETER DryRun
    Hicbir sey yazmaz, sadece ne yapacagini soyler.

.EXAMPLE
    .\Win11-UyumsuzDonanim.ps1                      # sadece rapor
    .\Win11-UyumsuzDonanim.ps1 -YerindeYukseltme    # anahtarlari yaz, kurulumu elle baslat
    .\Win11-UyumsuzDonanim.ps1 -YerindeYukseltme -SetupBaslat C:\Win11_24H2.iso
    .\Win11-UyumsuzDonanim.ps1 -YerindeYukseltme -IsoIndir           # C:\Temp'e indirip kurar
    .\Win11-UyumsuzDonanim.ps1 -YerindeYukseltme -IsoIndir -IsoKlasor D:\ISO -Sessiz
    .\Win11-UyumsuzDonanim.ps1 -UsbHazirla E:       # kurulum USB'sini hazirla
    X:\...\Win11-UyumsuzDonanim.ps1 -WinPE          # setup ekraninda Shift+F10

.NOTES
    KURUMSAL NOT: TPM/Secure Boot atlatilan makinede BitLocker/cihaz sifreleme
    ve sanallastirma tabanli guvenlik (VBS/Credential Guard) calismaz ya da
    zayiflar. Sirket cihazinda bunu bilerek yapin; mumkunse once BIOS'tan
    TPM ve Secure Boot'u ACIN (cogu makinede kapali geldigi icin denetimden
    kaliyor - script bunu da soyler).
#>

[CmdletBinding()]
param(
    [switch]$YerindeYukseltme,
    [string]$SetupBaslat,
    [switch]$IsoIndir,
    [string]$IsoKlasor = "$env:SystemDrive\Temp",
    [string]$IsoDil = 'Turkish',
    [switch]$Sessiz,
    [string]$UsbHazirla,
    [switch]$WinPE,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Yaz {
    param([string]$Msg, [ValidateSet('INFO','OK','WARN','ERR','SKIP')][string]$Level = 'INFO')
    $renk = switch ($Level) { 'OK'{'Green'} 'WARN'{'Yellow'} 'ERR'{'Red'} 'SKIP'{'DarkGray'} default{'Gray'} }
    Write-Host ("[{0,-4}] {1}" -f $Level, $Msg) -ForegroundColor $renk
}

function Baslik {
    param([string]$T)
    Write-Host ""
    Write-Host ("=" * 66) -ForegroundColor Cyan
    Write-Host "  $T" -ForegroundColor Cyan
    Write-Host ("=" * 66) -ForegroundColor Cyan
}

# WinPE (kurulum ortami) icinde miyiz? Orada sistem surucusu X: olur.
$script:PEdeyiz = ($env:SystemDrive -eq 'X:') -or (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')

# Yonetici kontrolu (WinPE zaten SYSTEM olarak calisir)
if (-not $script:PEdeyiz) {
    $kimlik = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$kimlik).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Yonetici hakki gerekiyor, yeniden baslatiliyor..." -ForegroundColor Yellow
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
        foreach ($k in $PSBoundParameters.Keys) {
            $v = $PSBoundParameters[$k]
            if ($v -is [switch] -and $v) { $argList += "-$k" }
            elseif ($v -isnot [switch])  { $argList += @("-$k", "`"$v`"") }
        }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        exit
    }
}

#region ==================== DONANIM TESPITI ====================

<#
    Test-SSE42: islemcide SSE4.2 var mi? 24H2'nin ATLANAMAYAN sarti.
    kernel32!IsProcessorFeaturePresent(38) = PF_SSE4_2_INSTRUCTIONS_AVAILABLE.
    Windows'un kendi cekirdegine sordugumuz icin sonuc kesindir (islemci adi
    tahmininden farkli olarak yanilmaz).
#>
function Test-SSE42 {
    try {
        if (-not ('Win32Cpu' -as [type])) {
            Add-Type -Namespace '' -Name 'Win32Cpu' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool IsProcessorFeaturePresent(uint feature);
'@
        }
        return [Win32Cpu]::IsProcessorFeaturePresent(38)
    } catch { return $null }   # olculemedi
}

function Get-DonanimDurumu {
    $d = [ordered]@{}

    # --- Kurulu Windows surumu (hangi build'den hangi build'e cikiyoruz) ---
    $d.OsAd = 'bilinmiyor'; $d.OsSurum = '?'; $d.OsBuild = '?'
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $d.OsAd    = $cv.ProductName
        $d.OsSurum = if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }
        $d.OsBuild = "$($cv.CurrentBuild).$($cv.UBR)"
        # Win11 22000+ build'dir; ProductName bazi makinelerde hala "Windows 10" der
        if ([int]$cv.CurrentBuild -ge 22000 -and $d.OsAd -notmatch '11') { $d.OsAd = $d.OsAd -replace '10','11' }
    } catch {}

    # --- Islemci ---
    $cpu = $null
    try { $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch {}
    $d.CpuAd       = if ($cpu) { $cpu.Name.Trim() } else { 'bilinmiyor' }
    $d.CpuCekirdek = if ($cpu) { [int]$cpu.NumberOfCores } else { 0 }
    $d.CpuMHz      = if ($cpu) { [int]$cpu.MaxClockSpeed } else { 0 }
    $d.SSE42       = Test-SSE42

    # --- Bellek ---
    try { $d.RamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1) } catch { $d.RamGB = 0 }

    # --- Sistem diski ---
    try {
        $sysDisk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
        $d.DiskGB = [math]::Round($sysDisk.Size / 1GB)
    } catch { $d.DiskGB = 0 }

    # --- UEFI / Secure Boot ---
    $d.UEFI = $false; $d.SecureBoot = $false
    try {
        $d.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
        $d.UEFI = $true      # komut calistiysa firmware UEFI demektir
    } catch {
        # "not supported on this platform" -> BIOS/Legacy; diger hatalar -> UEFI ama kapali
        if ("$($_.Exception.Message)" -match 'not supported|desteklenmiyor') { $d.UEFI = $false }
        else { $d.UEFI = $true }
    }
    if ($env:firmware_type) { $d.UEFI = ($env:firmware_type -eq 'UEFI') }

    # --- TPM ---
    $d.TpmVar = $false; $d.TpmSurum = 'yok'; $d.TpmAcik = $false
    try {
        $tpm = Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -Class Win32_Tpm -ErrorAction Stop
        if ($tpm) {
            $d.TpmVar    = $true
            $d.TpmAcik   = [bool]$tpm.IsEnabled_InitialValue
            # SpecVersion ornek: "2.0, 0, 1.38" -> ilk parca surumdur
            $d.TpmSurum  = ("$($tpm.SpecVersion)" -split ',')[0].Trim()
        }
    } catch {}

    return $d
}

function Goster-Rapor {
    param($d)

    Baslik "Donanim uyumluluk raporu"
    Write-Host ("  Islemci : {0}" -f $d.CpuAd)
    Write-Host ("  Bellek  : {0} GB   Sistem diski: {1} GB" -f $d.RamGB, $d.DiskGB)
    Write-Host ("  Windows : {0} (surum {1}, build {2})" -f $d.OsAd, $d.OsSurum, $d.OsBuild)
    Write-Host ""

    $satirlar = @()
    $satirlar += [pscustomobject]@{ Gereksinim='TPM 2.0';        Durum = $(if ($d.TpmVar) { "TPM $($d.TpmSurum)" + $(if (-not $d.TpmAcik) { ' (KAPALI)' }) } else { 'yok' }); Uygun = ($d.TpmVar -and $d.TpmSurum -like '2*' -and $d.TpmAcik); Atlanir = $true }
    $satirlar += [pscustomobject]@{ Gereksinim='Secure Boot';    Durum = $(if ($d.SecureBoot) { 'acik' } elseif ($d.UEFI) { 'kapali (UEFI var)' } else { 'Legacy BIOS' }); Uygun = $d.SecureBoot; Atlanir = $true }
    $satirlar += [pscustomobject]@{ Gereksinim='UEFI';           Durum = $(if ($d.UEFI) { 'UEFI' } else { 'Legacy/CSM' });            Uygun = $d.UEFI;            Atlanir = $true }
    $satirlar += [pscustomobject]@{ Gereksinim='RAM >= 4 GB';    Durum = "$($d.RamGB) GB";                                            Uygun = ($d.RamGB -ge 4);   Atlanir = $true }
    $satirlar += [pscustomobject]@{ Gereksinim='Disk >= 64 GB';  Durum = "$($d.DiskGB) GB";                                           Uygun = ($d.DiskGB -ge 64); Atlanir = $true }
    $satirlar += [pscustomobject]@{ Gereksinim='CPU 2 cekirdek'; Durum = "$($d.CpuCekirdek) cekirdek / $($d.CpuMHz) MHz";             Uygun = ($d.CpuCekirdek -ge 2 -and $d.CpuMHz -ge 1000); Atlanir = $true }
    $satirlar += [pscustomobject]@{ Gereksinim='CPU SSE4.2/POPCNT (24H2)'; Durum = $(if ($null -eq $d.SSE42) { 'olculemedi' } elseif ($d.SSE42) { 'var' } else { 'YOK' }); Uygun = ($d.SSE42 -ne $false); Atlanir = $false }

    foreach ($s in $satirlar) {
        $isaret = if ($s.Uygun) { 'OK  ' } elseif ($s.Atlanir) { 'ATLA' } else { 'DUR ' }
        $renk   = if ($s.Uygun) { 'Green' } elseif ($s.Atlanir) { 'Yellow' } else { 'Red' }
        Write-Host ("  [{0}] {1,-26} {2}" -f $isaret, $s.Gereksinim, $s.Durum) -ForegroundColor $renk
    }
    Write-Host ""
    Write-Host "  OK = sarti sagliyor · ATLA = saglamiyor ama bu script atlatabilir" -ForegroundColor DarkGray
    Write-Host "  DUR = saglamiyor ve ATLATILAMAZ" -ForegroundColor DarkGray

    return $satirlar
}

#endregion

#region ==================== ATLATMA ISLEMLERI ====================

function Set-BypassAnahtar {
    param([string]$Yol, [string]$Ad, [int]$Deger = 1)
    if ($DryRun) { Yaz "[DRY] $Yol\$Ad = $Deger" 'SKIP'; return }
    if (-not (Test-Path $Yol)) { New-Item -Path $Yol -Force | Out-Null }
    New-ItemProperty -Path $Yol -Name $Ad -Value $Deger -PropertyType DWord -Force | Out-Null
    Yaz "$Ad = $Deger  ($Yol)" 'OK'
}

# Kurulum ortaminda (WinPE) gecerli olan denetim atlatmalari.
function Set-LabConfig {
    $yol = 'HKLM:\SYSTEM\Setup\LabConfig'
    foreach ($ad in @('BypassTPMCheck','BypassSecureBootCheck','BypassRAMCheck','BypassStorageCheck','BypassCPUCheck')) {
        Set-BypassAnahtar $yol $ad 1
    }
}

# Calisan Windows uzerinden yukseltme icin Microsoft'un kendi anahtari.
function Set-MoSetup {
    Set-BypassAnahtar 'HKLM:\SYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 1
}

<#
    Set-HwReqChk: 24H2'nin yeni donanim denetimini (HwReqChk) kandirir.

    Setup, denetim sonuclarini bu MULTI_SZ degerden okur; buraya "Secure Boot
    var, TPM 2.0 var, 8 GB RAM var" yazilinca denetim gecmis sayilir. 24H2'de
    LabConfig/MoSetup'in yetmedigi durumlarin cogunu bu cozer.
    (Neowin rehberindeki "Option 2" budur.)
#>
function Set-HwReqChk {
    $yol = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk'
    $deger = @(
        'SQ_SecureBootCapable=TRUE'
        'SQ_SecureBootEnabled=TRUE'
        'SQ_TpmVersion=2'
        'SQ_RamMB=8192'
    )
    if ($DryRun) { Yaz "[DRY] $yol\HwReqChkVars = $($deger -join ' | ')" 'SKIP'; return }
    if (-not (Test-Path $yol)) { New-Item -Path $yol -Force | Out-Null }
    New-ItemProperty -Path $yol -Name 'HwReqChkVars' -Value $deger -PropertyType MultiString -Force | Out-Null
    Yaz "HwReqChkVars yazildi (SecureBoot/TPM 2.0/8 GB RAM sagliyor gibi gorunur)" 'OK'
}

<#
    Get-Win11Iso: Windows 11 ISO'sunu MICROSOFT'UN KENDI SUNUCUSUNDAN indirir.

    Nasil: microsoft.com/software-download/windows11 sayfasinin arkasindaki
    indirme servisi taklit edilir (tarayicida "surum sec > dil sec > indir"
    adimlarinin yaptigi seyin aynisi):
      1) Sayfadan guncel ProductEditionId okunur (sabit yazmiyoruz; her yeni
         surumde degistigi icin sayfadan okumak tek saglam yol)
      2) Oturum kaydedilir, dil listesi alinir
      3) Secilen dilin x64 ISO baglantisi alinir ve indirilir

    DIKKAT: Bu servis Microsoft'un BELGELENMEMIS ucudur. Microsoft yapisini
    degistirirse ya da IP'yi engellerse (veri merkezi/VPN IP'lerini sik sik
    engelliyor) calismaz. O yuzden basarisiz olursa script elle indirme
    yonergesini yazar; is durmaz.

    FILO ONERISI: 5-6 GB'lik ISO'yu her makineye indirmek yerine BIR KEZ indirip
    ag payina koyun ve -SetupBaslat \\sunucu\pay\Win11.iso kullanin.
#>
function Get-Win11Iso {
    param(
        [Parameter(Mandatory)][string]$Hedef,
        [string]$Dil = 'Turkish'
    )

    if (-not (Test-Path $Hedef)) {
        if ($DryRun) { Yaz "[DRY] Klasor olusturulacak: $Hedef" 'SKIP' }
        else {
            New-Item -ItemType Directory -Path $Hedef -Force | Out-Null
            Yaz "Klasor olusturuldu: $Hedef" 'OK'
        }
    }

    # ISO 5-6 GB; yer yoksa yarida kalir. Onceden bakip net soyleyelim.
    try {
        $surucu = (Split-Path -Qualifier (Resolve-Path $Hedef -ErrorAction SilentlyContinue)) -replace ':',''
        if ($surucu) {
            $bosGB = [math]::Round((Get-PSDrive -Name $surucu -ErrorAction Stop).Free / 1GB, 1)
            if ($bosGB -lt 10) {
                Yaz "$surucu`: surucusunde sadece $bosGB GB bos yer var; ISO icin 8-10 GB gerekir." 'WARN'
            } else { Yaz "Bos disk alani: $bosGB GB" 'INFO' }
        }
    } catch {}

    # Zaten indirilmis mi? Chrome'da oldugu gibi: varsa tekrar indirme.
    $mevcut = Get-ChildItem -LiteralPath $Hedef -Filter '*.iso' -ErrorAction SilentlyContinue |
              Where-Object { $_.Length -gt 3GB } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($mevcut) {
        Yaz "ISO zaten var, tekrar indirilmiyor: $($mevcut.Name) ($([math]::Round($mevcut.Length/1GB,1)) GB)" 'SKIP'
        return $mevcut.FullName
    }

    if ($DryRun) { Yaz "[DRY] Microsoft'tan Windows 11 ISO ($Dil) indirilecek -> $Hedef" 'SKIP'; return $null }

    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
    $oturum = [guid]::NewGuid().ToString()
    $eskiPB = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # 1) Guncel surumun ProductEditionId'si sayfadan okunur
        Yaz "Microsoft indirme sayfasi okunuyor..." 'INFO'
        $sayfa = Invoke-WebRequest -Uri 'https://www.microsoft.com/en-us/software-download/windows11' `
                    -UseBasicParsing -UserAgent $ua -TimeoutSec 60
        $idler = [regex]::Matches($sayfa.Content, 'value="(\d{3,5})"[^>]*>\s*Windows 11') |
                 ForEach-Object { $_.Groups[1].Value }
        if (-not $idler) {
            # Yedek kalip: option listesi bazen farkli siralanir
            $idler = [regex]::Matches($sayfa.Content, '<option[^>]*value="(\d{3,5})"') |
                     ForEach-Object { $_.Groups[1].Value }
        }
        $urunId = $idler | Select-Object -Last 1
        if (-not $urunId) { throw "Sayfadan surum kimligi (ProductEditionId) okunamadi" }
        Yaz "Surum kimligi: $urunId" 'OK'

        # 2) Oturum kaydi (bu adim atlanirsa servis 715-123130 hatasi verir)
        try {
            Invoke-WebRequest -Uri "https://vlscppe.microsoft.com/fp/tags?org_id=y6jn8c31&session_id=$oturum" `
                -UseBasicParsing -UserAgent $ua -TimeoutSec 30 | Out-Null
        } catch {}

        # 3) Dil listesi
        $skuUrl = "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition" +
                  "?profile=606624d44113&ProductEditionId=$urunId&SKU=undefined&friendlyFileName=undefined&Locale=en-US&sessionID=$oturum"
        $sku = Invoke-RestMethod -Uri $skuUrl -UseBasicParsing -UserAgent $ua -TimeoutSec 60

        $secili = $sku.Skus | Where-Object { $_.LocalizedLanguage -eq $Dil -or $_.Language -eq $Dil } | Select-Object -First 1
        if (-not $secili) {
            Yaz "'$Dil' bulunamadi, Ingilizce secildi. Mevcut diller: $(($sku.Skus.LocalizedLanguage | Select-Object -First 8) -join ', ') ..." 'WARN'
            $secili = $sku.Skus | Where-Object { $_.LocalizedLanguage -match 'English \(United States\)' } | Select-Object -First 1
        }
        if (-not $secili) { throw "Dil secilemedi" }
        Yaz "Dil: $($secili.LocalizedLanguage)" 'OK'

        # 4) Indirme baglantisi (24 saat gecerli, oturuma bagli)
        $linkUrl = "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku" +
                   "?profile=606624d44113&productEditionId=undefined&SKU=$($secili.Id)&friendlyFileName=undefined&Locale=en-US&sessionID=$oturum"
        $link = Invoke-RestMethod -Uri $linkUrl -UseBasicParsing -UserAgent $ua -TimeoutSec 60

        if ($link.Errors) {
            $hataMetni = "$($link.Errors[0].Value)"
            # "Sentinel ... rejected" = IP tabanli engel. Microsoft veri merkezi,
            # VPN ve bazi kurumsal proxy cikislarini engelliyor; ev/ofis
            # baglantisindan ayni istek gecer.
            if ($hataMetni -match 'Sentinel|reject') {
                throw "Microsoft bu baglantiyi reddetti (VPN / veri merkezi / proxy IP'si olabilir): $hataMetni"
            }
            throw "Microsoft servisi reddetti: $hataMetni"
        }
        $x64 = $link.ProductDownloadOptions | Where-Object { $_.Uri -match 'x64' } | Select-Object -First 1
        if (-not $x64) { $x64 = $link.ProductDownloadOptions | Select-Object -First 1 }
        if (-not $x64.Uri) { throw "Indirme baglantisi alinamadi" }

        $dosyaAd = [IO.Path]::GetFileName(($x64.Uri -split '\?')[0])
        if (-not $dosyaAd -or $dosyaAd -notmatch '\.iso$') { $dosyaAd = "Win11_$urunId.iso" }
        $hedefDosya = Join-Path $Hedef $dosyaAd

        Yaz "Indiriliyor (5-6 GB, baglantiya gore 10-60 dk): $dosyaAd" 'INFO'
        $sw = [Diagnostics.Stopwatch]::StartNew()

        # BITS varsa onu kullan: kesintide kaldigi yerden devam eder ve ilerleme gosterir
        $bits = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
        if ($bits) { Start-BitsTransfer -Source $x64.Uri -Destination $hedefDosya -Description 'Windows 11 ISO' }
        else       { Invoke-WebRequest -Uri $x64.Uri -OutFile $hedefDosya -UseBasicParsing -UserAgent $ua }
        $sw.Stop()

        $boyutGB = [math]::Round((Get-Item $hedefDosya).Length / 1GB, 2)
        if ($boyutGB -lt 3) { throw "Indirilen dosya cok kucuk ($boyutGB GB) - eksik indi" }
        Yaz ("ISO indirildi: {0} ({1} GB, {2:N0} dk)" -f $dosyaAd, $boyutGB, $sw.Elapsed.TotalMinutes) 'OK'
        return $hedefDosya
    }
    catch {
        Yaz "ISO otomatik indirilemedi: $($_.Exception.Message)" 'ERR'
        Write-Host ""
        if ("$($_.Exception.Message)" -match 'reddetti|Sentinel') {
            Yaz "Bu bir IP engeli - script hatasi degil. VPN acilsa kapatin, ya da" 'WARN'
            Yaz "kurumsal proxy disinda bir baglantidan bir kez indirip paya koyun." 'WARN'
            Write-Host ""
        }
        Yaz "Elle indirme (1 kez yapip ag payina koymak en saglami):" 'INFO'
        Yaz "  https://www.microsoft.com/software-download/windows11 > 'Disk Image (ISO)'" 'INFO'
        Yaz "  ya da Rufus (rufus.ie) icindeki ISO indirme dugmesi" 'INFO'
        Yaz "Sonra: -SetupBaslat <ISO yolu> ile devam edin." 'INFO'
        return $null
    }
    finally { $ProgressPreference = $eskiPB }
}

<#
    Start-SetupPrep: yukseltmeyi ureticinin "sunucu urunu" yolundan baslatir.

    24H2'de eski `setup.exe /product server` numarasi "unknown command" verir;
    calisan komut sources klasorundeki setupprep.exe'dir. Ekranda "Windows
    Server" yazar ama kurulan sey mevcut surumunuzun normal karsiligidir.
    (Neowin rehberindeki "Option 1" budur.)
#>
function Start-SetupPrep {
    param(
        [Parameter(Mandatory)][string]$Kaynak,
        [switch]$Sessiz          # hic soru sormadan, dosyalar+programlar korunarak yukselt
    )

    $harf = $null
    $baglandi = $false
    try {
        # Klasor/surucu verildiyse: once "bu zaten kurulum medyasi mi?" diye bak
        # (bagli ISO ya da USB -> sources\setupprep.exe icerir). Degilse, icinde
        # ISO ariyoruz. Sira onemli: F: gibi bagli bir medyada ISO aramak yanlis
        # olurdu.
        if ((Test-Path -LiteralPath $Kaynak -PathType Container -ErrorAction SilentlyContinue) -and
            -not (Test-Path -LiteralPath ("$($Kaynak.TrimEnd('\'))\sources\setupprep.exe") -ErrorAction SilentlyContinue)) {
            $bulunan = Get-ChildItem -LiteralPath $Kaynak -Filter '*.iso' -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($bulunan) { Yaz "Klasorde ISO bulundu: $($bulunan.Name)" 'OK'; $Kaynak = $bulunan.FullName }
            else { Yaz "Bu klasorde ne kurulum medyasi ne de ISO var: $Kaynak" 'ERR'; return }
        }

        if ($Kaynak -match '\.iso$') {
            if (-not (Test-Path $Kaynak)) { Yaz "ISO bulunamadi: $Kaynak" 'ERR'; return }
            if ($DryRun) { Yaz "[DRY] ISO baglanip setupprep.exe /product server calistirilacak" 'SKIP'; return }
            Yaz "ISO baglaniyor: $Kaynak" 'INFO'
            $img = Mount-DiskImage -ImagePath (Resolve-Path $Kaynak).Path -PassThru
            Start-Sleep -Seconds 2
            $harf = ($img | Get-Volume).DriveLetter + ':'
            $baglandi = $true
            Yaz "ISO baglandi: $harf" 'OK'
        } else {
            # Yalniz tek harf verildiyse iki nokta eklenir ("F" -> "F:").
            # "F:", "C:\medya" ve "\\sunucu\pay" oldugu gibi birakilir.
            $harf = $Kaynak.TrimEnd('\')
            if ($harf -match '^[A-Za-z]$') { $harf = "$harf`:" }
        }

        # Join-Path kullanilmaz: olmayan bir surucu harfi verilirse ("Cannot find
        # drive F") anlamsiz bir hata firlatir. Duz birlestirip Test-Path ile
        # sessizce kontrol etmek daha net bir mesaj verir.
        $prep = "$harf\sources\setupprep.exe"
        if (-not (Test-Path -LiteralPath $prep -ErrorAction SilentlyContinue)) {
            Yaz "setupprep.exe bulunamadi: $prep" 'ERR'
            Yaz "ISO'yu baglayip surucu harfini verin (orn: -SetupBaslat F:) ya da" 'INFO'
            Yaz "dogrudan ISO dosyasinin yolunu verin (orn: -SetupBaslat C:\Win11.iso)" 'INFO'
            return
        }
        # Sessiz mod: hicbir soru sorulmadan yukseltir.
        #   /auto upgrade  -> dosyalar VE programlar korunur (temiz kurulum degil)
        #   /quiet         -> arayuz yok
        #   /noreboot      -> makineyi biz kapatmayiz, zamanlamasi sizde kalir
        #   /compat ignorewarning -> "su program uyumsuz olabilir" uyarilarinda durmaz
        #   /dynamicupdate disable -> kurulum sirasinda WU'dan ek paket cekmez;
        #                             cekseydi denetim bilesenleri tazelenip
        #                             atlatmayi bozabilirdi (ve cok uzardi)
        $argumanlar = @('/product','server')
        if ($Sessiz) {
            $argumanlar += @('/auto','upgrade','/quiet','/eula','accept','/noreboot',
                             '/compat','ignorewarning','/dynamicupdate','disable')
        }

        if ($DryRun) { Yaz "[DRY] Calistirilacak: $prep $($argumanlar -join ' ')" 'SKIP'; return }

        Yaz "Calistiriliyor: setupprep.exe $($argumanlar -join ' ')" 'OK'
        Yaz "Ekranda 'Windows Server' yazacak - normaldir, mevcut surumunuz kurulur." 'INFO'
        if ($Sessiz) {
            Yaz "SESSIZ YUKSELTME: 30-60 dk surer, ekranda bir sey gorunmez." 'WARN'
            Yaz "Bitince makine kendiliginden yeniden BASLATILMAZ; siz baslatacaksiniz." 'WARN'
        }
        # Setup ayri surectir; ISO'yu erken cikarmamak icin BEKLENIR.
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $p = Start-Process -FilePath $prep -ArgumentList $argumanlar -Wait -PassThru
        $sw.Stop()

        # setup.exe cikis kodlari: 0 = tamam, 0x3010 (12304) = yeniden baslatma gerekli
        switch ($p.ExitCode) {
            0     { Yaz ("Yukseltme tamamlandi ({0:N0} dk)" -f $sw.Elapsed.TotalMinutes) 'OK' }
            12304 { Yaz ("Yukseltme tamamlandi, YENIDEN BASLATMA gerekiyor ({0:N0} dk)" -f $sw.Elapsed.TotalMinutes) 'OK' }
            default {
                Yaz ("Kurulum {0} kodu ile bitti ({1:N0} dk)" -f $p.ExitCode, $sw.Elapsed.TotalMinutes) 'WARN'
                Yaz "Ayrinti: C:\`$WINDOWS.~BT\Sources\Panther\setupact.log" 'INFO'
            }
        }
    }
    catch { Yaz "setupprep baslatilamadi: $($_.Exception.Message)" 'ERR' }
    finally {
        if ($baglandi) {
            Yaz "ISO baglantisi kaldiriliyor" 'INFO'
            try { Dismount-DiskImage -ImagePath (Resolve-Path $Kaynak).Path | Out-Null } catch {}
        }
    }
}

<#
    New-AutounattendBypass: kurulum USB'sinin kokune autounattend.xml yazar.
    Setup, windowsPE asamasinda bu dosyayi otomatik okur ve icindeki reg
    komutlarini DENETIMDEN ONCE calistirir -> Shift+F10 ile elle ugrasmak
    gerekmez. Sadece bypass komutlari var; kurulumun geri kalani normal
    ilerler (dil, disk secimi vb. yine size sorulur).
#>
function New-AutounattendBypass {
    param([Parameter(Mandatory)][string]$Kok)

    $komutlar = @(
        'reg add HKLM\System\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f'
        'reg add HKLM\System\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f'
        'reg add HKLM\System\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f'
        'reg add HKLM\System\Setup\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f'
        'reg add HKLM\System\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f'
        'reg add HKLM\System\Setup\MoSetup /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f'
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine('<unattend xmlns="urn:schemas-microsoft-com:unattend">')
    [void]$sb.AppendLine('  <settings pass="windowsPE">')
    [void]$sb.AppendLine('    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">')
    [void]$sb.AppendLine('      <RunSynchronous>')
    $sira = 0
    foreach ($k in $komutlar) {
        $sira++
        [void]$sb.AppendLine('        <RunSynchronousCommand wcm:action="add">')
        [void]$sb.AppendLine("          <Order>$sira</Order>")
        [void]$sb.AppendLine("          <Path>$k</Path>")
        [void]$sb.AppendLine('        </RunSynchronousCommand>')
    }
    [void]$sb.AppendLine('      </RunSynchronous>')
    [void]$sb.AppendLine('    </component>')
    [void]$sb.AppendLine('  </settings>')
    [void]$sb.AppendLine('</unattend>')

    $hedef = Join-Path $Kok 'autounattend.xml'
    if ($DryRun) { Yaz "[DRY] Yazilacak: $hedef" 'SKIP'; return }

    # Uzerine yazmadan once mevcut dosyayi yedekle: USB'de baska bir cevap
    # dosyasi olabilir, sessizce ezmek istemeyiz.
    if (Test-Path $hedef) {
        $yedek = Join-Path $Kok ('autounattend.xml.yedek')
        Copy-Item $hedef $yedek -Force
        Yaz "Mevcut autounattend.xml yedeklendi -> $yedek" 'WARN'
    }
    # UTF8 BOM'suz: setup BOM'lu dosyada bazen takilir
    [IO.File]::WriteAllText($hedef, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
    Yaz "autounattend.xml yazildi -> $hedef" 'OK'

    # Shift+F10 yolunu tercih edenler icin ayrica .reg dosyasi birakilir
    $reg = @(
        'Windows Registry Editor Version 5.00'
        ''
        '[HKEY_LOCAL_MACHINE\SYSTEM\Setup\LabConfig]'
        '"BypassTPMCheck"=dword:00000001'
        '"BypassSecureBootCheck"=dword:00000001'
        '"BypassRAMCheck"=dword:00000001'
        '"BypassStorageCheck"=dword:00000001'
        '"BypassCPUCheck"=dword:00000001'
        ''
        '[HKEY_LOCAL_MACHINE\SYSTEM\Setup\MoSetup]'
        '"AllowUpgradesWithUnsupportedTPMOrCPU"=dword:00000001'
    )
    $regYol = Join-Path $Kok 'Bypass-Denetim.reg'
    Set-Content -Path $regYol -Value $reg -Encoding Unicode
    Yaz "Yedek yontem icin .reg birakildi -> $regYol (Shift+F10 > regedit ile ice aktarin)" 'INFO'
}

#endregion

#region ==================== AKIS ====================

Baslik "Windows 11 uyumsuz donanim yardimcisi"
if ($script:PEdeyiz) { Yaz "Kurulum ortami (WinPE) tespit edildi" 'INFO' }
if ($DryRun)         { Yaz "DRY RUN - hicbir degisiklik yapilmayacak" 'WARN' }

$donanim = Get-DonanimDurumu
$satirlar = Goster-Rapor $donanim

# --- ATLATILAMAYAN durum: 24H2 icin SSE4.2 ---
if ($donanim.SSE42 -eq $false) {
    Baslik "DUR: bu makineye 24H2 / 25H2 KURULAMAZ"
    Yaz "Islemcide SSE4.2 + POPCNT komut kumesi yok (yaklasik 2009 oncesi islemci)." 'ERR'
    Yaz "Bu bir kurulum denetimi degil, cekirdegin kullandigi komuttur:" 'ERR'
    Yaz "registry hilesi, Rufus, autounattend - hicbiri ise yaramaz; kurulsa bile acilmaz." 'ERR'
    Write-Host ""
    Yaz "Yapilabilecekler: makineyi 23H2'de birakmak (destek suresi doluyor)," 'INFO'
    Yaz "Windows 10 ESU almak ya da donanimi yenilemek." 'INFO'
    if (-not $YerindeYukseltme -and -not $UsbHazirla -and -not $WinPE) { exit 1 }
    Yaz "Yine de istediginiz islem uygulanacak (bosa gitmesi muhtemel)." 'WARN'
}

# --- Zaten uyumlu mu? ---
$eksikler = @($satirlar | Where-Object { -not $_.Uygun })
if ($eksikler.Count -eq 0) {
    Yaz "Bu makine tum sartlari sagliyor - atlatmaya gerek yok." 'OK'
}
else {
    # BIOS'tan acmakla cozulecek seyi registry ile atlatmak yanlis: once bunu soyle.
    $tpmKapali    = ($donanim.TpmVar -and -not $donanim.TpmAcik)
    $sbKapaliAma  = ($donanim.UEFI -and -not $donanim.SecureBoot)
    if ($tpmKapali -or $sbKapaliAma) {
        Baslik "ONCE BUNU DENEYIN (atlatmadan cozulur)"
        if ($tpmKapali)   { Yaz "TPM makinede VAR ama KAPALI -> BIOS/UEFI > Security > TPM / PTT / fTPM = Enabled" 'WARN' }
        if ($sbKapaliAma) { Yaz "UEFI var, Secure Boot kapali -> BIOS > Boot > Secure Boot = Enabled (CSM/Legacy kapatilir)" 'WARN' }
        Yaz "Bunlari acinca makine cogu zaman DESTEKLENEN duruma gecer; guvenlik de korunur." 'INFO'
        Write-Host ""
    }
}

# --- Islemler ---
$islemYapildi = $false

if ($YerindeYukseltme) {
    Baslik "Yerinde yukseltme icin anahtarlar yaziliyor"
    Set-MoSetup
    Set-HwReqChk       # 24H2'nin yeni denetimi asil burayi okur
    Set-LabConfig      # zarari yok; bazi senaryolarda setup bunlari da okur
    $islemYapildi = $true
    if (-not $SetupBaslat) {
        Write-Host ""
        Yaz "Sirada: Windows 11 ISO'sunu indirin, cift tiklayip baglayin (mount)," 'INFO'
        Yaz "surucudeki setup.exe'yi calistirin ve 'Kisisel dosyalari ve uygulamalari koru' secin." 'INFO'
        Yaz "Takilirsa: -SetupBaslat <ISO yolu> ile setupprep.exe /product server yolunu deneyin." 'INFO'
    }
}

if ($IsoIndir) {
    Baslik "Windows 11 ISO indiriliyor -> $IsoKlasor"
    $indirilen = Get-Win11Iso -Hedef $IsoKlasor -Dil $IsoDil
    if ($indirilen) {
        # Ayrica -SetupBaslat verilmediyse indirilen ISO dogrudan kullanilir
        if (-not $SetupBaslat) { $SetupBaslat = $indirilen }
    } else {
        $islemYapildi = $true   # rapor/yonerge verildi; "ne yapmali" listesini tekrarlama
    }
}

if ($SetupBaslat) {
    Baslik "Kurulum baslatiliyor (setupprep.exe /product server)"
    # Anahtarlar yazilmadan setupprep tek basina da cogu makinede yeter, ama
    # ikisi birlikte en yuksek basari sansini verir.
    if (-not $YerindeYukseltme) {
        Yaz "Once denetim anahtarlari da yaziliyor (garanti olsun)" 'INFO'
        Set-MoSetup; Set-HwReqChk
    }
    Start-SetupPrep -Kaynak $SetupBaslat -Sessiz:$Sessiz
    $islemYapildi = $true

    # Indirilen ISO diskte kaliyor: bilerek silmiyoruz (kurulum yarim kalirsa
    # tekrar indirmek gerekmesin). Yer sikintisi olursa kullanici silsin.
    if ($indirilen) {
        Write-Host ""
        Yaz "ISO burada duruyor: $indirilen" 'INFO'
        Yaz "Yukseltme bittiyse silip 5-6 GB yer acabilirsiniz." 'INFO'
    }
}
elseif ($Sessiz) {
    Yaz "-Sessiz tek basina bir sey yapmaz; -SetupBaslat <ISO> ile birlikte kullanin." 'WARN'
}

if ($WinPE -or ($script:PEdeyiz -and -not $YerindeYukseltme -and -not $UsbHazirla)) {
    Baslik "Kurulum ortami icin denetim atlatiliyor"
    Set-LabConfig
    $islemYapildi = $true
    Write-Host ""
    Yaz "Simdi bu pencereyi kapatip kuruluma devam edin (geri > ileri yapmaniz gerekebilir)." 'INFO'
}

if ($UsbHazirla) {
    Baslik "Kurulum USB'si hazirlaniyor: $UsbHazirla"
    $kok = $UsbHazirla.TrimEnd('\')
    if ($kok -notmatch ':$' -and $kok -notmatch '\\') { $kok = "$kok`:" }
    if (-not (Test-Path $kok)) {
        Yaz "Surucu bulunamadi: $kok" 'ERR'
    }
    elseif (-not (Test-Path (Join-Path $kok 'setup.exe'))) {
        Yaz "Bu surucude setup.exe yok - Windows kurulum medyasi degil gibi gorunuyor." 'WARN'
        Yaz "Yine de autounattend.xml yaziliyor; yanlis surucu ise dosyayi silin." 'WARN'
        New-AutounattendBypass -Kok $kok
        $islemYapildi = $true
    }
    else {
        New-AutounattendBypass -Kok $kok
        $islemYapildi = $true
        Write-Host ""
        Yaz "USB hazir. Makineyi bu USB'den baslatin; denetim otomatik atlanacak." 'OK'
    }
}

#endregion

#region ==================== YOL HARITASI ====================

if (-not $islemYapildi) {
    Baslik "Ne yapmali?"
    Write-Host "  ONEMLI: Uyumsuz makineye Windows Update ASLA yeni build (24H2/25H2)" -ForegroundColor Yellow
    Write-Host "  teklif etmez - sadece aylik guncellemeler gelir. Yeni build icin ISO sart." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  0) ISO yoksa script kendisi indirsin:" -ForegroundColor White
    Write-Host "       .\Win11-UyumsuzDonanim.ps1 -YerindeYukseltme -IsoIndir" -ForegroundColor Gray
    Write-Host "       C:\Temp'e iner (klasor yoksa acilir), anahtarlari yazar, kurulumu baslatir" -ForegroundColor DarkGray
    Write-Host "       baska klasor icin: -IsoKlasor D:\ISO" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1) Mevcut Windows'u yukseltmek (dosyalar/programlar kalsin):" -ForegroundColor White
    Write-Host "       .\Win11-UyumsuzDonanim.ps1 -YerindeYukseltme -SetupBaslat C:\Win11_24H2.iso" -ForegroundColor Gray
    Write-Host "       anahtarlari yazar + setupprep.exe /product server ile kurulumu baslatir" -ForegroundColor DarkGray
    Write-Host "       (sadece anahtar yazip elle kurmak icin -SetupBaslat vermeyin)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1b) Toplu / uzaktan, hic soru sormadan (NinjaOne vb.):" -ForegroundColor White
    Write-Host "       .\Win11-UyumsuzDonanim.ps1 -YerindeYukseltme -SetupBaslat \\sunucu\pay\Win11.iso -Sessiz" -ForegroundColor Gray
    Write-Host "       30-60 dk surer, ekranda bir sey gorunmez, makineyi kendisi baslatmaz" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2) Sifirdan kurulum (USB ile):" -ForegroundColor White
    Write-Host "       .\Win11-UyumsuzDonanim.ps1 -UsbHazirla E:" -ForegroundColor Gray
    Write-Host "       USB'yi Media Creation Tool/Rufus ile hazirlayin, sonra bu komutu calistirin" -ForegroundColor DarkGray
    Write-Host "       Rufus kullaniyorsaniz zaten 'Remove requirement for 4GB+ RAM, Secure Boot" -ForegroundColor DarkGray
    Write-Host "       and TPM 2.0' kutusunu isaretlemeniz yeterli - bu adim gerekmez." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3) Kurulum ekraninda takildiysaniz (Shift+F10 ile komut istemi):" -ForegroundColor White
    Write-Host "       reg add HKLM\System\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f" -ForegroundColor Gray
    Write-Host "       reg add HKLM\System\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  NOT: 24H2'de artik CALISMAYAN yontemler -> setup.exe /product server," -ForegroundColor DarkGray
    Write-Host "  Installation Assistant uyumluluk sorun gidericisi, .reg birlestirme." -ForegroundColor DarkGray
}

Baslik "Bilinmesi gerekenler"
Yaz "Desteklenmeyen donanimda kurulan Windows 11 'destek disi' sayilir; masaustunde" 'INFO'
Yaz "filigran cikabilir ve Microsoft guncelleme garantisi vermez (pratikte guncellemeler gelir)." 'INFO'
Yaz "TPM/Secure Boot atlatilirsa BitLocker ve VBS gibi guvenlik ozellikleri calismaz." 'WARN'
Yaz "Sirket cihazinda once BIOS'tan TPM/Secure Boot acmayi deneyin - dogru cozum odur." 'WARN'

if (-not $script:PEdeyiz -and [Environment]::UserInteractive) {
    Write-Host ""
    Write-Host "  Pencere kendiliginden kapanmayacak. Okuyunca (X) ile kapatabilirsiniz." -ForegroundColor Cyan
    try { $null = Read-Host "  Devam etmek icin Enter" } catch {}
}

#endregion
