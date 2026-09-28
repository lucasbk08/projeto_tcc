# =============================================================================
# 02_validacao_cruzada.R — 4 modelos x 4 estratégias de ausentes, CV 10x5
# =============================================================================
# Para cada repetição r e fold k:
#   1. separa treino/teste (estratificado pela classe)
#   2. aplica a estratégia de ausentes (aprendida SÓ no treino)
#   3. ajusta os 4 modelos no treino e prevê o teste
#   4. calcula AUC, acurácia, sensibilidade, especificidade, precisão, F1, Brier
# Saídas:
#   resultados/tabelas/02_cv_por_fold.csv      (uma linha por fold/modelo/estratégia)
#   resultados/tabelas/02_predicoes_oof.csv    (predições fora-do-fold, p/ curvas ROC)
# Tempo aproximado: 5–10 min (o MICE é a parte mais lenta).
# =============================================================================

folds <- criar_folds(pima$diabetes)

res_folds <- list(); preds <- list()
t0 <- Sys.time()
for (nome_est in names(ESTRATEGIAS)) {
  cat(sprintf("\n>> Estratégia: %s\n", ROTULOS_ESTRATEGIAS[[nome_est]]))
  for (r in seq_len(N_REPETICOES)) {
    for (k in seq_len(K_FOLDS)) {
      idx_te <- which(folds[[r]] == k)
      set.seed(SEMENTE + 1000 * r + k)  # mesma semente para todos os modelos
      dados <- ESTRATEGIAS[[nome_est]](pima[-idx_te, ], pima[idx_te, ])
      for (nome_mod in names(MODELOS)) {
        set.seed(SEMENTE + 1000 * r + k)
        mod <- MODELOS[[nome_mod]]$ajustar(dados$treino)
        p   <- MODELOS[[nome_mod]]$prever(mod, dados$teste)
        met <- calcular_metricas(dados$teste$diabetes, p)
        res_folds[[length(res_folds) + 1]] <- cbind(
          estrategia = nome_est, modelo = nome_mod, repeticao = r, fold = k,
          n_treino = nrow(dados$treino), n_teste = nrow(dados$teste), met)
        preds[[length(preds) + 1]] <- data.frame(
          estrategia = nome_est, modelo = nome_mod, repeticao = r, fold = k,
          id = as.integer(rownames(dados$teste)),
          y = dados$teste$diabetes, prob = p)
      }
    }
    cat(sprintf("   repetição %d/%d ok (%.1f min)\n", r, N_REPETICOES,
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
}

res_folds <- do.call(rbind, res_folds)
preds     <- do.call(rbind, preds)
write.csv(res_folds, file.path(DIR_TABELAS, "02_cv_por_fold.csv"), row.names = FALSE)
write.csv(preds,     file.path(DIR_TABELAS, "02_predicoes_oof.csv"), row.names = FALSE)
cat(sprintf("\nValidação cruzada concluída em %.1f min.\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
