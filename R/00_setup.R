# =============================================================================
# 00_setup.R — pacotes, semente, caminhos e parâmetros globais do experimento
# =============================================================================
# TCC: Predição de diabetes por aprendizado de máquina supervisionado
# Universidade Presbiteriana Mackenzie — FCI
# =============================================================================

pacotes <- c(
  "mlbench",       # contém o Pima Indians Diabetes Dataset
  "rpart",         # árvore de decisão (CART)
  "randomForest",  # random forest
  "gbm",           # gradient boosting
  "pROC",          # curva ROC e AUC
  "mice",          # imputação múltipla por equações encadeadas
  "ggplot2",       # figuras
  "partykit"       # desenho da árvore de decisão
)

faltando <- pacotes[!vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltando) > 0) {
  message("Instalando pacotes que faltam: ", paste(faltando, collapse = ", "))
  install.packages(faltando, repos = "https://cloud.r-project.org")
}
invisible(lapply(pacotes, function(p) suppressPackageStartupMessages(
  library(p, character.only = TRUE))))

# ---- Parâmetros globais -----------------------------------------------------
SEMENTE      <- 2026   # reprodutibilidade
K_FOLDS      <- 10     # validação cruzada k-fold
N_REPETICOES <- 5      # repetições da CV (10 x 5 = 50 avaliações por modelo)
LIMIAR       <- 0.5    # limiar de probabilidade para métricas de classe
DELTA_AUC_RELEVANTE <- 0.05  # critério do objetivo específico 3

# Estratégia de ausentes usada nas análises principais (definida a priori:
# imputação múltipla é a abordagem mais recomendada na literatura e usa
# todos os 768 pacientes). As outras entram na análise do objetivo 4.
ESTRATEGIA_PRINCIPAL <- "mice"

# Variáveis em que o valor zero é fisiologicamente impossível -> dado ausente
VARS_ZERO_INVALIDO <- c("glucose", "pressure", "triceps", "insulin", "mass")

# ---- Caminhos ----------------------------------------------------------------
DIR_DADOS   <- "data"
DIR_RESULT  <- "resultados"
DIR_TABELAS <- file.path(DIR_RESULT, "tabelas")
DIR_FIGURAS <- file.path(DIR_RESULT, "figuras")
DIR_MODELOS <- file.path(DIR_RESULT, "modelos")
for (d in c(DIR_DADOS, DIR_TABELAS, DIR_FIGURAS, DIR_MODELOS)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# ---- Rótulos em português para tabelas e figuras ---------------------------
ROTULOS_VARS <- c(
  pregnant = "Gestações",
  glucose  = "Glicose",
  pressure = "Pressão diastólica",
  triceps  = "Dobra cutânea (tríceps)",
  insulin  = "Insulina",
  mass     = "IMC",
  pedigree = "Histórico familiar (DPF)",
  age      = "Idade"
)

ROTULOS_MODELOS <- c(
  logistica = "Regressão logística",
  arvore    = "Árvore de decisão",
  rf        = "Random forest",
  gbm       = "Gradient boosting"
)

ROTULOS_ESTRATEGIAS <- c(
  zeros_mantidos = "Zeros mantidos (sem tratamento)",
  casos_completos = "Remoção de casos incompletos",
  mediana        = "Imputação pela mediana",
  mice           = "Imputação múltipla (MICE)"
)

# Paleta categórica (4 modelos) — ordem fixa, validada para daltonismo
CORES_MODELOS <- c(
  logistica = "#2a78d6",  # azul
  arvore    = "#eb6834",  # laranja
  rf        = "#1baf7a",  # verde-água
  gbm       = "#eda100"   # amarelo
)

tema_tcc <- function(base = 13) {
  theme_minimal(base_size = base) +
    theme(
      plot.title       = element_text(face = "bold", colour = "#0b0b0b"),
      plot.subtitle    = element_text(colour = "#52514e"),
      axis.text        = element_text(colour = "#52514e"),
      axis.title       = element_text(colour = "#0b0b0b"),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "#e8e7e3", linewidth = 0.3),
      legend.position  = "bottom",
      strip.text       = element_text(face = "bold", hjust = 0),
      plot.background  = element_rect(fill = "white", colour = NA)
    )
}
