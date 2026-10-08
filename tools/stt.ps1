# Offline speech-to-text for the game: transcribes a 16 kHz mono 16-bit WAV with the Windows desktop
# recognizer (System.Speech). Prints the recognised text on one line; prints nothing if nothing was heard.
param([Parameter(Mandatory = $true)][string]$Wav)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
$engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine($culture)
try {
    $engine.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
    $engine.SetInputToWaveFile($Wav)
    $words = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $result = $engine.Recognize()
        if ($null -eq $result) { break }
        if ($result.Text) { $words.Add($result.Text) }
    }
    [Console]::Out.WriteLine(($words -join ' ').Trim())
}
finally {
    $engine.Dispose()
}
