# run_all.R -- ejecuta el pipeline completo, desde los datos originales hasta el informe.
# Uso (desde cualquier directorio dentro del proyecto):
#   Rscript run_all.R            o, en R:  source("run_all.R")
#
# Con limpiar = TRUE borra primero todo lo generado (data/processed y outputs) y lo
# reconstruye: es la prueba de reproducibilidad (solo quedan los datos originales y el codigo).
limpiar <- TRUE
generar_informe <- TRUE

if (!requireNamespace("here", quietly = TRUE)) stop("Falta el paquete here: install.packages(\"here\")")
raiz <- here::here()

if (limpiar) {
  unlink(file.path(raiz, c("data/processed", "outputs")), recursive = TRUE)
  message("Borrados data/processed y outputs: se regeneran desde data/raw")
}

# Scripts del pipeline en orden (01_..., 02_..., ...); cada uno en su propio entorno
scripts <- list.files(file.path(raiz, "scripts"), pattern = "^0[1-9]_.*\\.R$", full.names = TRUE)
for (s in scripts) {
  message("\n==> ", basename(s))
  inicio <- Sys.time()
  source(s, local = new.env(), encoding = "UTF-8")
  message("    ", round(difftime(Sys.time(), inicio, units = "secs")), " s")
}

# Informe Quarto: con el paquete quarto si esta instalado; si no, con la linea de comandos.
if (generar_informe) {
  message("\n==> report/informe.qmd")
  qmd <- file.path(raiz, "report", "informe.qmd")
  if (requireNamespace("quarto", quietly = TRUE)) {
    quarto::quarto_render(qmd)
  } else {
    estado <- system2("quarto", c("render", shQuote(qmd)))
    if (estado != 0) stop("No se pudo generar el informe (¿esta instalado Quarto?)")
  }
}

# Versiones de R y de los paquetes usados en esta corrida
writeLines(capture.output(sessionInfo()), file.path(raiz, "outputs", "session_info.txt"))
message("\nListo. Resultados en outputs/ e informe en report/informe.html")
