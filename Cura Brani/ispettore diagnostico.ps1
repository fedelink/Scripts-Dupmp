Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host "      L'ISPETTORE: DIAGNOSTICA DI PRECISIONE     " -ForegroundColor Cyan
Write-Host "=================================================`n" -ForegroundColor Cyan

$cartellaMusica = Read-Host "Inserisci il percorso della cartella da analizzare"

$fileAudio = Get-ChildItem -LiteralPath $cartellaMusica -Filter "*.flac" -Recurse | Where-Object { $_.Name -notmatch "_PULITO" }

if ($fileAudio.Count -eq 0) {
    Write-Host "Nessun file FLAC trovato." -ForegroundColor Yellow
} else {
    foreach ($file in $fileAudio) {
        $dimFisicaMB = (Get-Item -LiteralPath $file.FullName).Length / 1MB
        $durata = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $file.FullName
        $formato = & ffprobe -v error -select_streams a:0 -show_entries stream=sample_fmt -of default=noprint_wrappers=1:nokey=1 $file.FullName
        $frequenza = & ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 $file.FullName
        
        $formato = if ($formato) { $formato.Trim() } else { "Sconosciuto" }
        $frequenza = if ($frequenza) { $frequenza.Trim() } else { "Sconosciuta" }

        $mbAlMinuto = 0
        $motivoCura = ""

        if ([string]::IsNullOrWhiteSpace($durata) -or $durata -eq "N/A") {
            $motivoCura += "[Durata Illeggibile] "
        } else {
            $minuti = [double]$durata / 60
            if ($minuti -gt 0) {
                $mbAlMinuto = $dimFisicaMB / $minuti
                if ($mbAlMinuto -gt 25) { $motivoCura += "[Densità > 25] " }
            }
        }

        if ($formato -match "32" -or $formato -match "f") {
            $motivoCura += "[Formato 32-bit] "
        }

        Write-Host "`nNome: $($file.Name)" -ForegroundColor Yellow
        Write-Host "  - Formato e Freq: $formato a $frequenza Hz" -ForegroundColor Gray
        Write-Host "  - Peso: $([math]::Round($dimFisicaMB, 2)) MB" -ForegroundColor Gray
        Write-Host "  - Densità: $([math]::Round($mbAlMinuto, 2)) MB/min" -ForegroundColor Gray
        
        if ($motivoCura) {
            Write-Host "  -> ATTENZIONE: Scatterebbe la Cura Profonda per: $motivoCura" -ForegroundColor Red
        } else {
            Write-Host "  -> OK: Scatterebbe il Lavaggio Leggero (Sano)" -ForegroundColor Green
        }
        Write-Host "-------------------------------------------------" -ForegroundColor DarkGray
    }
}