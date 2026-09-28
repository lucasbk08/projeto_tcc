# =============================================================================
# 03_comparacao.R — responde aos objetivos específicos 2, 3 e 4
# =============================================================================
# Obj. 2: comparar ensembles (RF, GBM) com a regressão logística (métrica: AUC)
# Obj. 3: a perda de AUC ao escolher o modelo mais interpretável é > 0,05?
# Obj. 4: impacto do tratamento de ausentes no desempenho e na estabilidade
# Saídas:
#   resultados/tabelas/03_resumo_desempenho.csv
#   resultados/tabelas/03_logistica_vs_modelos.csv
#   resultados/tabelas/03_efeito_ausentes.csv
#   resultados/figuras/03_auc_por_modelo.png
#   resultados/figuras/03_curvas_roc.png
#   resultados/figuras/03_estrategias_ausentes.png
# =============================================================================

if (!exists("res_folds")) {
  res_folds <- read.csv(file.path(DIR_TABELAS, "02_cv_por_fold.csv"))
  preds     <- read.csv(file.path(DIR_TABELAS, "02_predicoes_oof.csv"))
}

metricas <- c("auc", "acuracia", "sensibilidade", "especificidade", "precisao", "f1", "brier")

# ---- Tabela resumo: média, DP e IC95% por modelo x estratégia ----------------
resumo <- do.call(rbind, lapply(split(res_folds, list(res_folds$estrategia, res_folds$modelo)),
  function(d) {
    linha <- data.frame(estrategia = d$estrategia[1], modelo = d$modelo[1],
                        n_avaliacoes = nrow(d))
    for (m in metricas) {
      linha[[paste0(m, "_media")]] <- mean(d[[m]], na.rm = TRUE)
      linha[[paste0(m, "_dp")]]    <- sd(d[[m]], na.rm = TRUE)
    }
    linha
  }))
resumo <- resumo[order(resumo$estrategia, -resumo$auc_media), ]
rownames(resumo) <- NULL
write.csv(resumo, file.path(DIR_TABELAS, "03_resumo_desempenho.csv"), row.names = FALSE)

fmt <- function(m, s) sprintf("%.3f ± %.3f", m, s)
cat("\n== Desempenho (média ± DP em 50 folds) — estratégia principal ==\n")
princ <- resumo[resumo$estrategia == ESTRATEGIA_PRINCIPAL, ]
print(data.frame(
  modelo = ROTULOS_MODELOS[princ$modelo],
  AUC = fmt(princ$auc_media, princ$auc_dp),
  Acuracia = fmt(princ$acuracia_media, princ$acuracia_dp),
  Sensib = fmt(princ$sensibilidade_media, princ$sensibilidade_dp),
  Especif = fmt(princ$especificidade_media, princ$especificidade_dp),
  F1 = fmt(princ$f1_media, princ$f1_dp),
  Brier = fmt(princ$brier_media, princ$brier_dp)), row.names = FALSE)

# ---- Objetivos 2 e 3: logística vs. cada modelo (pareado por fold) -----------
comparar_com_logistica <- function(est) {
  d  <- res_folds[res_folds$estrategia == est, ]
  lr <- d[d$modelo == "logistica", ]
  do.call(rbind, lapply(setdiff(names(MODELOS), "logistica"), function(mod) {
    outro <- d[d$modelo == mod, ]
    outro <- outro[match(paste(lr$repeticao, lr$fold), paste(outro$repeticao, outro$fold)), ]
    dif <- outro$auc - lr$auc   # > 0: o outro modelo é melhor que a logística
    tt  <- teste_t_corrigido(dif, mean(lr$n_treino), mean(lr$n_teste))
    cbind(estrategia = est, modelo = mod,
          auc_modelo = mean(outro$auc), auc_logistica = mean(lr$auc), tt,
          ganho_relevante = tt$diferenca_media > DELTA_AUC_RELEVANTE,
          folds_modelo_vence = mean(dif > 0))
  }))
}
comp <- do.call(rbind, lapply(names(ESTRATEGIAS), comparar_com_logistica))
write.csv(comp, file.path(DIR_TABELAS, "03_logistica_vs_modelos.csv"), row.names = FALSE)

cat("\n== ΔAUC = modelo − regressão logística (teste t corrigido de Nadeau & Bengio) ==\n")
cp <- comp[comp$estrategia == ESTRATEGIA_PRINCIPAL, ]
print(data.frame(
  modelo = ROTULOS_MODELOS[cp$modelo],
  delta_AUC = sprintf("%+.3f", cp$diferenca_media),
  IC95 = sprintf("[%+.3f; %+.3f]", cp$ic95_inf, cp$ic95_sup),
  p = sprintf("%.3f", cp$p_valor),
  `supera LR em > 0,05?` = ifelse(cp$ganho_relevante, "SIM", "não"),
  check.names = FALSE), row.names = FALSE)

melhor <- princ$modelo[which.max(princ$auc_media)]
cat(sprintf("\nMelhor AUC média (%s): %s\n", ESTRATEGIA_PRINCIPAL, ROTULOS_MODELOS[[melhor]]))

# ---- Objetivo 3: perda ao trocar o melhor modelo por um interpretável -------
# Perda = AUC(melhor) − AUC(interpretável). Relevante se a perda média > 0,05.
# Também se reporta o limite superior do IC 95%: se ele fica abaixo de 0,05,
# há evidência de que a perda NÃO é clinicamente relevante.
perda_interpretavel <- function(est) {
  d <- res_folds[res_folds$estrategia == est, ]
  medias_est <- tapply(d$auc, d$modelo, mean)
  top <- names(which.max(medias_est))
  b <- d[d$modelo == top, ]
  do.call(rbind, lapply(c("logistica", "arvore"), function(interp) {
    i <- d[d$modelo == interp, ]
    i <- i[match(paste(b$repeticao, b$fold), paste(i$repeticao, i$fold)), ]
    tt <- teste_t_corrigido(b$auc - i$auc, mean(b$n_treino), mean(b$n_teste))
    data.frame(estrategia = est, melhor_modelo = top, modelo_interpretavel = interp,
          auc_melhor = mean(b$auc), auc_interpretavel = mean(i$auc),
          perda_auc = tt$diferenca_media, ic95_inf = tt$ic95_inf, ic95_sup = tt$ic95_sup,
          p_valor = tt$p_valor,
          perda_relevante = tt$diferenca_media > DELTA_AUC_RELEVANTE,
          ic_exclui_relevante = tt$ic95_sup < DELTA_AUC_RELEVANTE)
  }))
}
obj3 <- do.call(rbind, lapply(names(ESTRATEGIAS), perda_interpretavel))
write.csv(obj3, file.path(DIR_TABELAS, "03_objetivo3_perda_interpretabilidade.csv"), row.names = FALSE)
cat("\n== Objetivo 3: perda de AUC ao escolher o modelo interpretável (limite: 0,05) ==\n")
o3 <- obj3[obj3$estrategia == ESTRATEGIA_PRINCIPAL, ]
print(data.frame(
  melhor = ROTULOS_MODELOS[o3$melhor_modelo],
  interpretavel = ROTULOS_MODELOS[o3$modelo_interpretavel],
  perda = sprintf("%.3f", o3$perda_auc),
  IC95 = sprintf("[%.3f; %.3f]", o3$ic95_inf, o3$ic95_sup),
  relevante = ifelse(o3$perda_relevante, "SIM (> 0,05)", "não (≤ 0,05)")),
  row.names = FALSE)

# ---- Objetivo 4: efeito do tratamento de ausentes ----------------------------
# Comparação pareada com a linha de base "zeros mantidos". A estratégia de
# casos completos usa outra amostra (392 pacientes), então sua comparação é
# apenas descritiva (não pareada).
efeito <- do.call(rbind, lapply(names(MODELOS), function(mod) {
  base <- res_folds[res_folds$estrategia == "zeros_mantidos" & res_folds$modelo == mod, ]
  do.call(rbind, lapply(names(ESTRATEGIAS), function(est) {
    d <- res_folds[res_folds$estrategia == est & res_folds$modelo == mod, ]
    linha <- data.frame(modelo = mod, estrategia = est,
                        auc_media = mean(d$auc), auc_dp = sd(d$auc),
                        coef_variacao = sd(d$auc) / mean(d$auc),
                        amplitude = diff(range(d$auc)),
                        n_pacientes = round(mean(d$n_treino + d$n_teste)))
    if (est %in% c("mediana", "mice")) {
      d <- d[match(paste(base$repeticao, base$fold), paste(d$repeticao, d$fold)), ]
      tt <- teste_t_corrigido(d$auc - base$auc, mean(d$n_treino), mean(d$n_teste))
      linha$delta_vs_zeros <- tt$diferenca_media; linha$p_valor <- tt$p_valor
    } else {
      linha$delta_vs_zeros <- if (est == "zeros_mantidos") 0 else mean(d$auc) - mean(base$auc)
      linha$p_valor <- NA
    }
    linha
  }))
}))
write.csv(efeito, file.path(DIR_TABELAS, "03_efeito_ausentes.csv"), row.names = FALSE)
cat("\n== Efeito do tratamento de ausentes na AUC (média ± DP) ==\n")
tab4 <- reshape(efeito[, c("modelo", "estrategia", "auc_media")], idvar = "modelo",
                timevar = "estrategia", direction = "wide")
names(tab4) <- sub("auc_media.", "", names(tab4))
tab4$modelo <- ROTULOS_MODELOS[tab4$modelo]
print(format(tab4, digits = 3), row.names = FALSE)

# ---- Figura: AUC por modelo (estratégia principal) --------------------------
dp <- res_folds[res_folds$estrategia == ESTRATEGIA_PRINCIPAL, ]
ordem <- names(sort(tapply(dp$auc, dp$modelo, mean)))
dp$modelo_f <- factor(dp$modelo, levels = ordem, labels = ROTULOS_MODELOS[ordem])
medias <- aggregate(auc ~ modelo + modelo_f, dp, mean)
g_auc <- ggplot(dp, aes(x = auc, y = modelo_f, colour = modelo)) +
  geom_jitter(height = 0.15, width = 0, alpha = 0.35, size = 1.8) +
  geom_boxplot(fill = NA, outlier.shape = NA, width = 0.5, linewidth = 0.5,
               colour = "#52514e") +
  geom_point(data = medias, shape = 21, size = 3.5, fill = "white", stroke = 1.4) +
  geom_text(data = medias, aes(label = sprintf("%.3f", auc)), colour = "#0b0b0b",
            nudge_y = 0.38, size = 3.8, fontface = "bold") +
  scale_colour_manual(values = CORES_MODELOS, guide = "none") +
  labs(title = "AUC-ROC na validação cruzada 10-fold × 5 repetições",
       subtitle = sprintf("Ausentes: %s · ponto = 1 fold · círculo = média",
                          ROTULOS_ESTRATEGIAS[[ESTRATEGIA_PRINCIPAL]]),
       x = "AUC-ROC", y = NULL) +
  tema_tcc()
ggsave(file.path(DIR_FIGURAS, "03_auc_por_modelo.png"), g_auc, width = 8, height = 4.5, dpi = 300)

# ---- Figura: curvas ROC (predições fora-do-fold, repetição 1) ---------------
pr <- preds[preds$estrategia == ESTRATEGIA_PRINCIPAL & preds$repeticao == 1, ]
rocs <- do.call(rbind, lapply(names(MODELOS), function(mod) {
  d <- pr[pr$modelo == mod, ]
  ro <- pROC::roc(d$y == "pos", d$prob, quiet = TRUE, levels = c(FALSE, TRUE), direction = "<")
  data.frame(modelo = mod, fpr = 1 - ro$specificities, tpr = ro$sensitivities,
             rotulo = sprintf("%s (AUC = %.3f)", ROTULOS_MODELOS[[mod]], as.numeric(ro$auc)))
}))
rocs <- rocs[order(rocs$modelo, rocs$fpr, rocs$tpr), ]
rot <- unique(rocs[, c("modelo", "rotulo")])
rocs$modelo <- factor(rocs$modelo, levels = names(ROTULOS_MODELOS))
g_roc <- ggplot(rocs, aes(x = fpr, y = tpr, colour = modelo)) +
  geom_abline(linetype = "dashed", colour = "#b5b4ad", linewidth = 0.4) +
  geom_step(linewidth = 0.8, direction = "hv") +
  scale_colour_manual(values = CORES_MODELOS, labels = setNames(rot$rotulo, rot$modelo),
                      breaks = names(ROTULOS_MODELOS)) +
  coord_equal() +
  labs(title = "Curvas ROC dos quatro modelos",
       subtitle = "Predições fora-do-fold, 768 pacientes (1ª repetição da CV)",
       x = "1 − Especificidade (taxa de falsos positivos)",
       y = "Sensibilidade", colour = NULL) +
  guides(colour = guide_legend(ncol = 2)) +
  tema_tcc()
ggsave(file.path(DIR_FIGURAS, "03_curvas_roc.png"), g_roc, width = 7, height = 7.5, dpi = 300)

# ---- Figura: estratégias de ausentes x modelo -------------------------------
ef <- efeito
ef$estrategia_f <- factor(ef$estrategia, levels = names(ROTULOS_ESTRATEGIAS),
                          labels = c("Zeros\nmantidos", "Casos\ncompletos", "Mediana", "MICE"))
ef$modelo_f <- factor(ef$modelo, levels = names(ROTULOS_MODELOS), labels = ROTULOS_MODELOS)
g_aus <- ggplot(ef, aes(x = estrategia_f, y = auc_media, colour = modelo, group = modelo)) +
  geom_line(linewidth = 0.6, alpha = 0.6, position = position_dodge(width = 0.4)) +
  geom_pointrange(aes(ymin = auc_media - auc_dp, ymax = auc_media + auc_dp),
                  position = position_dodge(width = 0.4), size = 0.5, linewidth = 0.6) +
  scale_colour_manual(values = CORES_MODELOS, labels = ROTULOS_MODELOS,
                      breaks = names(ROTULOS_MODELOS)) +
  labs(title = "Efeito do tratamento dos valores ausentes",
       subtitle = "AUC média ± 1 DP entre os 50 folds (DP = estabilidade)",
       x = NULL, y = "AUC-ROC", colour = NULL) +
  tema_tcc()
ggsave(file.path(DIR_FIGURAS, "03_estrategias_ausentes.png"), g_aus, width = 8.5, height = 5, dpi = 300)
