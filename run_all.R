# =============================================================================
# run_all.R — roda o experimento completo, do dado cru às figuras do pôster
# =============================================================================
# Uso (na raiz do projeto):   Rscript run_all.R
#   ou no RStudio: abrir o projeto e dar source("run_all.R")
# Para pular a validação cruzada (lenta) e reaproveitar resultados salvos:
#   Rscript run_all.R --sem-cv
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
sem_cv <- "--sem-cv" %in% args

sink_log <- file("resultados_log.txt", open = "wt")
sink(sink_log, split = TRUE)

source("R/00_setup.R")
source("R/funcoes.R")
cat("==== 1. Dados e análise exploratória ====\n");      source("R/01_dados.R")
if (!sem_cv) {
  cat("\n==== 2. Validação cruzada (4 estratégias x 4 modelos) ====\n")
  source("R/02_validacao_cruzada.R")
}
cat("\n==== 3. Comparação (objetivos 2, 3 e 4) ====\n");   source("R/03_comparacao.R")
cat("\n==== 4. Interpretabilidade ====\n");                source("R/04_interpretabilidade.R")

cat("\n==== Informações da sessão ====\n"); print(sessionInfo())
sink(); close(sink_log)
