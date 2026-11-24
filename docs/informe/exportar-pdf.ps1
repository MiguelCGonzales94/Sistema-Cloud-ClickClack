# Abre el DOCX en Word, actualiza el índice y los números de página y exporta el PDF.
# Uso: powershell -File exportar-pdf.ps1 "<ruta .docx>" "<ruta .pdf>"
param(
    [Parameter(Mandatory = $true)][string]$Docx,
    [Parameter(Mandatory = $true)][string]$Pdf
)
$ErrorActionPreference = "Stop"
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
    $doc = $word.Documents.Open($Docx)
    $doc.Fields.Update() | Out-Null
    foreach ($toc in $doc.TablesOfContents) { $toc.Update() }
    $doc.Repaginate()
    $doc.Save()
    # 17 = wdExportFormatPDF; 0 = optimizar para impresión
    $doc.ExportAsFixedFormat($Pdf, 17, $false, 0)
    "PDF: $Pdf  (páginas: $($doc.ComputeStatistics(2)))"
    $doc.Close($false)
}
finally {
    $word.Quit()
}
