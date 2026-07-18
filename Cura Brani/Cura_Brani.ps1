Write-Host "Verifica dei prerequisiti..." -ForegroundColor Cyan

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "FFmpeg non trovato. Assicurati di averlo installato." -ForegroundColor Red
    Exit
}

$continuaAnalisi = $true

while ($continuaAnalisi) {
    Clear-Host
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host " IL CLINICO: LAVAGGIO IN-PLACE SUL POSTO         " -ForegroundColor Cyan
    Write-Host "=================================================`n" -ForegroundColor Cyan

    $inputValido = $false
    $cartelleDaAnalizzare = @()

    do {
        Write-Host "Puoi inserire un singolo percorso, oppure più percorsi separati da virgola." -ForegroundColor Gray
        $inputCartelle = Read-Host "Inserisci i percorsi da analizzare"
        
        $cartelle = $inputCartelle -split "," | ForEach-Object { $_.Trim() -replace '"', '' -replace "'", '' }
        
        foreach ($c in $cartelle) {
            if (Test-Path -LiteralPath $c) {
                $cartelleDaAnalizzare += $c
                $inputValido = $true
            } else {
                Write-Host "Attenzione: Il percorso '$c' non è valido e verrà ignorato." -ForegroundColor Red
            }
        }
        
        if (-not $inputValido) {
            Write-Host "Nessun percorso valido inserito. Riprova.`n" -ForegroundColor Red
        }
    } until ($inputValido)

    foreach ($cartellaMusica in $cartelleDaAnalizzare) {
        Write-Host "`n-------------------------------------------------" -ForegroundColor Cyan
        Write-Host " IN ANALISI: $cartellaMusica" -ForegroundColor White
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan

        $fileAudio = Get-ChildItem -LiteralPath $cartellaMusica -Filter "*.flac" -Recurse | 
                     Where-Object { $_.FullName -notlike "*\Danneggiati\*" -and $_.Name -notmatch "_PULITO" }

        if ($fileAudio.Count -eq 0) {
            Write-Host "Nessun file FLAC trovato in questa directory." -ForegroundColor Yellow
            continue 
        } 
        
        Write-Host "Inizio sanificazione sicura di $($fileAudio.Count) file...`n" -ForegroundColor Cyan

        $contatoreLavaggi = 0
        $contatoreCure = 0
        $contatoreErrori = 0

        foreach ($file in $fileAudio) {
            Write-Host "Cura: $($file.Name)... " -NoNewline -ForegroundColor DarkGray
            
            # 1. ESTRAZIONE METADATI
            $titolo = & ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 $file.FullName
            $artista = & ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 $file.FullName
            $album = & ffprobe -v error -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 $file.FullName

            $titolo = if ($titolo) { $titolo.Trim() } else { "" }
            $artista = if ($artista) { $artista.Trim() } else { "" }
            $album = if ($album) { $album.Trim() } else { "" }

            # Nomi dei file temporanei per la lavorazione
            $nomeUnico = [guid]::NewGuid().ToString().Substring(0,8)
            $tempCover = Join-Path $cartellaMusica "temp_cover_$nomeUnico.jpg"
            $fileTemp = Join-Path $cartellaMusica "temp_audio_$nomeUnico.flac"

            # 2. ESTRAZIONE SEPARATA DELLA COPERTINA
            & ffmpeg -y -v error -i $file.FullName -an -vframes 1 -vf "scale='min(800,iw)':-1" $tempCover
            $haCopertina = Test-Path -LiteralPath $tempCover

            # Ricostruzione stringa metadati
            $stringaMetadati = @("-map_metadata", "-1")
            if ($titolo)  { $stringaMetadati += "-metadata"; $stringaMetadati += "title=$titolo" }
            if ($artista) { $stringaMetadati += "-metadata"; $stringaMetadati += "artist=$artista" }
            if ($album)   { $stringaMetadati += "-metadata"; $stringaMetadati += "album=$album" }

            Write-Host "" 

            # 3. LAVAGGIO LEGGERO DI DEFAULT (Qualità intatta, salva sul file temporaneo)
            Write-Host "   -> [LAVAGGIO CONSERVATIVO] Elaborazione in-place..." -ForegroundColor DarkCyan
            
            if ($haCopertina) {
                $parametriFinali = @("-y", "-v", "error", "-i", $file.FullName, "-i", $tempCover, "-map", "0:a:0", "-map", "1:v:0", "-c:a", "copy", "-c:v", "copy", "-disposition:v", "attached_pic") + $stringaMetadati + @($fileTemp)
            } else {
                $parametriFinali = @("-y", "-v", "error", "-i", $file.FullName, "-map", "0:a:0", "-c:a", "copy") + $stringaMetadati + @($fileTemp)
            }
            
            & ffmpeg @parametriFinali

            # 4. CONTROLLO E FALLBACK
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fileTemp)) {
                Write-Host "      Errore copia! Audio corrotto. Avvio Cura Profonda..." -ForegroundColor DarkYellow
                
                # Pulisce l'eventuale temp fallito
                if (Test-Path -LiteralPath $fileTemp) { Remove-Item -LiteralPath $fileTemp -Force -ErrorAction SilentlyContinue }

                if ($haCopertina) {
                    $parametriFallback = @("-y", "-v", "error", "-i", $file.FullName, "-i", $tempCover, "-map", "0:a:0", "-map", "1:v:0", "-c:a", "flac", "-c:v", "copy", "-disposition:v", "attached_pic") + $stringaMetadati + @($fileTemp)
                } else {
                    $parametriFallback = @("-y", "-v", "error", "-i", $file.FullName, "-map", "0:a:0", "-c:a", "flac") + $stringaMetadati + @($fileTemp)
                }
                
                & ffmpeg @parametriFallback
                
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $fileTemp)) {
                    # Sostituzione sicura in-place
                    Remove-Item -LiteralPath $file.FullName -Force
                    Rename-Item -LiteralPath $fileTemp -NewName $file.Name -Force
                    Write-Host "      Fatto! Salvato tramite Cura Profonda (Ricodifica)." -ForegroundColor Green
                    $contatoreCure++
                } else {
                    # Se fallisce tutto, cancella il temp rotto e lascia intatto l'originale
                    if (Test-Path -LiteralPath $fileTemp) { Remove-Item -LiteralPath $fileTemp -Force -ErrorAction SilentlyContinue }
                    Write-Host "      ERRORE CRITICO: File irrecuperabile. Originale intatto." -ForegroundColor Red
                    $contatoreErrori++
                }
            } else {
                # Sostituzione sicura in-place del lavaggio
                Remove-Item -LiteralPath $file.FullName -Force
                Rename-Item -LiteralPath $fileTemp -NewName $file.Name -Force
                Write-Host "      Fatto! Metadati e copertina puliti alla perfezione." -ForegroundColor Green
                $contatoreLavaggi++
            }

            # 5. PULIZIA TEMPORANEI (Copertina)
            if (Test-Path -LiteralPath $tempCover) { Remove-Item -LiteralPath $tempCover -Force -ErrorAction SilentlyContinue }
        }

        Write-Host "`nProcesso terminato per la cartella: $cartellaMusica" -ForegroundColor Cyan
        Write-Host "Lavaggi conservativi eseguiti: $contatoreLavaggi" -ForegroundColor Green
        if ($contatoreCure -gt 0) { Write-Host "Cure profonde applicate: $contatoreCure" -ForegroundColor Yellow }
        if ($contatoreErrori -gt 0) { Write-Host "File ignorati (Irrecuperabili): $contatoreErrori" -ForegroundColor Red }
    }

    Write-Host "`n=================================================" -ForegroundColor Cyan
    do {
        $scelta = Read-Host "Vuoi analizzare altre cartelle? (S/N)"
    } until ($scelta -match "^[sSnN]$") 

    if ($scelta -match "^[nN]$") {
        $continuaAnalisi = $false
        Write-Host "`nChiusura de 'Il Clinico' in corso... Alla prossima!" -ForegroundColor Cyan
        Start-Sleep -Seconds 2
    }
}