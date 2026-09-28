# =============================================================================
# run_cdc.R — roda a SEGUNDA análise (CDC Diabetes Health Indicators)
# =============================================================================
# Independente do run_all.R (Pima): tem scripts (R/cdc/), resultados
# (resultados/cdc/) e log (resultados_cdc_log.txt) próprios. Só reaproveita
# a configuração geral (R/00_setup.R) e a caixa de ferramentas (R/funcoes.R).
#
# Uso (na raiz do projeto):
#   Rscript run_cdc.R                  base inteira (~30–60 min)
#   Rscript run_cdc.R --sem-cv         reaproveita a validação cruzada já salva
#   Rscript run_cdc.R --amostra=20000  teste rápido numa amostra; saídas em
#                                      resultados/cdc_amostra/ (fora do Git)
# Para a comparação Pima vs. CDC, rode antes o run_all.R.
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
sem_cv <- "--sem-cv" %in% args
arg_amostra <- grep("^--amostra=", args, value = TRUE)
CDC_AMOSTRA <- if (length(arg_amostra)) as.integer(sub("--amostra=", "", arg_amostra)) else NA

source("R/00_setup.R")
source("R/funcoes.R")
source("R/cdc/00_setup_cdc.R")

sink_log <- file(if (is.na(CDC_AMOSTRA)) "resultados_cdc_log.txt"
                 else file.path(DIR_CDC, "log.txt"), open = "wt")
sink(sink_log, split = TRUE)

cat("==== CDC 1. Dados e análise exploratória ====\n");     source("R/cdc/01_dados.R")
if (!sem_cv) {
  cat(sprintf("\n==== CDC 2. Validação cruzada (%d-fold x %d, 4 modelos) ====\n",
              CDC_K_FOLDS, CDC_N_REPETICOES))
  source("R/cdc/02_validacao_cruzada.R")
}
cat("\n==== CDC 3. Comparação (objetivos 2 e 3 + Pima vs. CDC) ====\n"); source("R/cdc/03_comparacao.R")
cat("\n==== CDC 4. Interpretabilidade ====\n");                source("R/cdc/04_interpretabilidade.R")

cat("\n==== Informações da sessão ====\n"); print(sessionInfo())
sink(); close(sink_log)
