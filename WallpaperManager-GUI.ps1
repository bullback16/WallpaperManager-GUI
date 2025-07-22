Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    public const int SPI_SETDESKWALLPAPER = 20;
    public const int SPIF_UPDATEINIFILE = 0x01;
    public const int SPIF_SENDCHANGE = 0x02;
}
"@

$ConfigPath = "$PSScriptRoot\WallpaperConfig.json"

function Convert-JsonToHashtable {
    param([string]$json)
    $obj = $json | ConvertFrom-Json
    $hash = @{}
    foreach ($property in $obj.PSObject.Properties) {
        $hash[$property.Name] = $property.Value
    }
    return $hash
}

function Get-Monitors {
    $monitors = @()
    $screens = [System.Windows.Forms.Screen]::AllScreens
    foreach ($s in $screens) {
        $monitors += [PSCustomObject]@{
            Name       = $s.DeviceName
            Width      = $s.Bounds.Width
            Height     = $s.Bounds.Height
            Resolution = "$($s.Bounds.Width)x$($s.Bounds.Height)"
            IsPrimary  = $s.Primary
        }
    }
    return $monitors
}

function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            $jsonContent = Get-Content $ConfigPath -Raw
            return Convert-JsonToHashtable $jsonContent
        } catch {
            return @{}
        }
    }
    return @{}
}

function Save-Config($config) {
    $json = $config | ConvertTo-Json -Depth 5
    $json | Out-File $ConfigPath -Encoding UTF8
}

function Set-Wallpaper($path) {
    if (-not (Test-Path $path)) {
        [System.Windows.Forms.MessageBox]::Show("Image not found:`n$path", "Error", "OK", "Error")
        return
    }
    $fullPath = (Resolve-Path $path).Path
    [Wallpaper]::SystemParametersInfo(
        [Wallpaper]::SPI_SETDESKWALLPAPER, 0, $fullPath,
        [Wallpaper]::SPIF_UPDATEINIFILE -bor [Wallpaper]::SPIF_SENDCHANGE
    ) | Out-Null
    [System.Windows.Forms.MessageBox]::Show("Wallpaper has been changed:`n$fullPath", "Info", "OK", "Information")
}

function Set-Wallpaper-For-Resolution {
    param([hashtable]$Config, [System.Windows.Forms.ListBox]$listBox)
    $res = $listBox.SelectedItem
    if (-not $res) {
        [System.Windows.Forms.MessageBox]::Show("Please select a resolution.", "Info", "OK", "Information")
        return
    }
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Image Files|*.jpg;*.jpeg;*.png;*.bmp;*.gif"
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Config[$res] = $dialog.FileName
        Save-Config $Config
        [System.Windows.Forms.MessageBox]::Show("Wallpaper for $res has been set.", "Info", "OK", "Information")
    }
}

function Apply-Current-Wallpaper($Config) {
    $monitors = Get-Monitors
    $found = $false
    foreach ($mon in $monitors) {
        $res = $mon.Resolution
        if ($Config.ContainsKey($res)) {
            $img = $Config[$res]
            if (Test-Path $img) {
                Set-Wallpaper $img
                $found = $true
            }
        }
    }
    if (-not $found) {
        [System.Windows.Forms.MessageBox]::Show("No wallpaper is set for the current resolution.", "Info", "OK", "Information")
    }
}

function Reset-Config($Config, $listBox) {
    if (Test-Path $ConfigPath) {
        Remove-Item $ConfigPath -Force
        $Config.Clear()
        $listBox.ClearSelected()
        [System.Windows.Forms.MessageBox]::Show("Configuration has been reset.", "Info", "OK", "Information")
    }
}

# --- GUI Creation ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Wallpaper Manager"
$form.Size = New-Object System.Drawing.Size(420,340)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Monitor Resolutions:"
$label.Location = New-Object System.Drawing.Point(10,10)
$label.Size = New-Object System.Drawing.Size(200,20)
$form.Controls.Add($label)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(10,35)
$listBox.Size = New-Object System.Drawing.Size(180,200)
$form.Controls.Add($listBox)

$btnSet = New-Object System.Windows.Forms.Button
$btnSet.Text = "Set Wallpaper for Resolution"
$btnSet.Location = New-Object System.Drawing.Point(210,35)
$btnSet.Size = New-Object System.Drawing.Size(180,30)
$form.Controls.Add($btnSet)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply Current Resolution"
$btnApply.Location = New-Object System.Drawing.Point(210,75)
$btnApply.Size = New-Object System.Drawing.Size(180,30)
$form.Controls.Add($btnApply)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "Reset Configuration"
$btnReset.Location = New-Object System.Drawing.Point(210,115)
$btnReset.Size = New-Object System.Drawing.Size(180,30)
$form.Controls.Add($btnReset)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Location = New-Object System.Drawing.Point(210,155)
$btnExit.Size = New-Object System.Drawing.Size(180,30)
$form.Controls.Add($btnExit)


# Button events
$btnSet.Add_Click({ Set-Wallpaper-For-Resolution $config $listBox })
$btnApply.Add_Click({ Apply-Current-Wallpaper $config })
$btnReset.Add_Click({ Reset-Config $config $listBox })
$btnExit.Add_Click({ $form.Close() })

# Add a TextBox and Button for manual resolution entry
$txtManual = New-Object System.Windows.Forms.TextBox
$txtManual.Location = New-Object System.Drawing.Point(10,245)
$txtManual.Size = New-Object System.Drawing.Size(120,25)
$form.Controls.Add($txtManual)

$btnAddManual = New-Object System.Windows.Forms.Button
$btnAddManual.Text = "Add Resolution"
$btnAddManual.Location = New-Object System.Drawing.Point(140,245)
$btnAddManual.Size = New-Object System.Drawing.Size(110,25)
$form.Controls.Add($btnAddManual)

# Load data and bind
$config = Load-Config
$monitors = Get-Monitors
$resolutions = $monitors | Select-Object -ExpandProperty Resolution -Unique
$listBox.Items.AddRange($resolutions)

$ConfigPath = [System.IO.Path]::Combine($env:APPDATA, "WallpaperConfig.json")

# Add manual resolution event
$btnAddManual.Add_Click({
    $manualRes = $txtManual.Text.Trim()
    if ($manualRes -match '^\d{3,5}x\d{3,5}$') {
        if (-not $listBox.Items.Contains($manualRes)) {
            $listBox.Items.Add($manualRes)
            [System.Windows.Forms.MessageBox]::Show("Resolution $manualRes has been added.", "Info", "OK", "Information")
        } else {
            [System.Windows.Forms.MessageBox]::Show("Resolution already exists.", "Info", "OK", "Information")
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please enter in WIDTHxHEIGHT format (e.g. 1920x1080).", "Warning", "OK", "Warning")
    }
})


[void]$form.ShowDialog()