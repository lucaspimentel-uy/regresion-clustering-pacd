# 05_informe_pdf.R -- genera informe/informe.pdf (con las figuras embebidas) a partir
# de informe/informe.md. Markdown -> HTML con {commonmark}; HTML -> PDF con Edge o
# Chrome en modo headless. Ejecutar desde la raiz: Rscript 05_informe_pdf.R

if (!requireNamespace("commonmark", quietly = TRUE)) {
  stop("Falta el paquete commonmark: install.packages(\"commonmark\")")
}
navegadores <- c("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
                 "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
                 "C:/Program Files/Google/Chrome/Application/chrome.exe")
navegador <- navegadores[file.exists(navegadores)][1]
if (is.na(navegador)) stop("No encuentro Edge ni Chrome para imprimir el PDF.")

md   <- readLines("informe/informe.md", encoding = "UTF-8", warn = FALSE)
body <- commonmark::markdown_html(paste(md, collapse = "\n"), extensions = TRUE)

css <- "
@page { size: A4; margin: 16mm 17mm; }
body { font-family: 'Segoe UI', Calibri, Arial, sans-serif; font-size: 10.3pt; line-height: 1.42; color: #1a1a1a; }
h1 { font-size: 18pt; margin: 0 0 8pt; }
h2 { font-size: 13.5pt; margin: 16pt 0 4pt; border-bottom: 1px solid #ccc; padding-bottom: 2pt; break-after: avoid; }
p { margin: 0 0 6pt; text-align: justify; }
ul, ol { margin: 0 0 6pt; padding-left: 18pt; }
code { font-family: Consolas, monospace; font-size: 9pt; background: #f2f2f2; padding: 0 2px; }
table { border-collapse: collapse; margin: 4pt 0 8pt; font-size: 8.8pt; width: 100%; break-inside: avoid; }
th, td { border: 1px solid #bbb; padding: 2pt 4pt; text-align: center; }
th { background: #eef2f5; }
td:first-child, th:first-child { text-align: left; }
p:has(> img) { margin: 8pt 0 2pt; text-align: center; break-after: avoid; break-inside: avoid; }
img { max-width: 100%; max-height: 105mm; object-fit: contain; }
p:has(> img) + p { text-align: center; font-size: 8.8pt; color: #444; margin-bottom: 9pt; }
"
html <- paste0("<!doctype html><html lang='es'><head><meta charset='utf-8'><title>Siniestralidad vial en Montevideo</title><style>",
               css, "</style></head><body>", body, "</body></html>")

# El HTML temporal va en informe/ para que las rutas relativas (../outputs/figuras/...) resuelvan.
tmp <- "informe/_informe_tmp.html"
writeLines(html, tmp, useBytes = TRUE)

pdf_out <- normalizePath("informe/informe.pdf", winslash = "/", mustWork = FALSE)
url     <- paste0("file:///", normalizePath(tmp, winslash = "/"))
res <- system2(navegador, c("--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                            paste0("--print-to-pdf=\"", pdf_out, "\""), paste0("\"", url, "\"")),
               stdout = TRUE, stderr = TRUE)
Sys.sleep(1)
unlink(tmp)
if (!file.exists(pdf_out)) stop("No se genero el PDF:\n", paste(res, collapse = "\n"))
cat("PDF generado:", pdf_out, "(", round(file.size(pdf_out) / 1024), "KB )\n")
