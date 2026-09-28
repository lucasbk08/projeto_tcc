# =============================================================================
# cdc/00_setup_cdc.R — parâmetros, caminhos e rótulos da análise CDC
# =============================================================================
# Segunda análise: replica a comparação dos 4 modelos no CDC Diabetes Health
# Indicators (UCI id 891; BRFSS/CDC), uma base grande (253.680 pessoas) de
# variáveis AUTODECLARADAS em questionário telefônico, sem exames de laboratório.
#
# Pressupõe que R/00_setup.R e R/funcoes.R já foram carregados (run_cdc.R faz
# isso). Tudo aqui tem prefixo CDC_ para não colidir com a análise do Pima.
# =============================================================================

if (!requireNamespace("ranger", quietly = TRUE)) {
  install.packages("ranger", repos = "https://cloud.r-project.org")
}
suppressPackageStartupMessages(library(ranger))

# ---- Parâmetros --------------------------------------------------------------
# Com 253 mil pessoas, a CV 10 x 5 do Pima levaria horas. Com 5 folds cada
# teste já tem ~50 mil pessoas (~7 mil com diabetes), então a variação entre
# folds é pequena; 2 repetições bastam para o teste t corrigido.
CDC_K_FOLDS      <- 5
CDC_N_REPETICOES <- 2
CDC_URL <- "https://archive.ics.uci.edu/static/public/891/data.csv"
CDC_ARQUIVO <- file.path(DIR_DADOS, "cdc_diabetes_health_indicators.csv")

# ---- Caminhos (resultados separados dos do Pima) ------------------------------
# Com --amostra=N (teste rápido), as saídas vão para resultados/cdc_amostra/,
# que é ignorada pelo Git, para nunca sobrescrever os resultados oficiais.
if (!exists("CDC_AMOSTRA")) CDC_AMOSTRA <- NA
DIR_CDC         <- file.path(DIR_RESULT, if (is.na(CDC_AMOSTRA)) "cdc" else "cdc_amostra")
DIR_CDC_TABELAS <- file.path(DIR_CDC, "tabelas")
DIR_CDC_FIGURAS <- file.path(DIR_CDC, "figuras")
for (d in c(DIR_CDC_TABELAS, DIR_CDC_FIGURAS)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# ---- Rótulos das variáveis (dicionário do UCI) --------------------------------
ROTULOS_CDC <- c(
  HighBP               = "Pressão alta",
  HighChol             = "Colesterol alto",
  CholCheck            = "Checou colesterol (5 anos)",
  BMI                  = "IMC",
  Smoker               = "Fumante (≥ 100 cigarros na vida)",
  Stroke               = "AVC prévio",
  HeartDiseaseorAttack = "Doença cardíaca / infarto",
  PhysActivity         = "Atividade física (30 dias)",
  Fruits               = "Come fruta todo dia",
  Veggies              = "Come verdura todo dia",
  HvyAlcoholConsump    = "Consumo pesado de álcool",
  AnyHealthcare        = "Tem cobertura de saúde",
  NoDocbcCost          = "Deixou de ir ao médico por custo",
  GenHlth              = "Saúde geral (1 excelente … 5 ruim)",
  MentHlth             = "Dias de saúde mental ruim (30 d)",
  PhysHlth             = "Dias de saúde física ruim (30 d)",
  DiffWalk             = "Dificuldade para andar",
  Sex                  = "Sexo masculino",
  Age                  = "Faixa etária (13 faixas de 5 anos)",
  Education            = "Escolaridade (1–6)",
  Income               = "Renda (1–8)"
)
CDC_VARS         <- names(ROTULOS_CDC)
CDC_VARS_BINARIAS <- c("HighBP", "HighChol", "CholCheck", "Smoker", "Stroke",
                       "HeartDiseaseorAttack", "PhysActivity", "Fruits", "Veggies",
                       "HvyAlcoholConsump", "AnyHealthcare", "NoDocbcCost",
                       "DiffWalk", "Sex")

# Unidade do odds ratio na regressão logística: binárias = "sim vs. não";
# as demais variam por um passo que faça sentido clínico.
CDC_UNIDADE_OR <- c(BMI = 5, MentHlth = 10, PhysHlth = 10,
                    GenHlth = 1, Age = 1, Education = 1, Income = 1)
CDC_DESCR_UNIDADE <- c(BMI = "+5 kg/m²", MentHlth = "+10 dias", PhysHlth = "+10 dias",
                       GenHlth = "+1 nível", Age = "+1 faixa (5 anos)",
                       Education = "+1 nível", Income = "+1 faixa")

# ---- Modelos -------------------------------------------------------------------
# Os mesmos 4 modelos e hiperparâmetros do Pima (R/funcoes.R), exceto a random
# forest: o pacote randomForest seria lento demais aqui, então usa-se o ranger,
# implementação do mesmo algoritmo (500 árvores, mtry = raiz de p) que roda em
# paralelo. probability = TRUE produz probabilidades (floresta de probabilidade).
MODELOS_CDC <- MODELOS
MODELOS_CDC$rf <- list(
  ajustar = function(tr) ranger(diabetes ~ ., data = tr, num.trees = 500,
                                probability = TRUE, seed = sample.int(1e6, 1),
                                verbose = FALSE),
  prever  = function(m, te) as.numeric(predict(m, data = te, verbose = FALSE)$predictions[, "pos"])
)

# ---- Métrica extra: AUC-PR -----------------------------------------------------
# Com só 14% de positivos, a AUC-ROC pode parecer boa mesmo com muitos falsos
# positivos. A AUC-PR (precisão média) olha só para quem o modelo aponta como
# positivo. Referência: um modelo que chuta tem AUC-PR = prevalência (~0,14).
# Empates de probabilidade (comuns na árvore) são tratados como um só limiar.
auc_pr <- function(y, p) {
  y01 <- y == "pos"
  o <- order(p, decreasing = TRUE); ps <- p[o]; ys <- y01[o]
  fim_grupo <- c(ps[-1] != ps[-length(ps)], TRUE)
  vp <- cumsum(ys)[fim_grupo]; fp <- cumsum(!ys)[fim_grupo]
  recall <- vp / sum(ys); precisao <- vp / (vp + fp)
  sum(diff(c(0, recall)) * precisao)
}

# Métricas do CDC = as mesmas do Pima (limiar 0,5) + AUC-PR + métricas de classe
# no limiar = prevalência do treino. Com 14% de diabéticos, o limiar 0,5 quase
# nunca é atingido e a sensibilidade despenca; a prevalência é o corte natural.
calcular_metricas_cdc <- function(y, p, prevalencia_treino) {
  base <- calcular_metricas(y, p, limiar = 0.5)
  lp <- calcular_metricas(y, p, limiar = prevalencia_treino)
  lp <- lp[, c("acuracia", "sensibilidade", "especificidade", "precisao", "f1")]
  names(lp) <- paste0(names(lp), "_lprev")
  cbind(base, auc_pr = auc_pr(y, p), limiar_prev = prevalencia_treino, lp)
}

# Números inteiros com ponto de milhar (253.680)
fmt_n <- function(x) formatC(x, format = "d", big.mark = ".")
