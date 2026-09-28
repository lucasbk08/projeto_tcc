# =============================================================================
# funcoes.R — funções auxiliares: tratamento de ausentes, modelos e métricas
# =============================================================================
# Regra de ouro: TODO o pré-processamento que "aprende" algo dos dados
# (mediana, modelo de imputação) é ajustado SÓ no fold de treino e depois
# aplicado ao fold de teste. Assim não há vazamento de informação (data leakage).
# =============================================================================

# ---- 1. Zeros inválidos -> NA ------------------------------------------------
zeros_para_na <- function(df, vars = VARS_ZERO_INVALIDO) {
  for (v in vars) df[[v]][df[[v]] == 0] <- NA
  df
}

# ---- 2. Estratégias de tratamento de ausentes --------------------------------
# Cada estratégia recebe (treino, teste) e devolve list(treino, teste) prontos.

trat_zeros_mantidos <- function(treino, teste) {
  # Linha de base: usa os dados crus, como se os zeros fossem medidas reais
  list(treino = treino, teste = teste)
}

trat_casos_completos <- function(treino, teste) {
  # Remove qualquer paciente com algum valor ausente (treino e teste).
  # Obs.: reduz a amostra de 768 para 392 pacientes.
  treino <- zeros_para_na(treino); teste <- zeros_para_na(teste)
  list(treino = treino[complete.cases(treino), ],
       teste  = teste[complete.cases(teste), ])
}

trat_mediana <- function(treino, teste) {
  # Mediana calculada NO TREINO e usada para preencher treino e teste
  treino <- zeros_para_na(treino); teste <- zeros_para_na(teste)
  for (v in VARS_ZERO_INVALIDO) {
    med <- median(treino[[v]], na.rm = TRUE)
    treino[[v]][is.na(treino[[v]])] <- med
    teste[[v]][is.na(teste[[v]])]   <- med
  }
  list(treino = treino, teste = teste)
}

trat_mice <- function(treino, teste, m = 1, maxit = 10) {
  # MICE com predictive mean matching (pmm). O modelo de imputação é ajustado
  # somente com as linhas de treino (argumento `ignore`); as linhas de teste
  # são imputadas, mas não influenciam o ajuste. A variável resposta NÃO entra
  # como preditora da imputação no teste (seria vazamento), então é removida.
  treino <- zeros_para_na(treino); teste <- zeros_para_na(teste)
  x_tr <- treino[, setdiff(names(treino), "diabetes")]
  x_te <- teste[,  setdiff(names(teste),  "diabetes")]
  juntos <- rbind(x_tr, x_te)
  ignorar <- c(rep(FALSE, nrow(x_tr)), rep(TRUE, nrow(x_te)))
  imp <- mice(juntos, m = m, maxit = maxit, method = "pmm",
              ignore = ignorar, printFlag = FALSE)
  completo <- complete(imp, 1)
  treino[, names(x_tr)] <- completo[!ignorar, ]
  teste[,  names(x_te)] <- completo[ignorar, ]
  list(treino = treino, teste = teste)
}

ESTRATEGIAS <- list(
  zeros_mantidos  = trat_zeros_mantidos,
  casos_completos = trat_casos_completos,
  mediana         = trat_mediana,
  mice            = trat_mice
)

# ---- 3. Modelos --------------------------------------------------------------
# Cada modelo: ajustar(treino) -> objeto ; prever(obj, teste) -> P(diabetes = pos)
# Hiperparâmetros fixos e documentados (ver README, seção "Decisões").

formula_modelo <- diabetes ~ .

MODELOS <- list(
  logistica = list(
    ajustar = function(tr) glm(formula_modelo, data = tr, family = binomial),
    prever  = function(m, te) as.numeric(predict(m, newdata = te, type = "response"))
  ),
  arvore = list(
    # CART com poda pelo erro de validação cruzada interna (regra do 1-SE)
    ajustar = function(tr) {
      a <- rpart(formula_modelo, data = tr, method = "class", model = TRUE,
                 control = rpart.control(cp = 0.001, minsplit = 20, xval = 10))
      cpt <- a$cptable
      limite <- min(cpt[, "xerror"]) + cpt[which.min(cpt[, "xerror"]), "xstd"]
      cp_1se <- cpt[which(cpt[, "xerror"] <= limite)[1], "CP"]
      prune(a, cp = cp_1se)
    },
    prever = function(m, te) as.numeric(predict(m, newdata = te, type = "prob")[, "pos"])
  ),
  rf = list(
    ajustar = function(tr) randomForest(formula_modelo, data = tr, ntree = 500,
                                        importance = TRUE),
    prever  = function(m, te) as.numeric(predict(m, newdata = te, type = "prob")[, "pos"])
  ),
  gbm = list(
    # gbm exige resposta 0/1; nº de árvores escolhido pelo erro OOB
    ajustar = function(tr) {
      tr$y <- as.integer(tr$diabetes == "pos"); tr$diabetes <- NULL
      m <- gbm(y ~ ., data = tr, distribution = "bernoulli", n.trees = 1500,
               interaction.depth = 3, shrinkage = 0.01, bag.fraction = 0.8,
               n.minobsinnode = 10, verbose = FALSE)
      m$melhor_n <- suppressMessages(suppressWarnings(
        gbm.perf(m, method = "OOB", plot.it = FALSE)))
      m
    },
    prever = function(m, te) as.numeric(predict(m, newdata = te, n.trees = m$melhor_n,
                                               type = "response"))
  )
)

# ---- 4. Métricas ---------------------------------------------------------------
calcular_metricas <- function(y, p, limiar = LIMIAR) {
  y01  <- as.integer(y == "pos")
  pred <- as.integer(p >= limiar)
  vp <- sum(pred == 1 & y01 == 1); vn <- sum(pred == 0 & y01 == 0)
  fp <- sum(pred == 1 & y01 == 0); fn <- sum(pred == 0 & y01 == 1)
  sens <- vp / (vp + fn); espec <- vn / (vn + fp)
  prec <- if ((vp + fp) > 0) vp / (vp + fp) else NA_real_
  auc  <- as.numeric(pROC::auc(pROC::roc(y01, p, quiet = TRUE,
                                         levels = c(0, 1), direction = "<")))
  data.frame(
    auc            = auc,
    acuracia       = (vp + vn) / length(y01),
    sensibilidade  = sens,
    especificidade = espec,
    precisao       = prec,
    f1             = if (is.na(prec) || (prec + sens) == 0) NA_real_ else 2 * prec * sens / (prec + sens),
    brier          = mean((p - y01)^2)
  )
}

# ---- 5. Folds estratificados repetidos ---------------------------------------
criar_folds <- function(y, k = K_FOLDS, repeticoes = N_REPETICOES, semente = SEMENTE) {
  set.seed(semente)
  lapply(seq_len(repeticoes), function(r) {
    fold <- integer(length(y))
    for (cls in levels(y)) {
      idx <- which(y == cls)
      fold[idx] <- sample(rep_len(seq_len(k), length(idx)))
    }
    fold
  })
}

# ---- 6. Teste t corrigido para CV repetida (Nadeau & Bengio, 2003) -----------
# As diferenças entre folds não são independentes (os treinos se sobrepõem),
# então a variância é corrigida pelo fator (1/J + n_teste/n_treino).
teste_t_corrigido <- function(diferencas, n_treino, n_teste) {
  J <- length(diferencas)
  m <- mean(diferencas); v <- var(diferencas)
  ep <- sqrt((1 / J + n_teste / n_treino) * v)
  t  <- m / ep
  gl <- J - 1
  ic <- m + c(-1, 1) * qt(0.975, gl) * ep
  data.frame(diferenca_media = m, ic95_inf = ic[1], ic95_sup = ic[2],
             t = t, gl = gl, p_valor = 2 * pt(-abs(t), gl))
}
