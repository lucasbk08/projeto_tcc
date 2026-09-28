# =============================================================================
# cdc/02_validacao_cruzada.R — 4 modelos, CV estratificada 5-fold x 2
# =============================================================================
# Mesma lógica do Pima (R/02_validacao_cruzada.R), mas sem estratégias de
# ausentes: a base CDC não tem valores faltantes.
# Saídas:
#   resultados/cdc/tabelas/02_cv_por_fold.csv  (uma linha por fold/modelo)
#   resultados/cdc/tabelas/02_curvas_roc.csv   (curvas ROC fora-do-fold da 1ª
#                                               repetição, resumidas a ~500 pontos)
# Tempo aproximado na base inteira: ~30–60 min (o gradient boosting é o mais lento).
# =============================================================================

folds_cdc <- criar_folds(cdc$diabetes, k = CDC_K_FOLDS, repeticoes = CDC_N_REPETICOES)

res_cdc <- list(); oof_rep1 <- list()
t0 <- Sys.time()
for (r in seq_len(CDC_N_REPETICOES)) {
  for (k in seq_len(CDC_K_FOLDS)) {
    idx_te <- which(folds_cdc[[r]] == k)
    treino <- cdc[-idx_te, ]; teste <- cdc[idx_te, ]
    prev_treino <- mean(treino$diabetes == "pos")
    for (nome_mod in names(MODELOS_CDC)) {
      set.seed(SEMENTE + 1000 * r + k)   # mesma semente para todos os modelos
      t_mod <- Sys.time()
      mod <- MODELOS_CDC[[nome_mod]]$ajustar(treino)
      p   <- MODELOS_CDC[[nome_mod]]$prever(mod, teste)
      rm(mod); invisible(gc())
      met <- calcular_metricas_cdc(teste$diabetes, p, prev_treino)
      res_cdc[[length(res_cdc) + 1]] <- cbind(
        modelo = nome_mod, repeticao = r, fold = k,
        n_treino = nrow(treino), n_teste = nrow(teste), met,
        segundos = round(as.numeric(difftime(Sys.time(), t_mod, units = "secs"))))
      if (r == 1) oof_rep1[[length(oof_rep1) + 1]] <-
        data.frame(modelo = nome_mod, y = teste$diabetes, prob = p)
    }
    cat(sprintf("   repetição %d, fold %d/%d ok (%.1f min)\n", r, k, CDC_K_FOLDS,
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
}
res_cdc <- do.call(rbind, res_cdc)
write.csv(res_cdc, file.path(DIR_CDC_TABELAS, "02_cv_por_fold.csv"), row.names = FALSE)

# ---- Curvas ROC fora-do-fold (1ª repetição: cada pessoa prevista uma vez) ----
# As 253 mil predições por modelo não vão para o Git (seriam ~40 MB); guardam-se
# só ~500 pontos de cada curva, o suficiente para desenhá-la.
oof_rep1 <- do.call(rbind, oof_rep1)
roc_cdc <- do.call(rbind, lapply(names(MODELOS_CDC), function(mod) {
  d  <- oof_rep1[oof_rep1$modelo == mod, ]
  ro <- pROC::roc(d$y == "pos", d$prob, quiet = TRUE, levels = c(FALSE, TRUE), direction = "<")
  fpr <- 1 - ro$specificities; tpr <- ro$sensitivities
  manter <- unique(round(seq(1, length(fpr), length.out = min(500, length(fpr)))))
  data.frame(modelo = mod, fpr = fpr[manter], tpr = tpr[manter], auc = as.numeric(ro$auc))
}))
write.csv(roc_cdc, file.path(DIR_CDC_TABELAS, "02_curvas_roc.csv"), row.names = FALSE)
rm(oof_rep1); invisible(gc())

cat(sprintf("\nValidação cruzada concluída em %.1f min.\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("Tempo médio por ajuste (s):\n")
print(round(tapply(res_cdc$segundos, res_cdc$modelo, mean)))
