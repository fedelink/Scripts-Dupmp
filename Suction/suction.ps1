do {
    cls
    Write-Host "--- Script di Spostamento File ---" -ForegroundColor Cyan
    $inputPath = Read-Host "Inserisci il percorso della cartella principale (o i percorsi separati da virgola)"

    $paths = $inputPath -split ',' | ForEach-Object { $_.Trim(' "''') }

    foreach ($path in $paths) {
        if (Test-Path $path) {
            Write-Host "Analisi della cartella: $path..." -ForegroundColor Yellow
            $files = Get-ChildItem -Path $path -Recurse -File

            foreach ($file in $files) {
                if ($file.Directory.FullName -ne $path) {
                    Move-Item -Path $file.FullName -Destination $path -Force
                }
            }

            Get-ChildItem -Path $path -Recurse -Directory | Sort-Object FullName -Descending | Remove-Item -Recurse -Force
            Write-Host "Operazione completata per: $path" -ForegroundColor Green
        } else {
            Write-Host "Il percorso $path non esiste. Operazione saltata." -ForegroundColor Red
        }
    }

    $answer = Read-Host "Vuoi avviare un nuovo processo? (S/N)"
} while ($answer -eq 'S' -or $answer -eq 's')