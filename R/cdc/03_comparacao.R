# =============================================================================
# cdc/03_comparacao.R — objetivos 2 e 3 no CDC + comparação com o Pima
# =============================================================================
# Obj. 2: os ensembles (RF, GBM) superam a regressão logística?
# Obj. 3: a perda de AUC ao trocar o melhor modelo pelo interpretável é > 0,05?
# Extra: o resultado do Pima se repete numa base 330x maior?
# Saídas:
#   resultados/cdc/tabelas/03_resumo_desempenho.csv
#   resultados/cdc/tabelas/03_logistica_vs_modelos.csv
#   resultados/cdc/tabelas/03_objetivo3_perda_interpretabilidade.csv
#   resultados/cdc/tabelas/03_pima_vs_cdc.csv
#   resultados/cdc/figuras/03_auc_por_modelo.png
#   resultados/cdc/figuras/03_curvas_roc.png
#   resultados/cdc/figuras/03_pima_vs_cdc.png
# =============================================================================

if (!exists("res_cdc")) {
  res_cdc <- read.csv(file.path(DIR_CDC_TABELAS, "02_cv_por_fold.csv"))
  roc_cdc <- read.csv(file.path(DIR_CDC_TABELAS, "02_curvas_roc.csv"))
}
n_aval <- CDC_K_FOLDS * CDC_N_REPETICOES

# ---- Resumo: média e DP por modelo ---------------------------------------------
metricas_cdc <- c("auc", "auc_pr", "brier", "acuracia", "sensibilidade", "especificidade",
                  "f1", "sensibilidade_lprev", "especificidade_lprev", "f1_lprev")
resumo_cdc <- do.call(rbind, lapply(split(res_cdc, res_cdc$modelo), function(d) {
  linha <- data.frame(modelo = d$modelo[1], n_avaliacoes = nrow(d))
  for (m in metricas_cdc) {
    linha[[paste0(m, "_media")]] <- mean(d[[m]], na.rm = TRUE)
    linha[[paste0(m, "_dp")]]    <- sd(d[[m]], na.rm = TRUE)
  }
  linha
}))
resumo_cdc <- resumo_cdc[order(-resumo_cdc$auc_media), ]
rownames(resumo_cdc) <- NULL
write.csv(resumo_cdc, file.path(DIR_CDC_TABELAS, "03_resumo_desempenho.csv"), row.names = FALSE)

fmt <- function(m, s) sprintf("%.3f ± %.3f", m, s)
cat(sprintf("\n== Desempenho no CDC (média ± DP em %d folds) ==\n", n_aval))
print(data.frame(
  modelo    = ROTULOS_MODELOS[resumo_cdc$modelo],
  AUC       = fmt(resumo_cdc$auc_media, resumo_cdc$auc_dp),
  `AUC-PR`  = fmt(resumo_cdc$auc_pr_media, resumo_cdc$auc_pr_dp),
  Brier     = fmt(resumo_cdc$brier_media, resumo_cdc$brier_dp),
  check.names = FALSE), row.names = FALSE)
cat("\nMétricas de classe: limiar 0,5 vs. limiar = prevalência do treino (~0,14)\n")
print(data.frame(
  modelo           = ROTULOS_MODELOS[resumo_cdc$modelo],
  `Sensib (0,5)`   = sprintf("%.3f", resumo_cdc$sensibilidade_media),
  `Especif (0,5)`  = sprintf("%.3f", resumo_cdc$especificidade_media),
  `Sensib (prev)`  = sprintf("%.3f", resumo_cdc$sensibilidade_lprev_media),
  `Especif (prev)` = sprintf("%.3f", resumo_cdc$especificidade_lprev_media),
  check.names = FALSE), row.names = FALSE)

# ---- Objetivo 2: logística vs. cada modelo (pareado por fold) ------------------
lr_cdc <- res_cdc[res_cdc$modelo == "logistica", ]
comp_cdc <- do.call(rbind, lapply(setdiff(names(MODELOS_CDC), "logistica"), function(mod) {
  outro <- res_cdc[res_cdc$modelo == mod, ]
  outro <- outro[match(paste(lr_cdc$repeticao, lr_cdc$fold), paste(outro$repeticao, outro$fold)), ]
  dif <- outro$auc - lr_cdc$auc
  tt  <- teste_t_corrigido(dif, mean(lr_cdc$n_treino), mean(lr_cdc$n_teste))
  cbind(modelo = mod, auc_modelo = mean(outro$auc), auc_logistica = mean(lr_cdc$auc), tt,
        ganho_relevante = tt$diferenca_media > DELTA_AUC_RELEVANTE,
        folds_modelo_vence = mean(dif > 0))
}))
write.csv(comp_cdc, file.path(DIR_CDC_TABELAS, "03_logistica_vs_modelos.csv"), row.names = FALSE)
cat("\n== ΔAUC = modelo − regressão logística (teste t corrigido de Nadeau & Bengio) ==\n")
print(data.frame(
  modelo    = ROTULOS_MODELOS[comp_cdc$modelo],
  delta_AUC = sprintf("%+.4f", comp_cdc$diferenca_media),
  IC95      = sprintf("[%+.4f; %+.4f]", comp_cdc$ic95_inf, comp_cdc$ic95_sup),
  p         = sprintf("%.4f", comp_cdc$p_valor),
  `vence em % dos folds` = sprintf("%.0f%%", 100 * comp_cdc$folds_modelo_vence),
  `supera LR em > 0,05?` = ifelse(comp_cdc$ganho_relevante, "SIM", "não"),
  check.names = FALSE), row.names = FALSE)

# ---- Objetivo 3: perda ao trocar o melhor modelo por um interpretável ----------
top_cdc <- resumo_cdc$modelo[1]
b <- res_cdc[res_cdc$modelo == top_cdc, ]
obj3_cdc <- do.call(rbind, lapply(setdiff(c("logistica", "arvore"), top_cdc), function(interp) {
  i <- res_cdc[res_cdc$modelo == interp, ]
  i <- i[match(paste(b$repeticao, b$fold), paste(i$repeticao, i$fold)), ]
  tt <- teste_t_corrigido(b$auc - i$auc, mean(b$n_treino), mean(b$n_teste))
  data.frame(melhor_modelo = top_cdc, modelo_interpretavel = interp,
             auc_melhor = mean(b$auc), auc_interpretavel = mean(i$auc),
             perda_auc = tt$diferenca_media, ic95_inf = tt$ic95_inf, ic95_sup = tt$ic95_sup,
             p_valor = tt$p_valor,
             perda_relevante = tt$diferenca_media > DELTA_AUC_RELEVANTE,
             ic_exclui_relevante = tt$ic95_sup < DELTA_AUC_RELEVANTE)
}))
write.csv(obj3_cdc, file.path(DIR_CDC_TABELAS, "03_objetivo3_perda_interpretabilidade.csv"),
          row.names = FALSE)
cat(sprintf("\n== Objetivo 3: perda de AUC ao trocar %s pelo interpretável (limite: 0,05) ==\n",
            ROTULOS_MODELOS[[top_cdc]]))
print(data.frame(
  interpretavel = ROTULOS_MODELOS[obj3_cdc$modelo_interpretavel],
  perda = sprintf("%.4f", obj3_cdc$perda_auc),
  IC95  = sprintf("[%.4f; %.4f]", obj3_cdc$ic95_inf, obj3_cdc$ic95_sup),
  relevante = ifelse(obj3_cdc$perda_relevante, "SIM (> 0,05)", "não (≤ 0,05)")),
  row.names = FALSE)

# ---- Pima vs. CDC: a conclusão se repete? -------------------------------------
arq_pima <- file.path(DIR_TABELAS, "03_resumo_desempenho.csv")
if (file.exists(arq_pima)) {
  rp <- read.csv(arq_pima)
  rp <- rp[rp$estrategia == ESTRATEGIA_PRINCIPAL, ]
  n_cdc <- round(mean(res_cdc$n_treino + res_cdc$n_teste))
  pv <- rbind(
    data.frame(base = "Pima (n = 768)", modelo = rp$modelo,
               auc = rp$auc_media, auc_dp = rp$auc_dp, brier = rp$brier_media),
    data.frame(base = sprintf("CDC (n = %s)", fmt_n(n_cdc)),
               modelo = resumo_cdc$modelo, auc = resumo_cdc$auc_media,
               auc_dp = resumo_cdc$auc_dp, brier = resumo_cdc$brier_media))
  auc_lr_base <- tapply(pv$auc[pv$modelo == "logistica"], pv$base[pv$modelo == "logistica"], mean)
  pv$delta_vs_logistica <- pv$auc - auc_lr_base[pv$base]
  write.csv(pv, file.path(DIR_CDC_TABELAS, "03_pima_vs_cdc.csv"), row.names = FALSE)
  cat("\n== Pima vs. CDC: AUC média (e diferença para a logística) ==\n")
  tab <- reshape(pv[, c("base", "modelo", "auc")], idvar = "modelo", timevar = "base",
                 direction = "wide")
  names(tab) <- sub("auc.", "", names(tab), fixed = TRUE)
  tab$modelo <- ROTULOS_MODELOS[tab$modelo]
  print(format(tab, digits = 3), row.names = FALSE)

  pv$base <- factor(pv$base, levels = unique(pv$base))
  pv$modelo_f <- factor(pv$modelo, levels = rev(names(ROTULOS_MODELOS)),
                        labels = rev(ROTULOS_MODELOS))
  g_pv <- ggplot(pv, aes(x = auc, y = modelo_f, colour = modelo)) +
    geom_errorbar(aes(xmin = auc - auc_dp, xmax = auc + auc_dp), width = 0.25,
                  linewidth = 0.6, orientation = "y") +
    geom_point(size = 3.2) +
    geom_text(aes(label = num(auc)), nudge_y = 0.32, size = 3.6,
              colour = "#0b0b0b") +
    facet_wrap(~ base, nrow = 1) +
    scale_colour_manual(values = CORES_MODELOS, guide = "none") +
    labs(title = "A mesma comparação em duas bases",
         subtitle = "AUC-ROC média ± 1 DP entre folds · Pima: exames clínicos · CDC: questionário autodeclarado",
         x = "AUC-ROC", y = NULL) +
    tema_tcc() + theme(panel.spacing = unit(1.5, "lines"))
  ggsave(file.path(DIR_CDC_FIGURAS, "03_pima_vs_cdc.png"), g_pv, width = 10, height = 4.5, dpi = 300)
} else {
  cat("\n(Resultados do Pima não encontrados; rode run_all.R para gerar a comparação.)\n")
}

# ---- Figura: AUC-ROC e AUC-PR por modelo ---------------------------------------
longo <- rbind(
  data.frame(metrica = "AUC-ROC", modelo = res_cdc$modelo, valor = res_cdc$auc),
  data.frame(metrica = "AUC-PR",  modelo = res_cdc$modelo, valor = res_cdc$auc_pr))
longo$metrica <- factor(longo$metrica, levels = c("AUC-ROC", "AUC-PR"))
ordem <- rev(resumo_cdc$modelo)
longo$modelo_f <- factor(longo$modelo, levels = ordem, labels = ROTULOS_MODELOS[ordem])
medias <- aggregate(valor ~ metrica + modelo + modelo_f, longo, mean)
g_auc <- ggplot(longo, aes(x = valor, y = modelo_f, colour = modelo)) +
  geom_point(alpha = 0.45, size = 2.2, position = position_jitter(height = 0.12, width = 0, seed = 1)) +
  geom_point(data = medias, shape = 21, size = 3.8, fill = "white", stroke = 1.4) +
  geom_text(data = medias, aes(label = num(valor)), colour = "#0b0b0b",
            nudge_y = 0.36, size = 3.6, fontface = "bold") +
  facet_wrap(~ metrica, scales = "free_x") +
  scale_colour_manual(values = CORES_MODELOS, guide = "none") +
  labs(title = sprintf("Desempenho no CDC: validação cruzada %d-fold × %d",
                       CDC_K_FOLDS, CDC_N_REPETICOES),
       subtitle = sprintf("ponto = 1 fold · círculo = média · AUC-PR de um chute = prevalência (%s)",
                          num(mean(res_cdc$limiar_prev), 2)),
       x = NULL, y = NULL) +
  tema_tcc() + theme(panel.spacing = unit(1.5, "lines"))
ggsave(file.path(DIR_CDC_FIGURAS, "03_auc_por_modelo.png"), g_auc, width = 10, height = 4.5, dpi = 300)

# ---- Figura: curvas ROC ----------------------------------------------------------
rot <- unique(roc_cdc[, c("modelo", "auc")])
rot$rotulo <- sprintf("%s (AUC = %s)", ROTULOS_MODELOS[rot$modelo], num(rot$auc))
roc_cdc$modelo <- factor(roc_cdc$modelo, levels = names(ROTULOS_MODELOS))
g_roc <- ggplot(roc_cdc, aes(x = fpr, y = tpr, colour = modelo)) +
  geom_abline(linetype = "dashed", colour = "#b5b4ad", linewidth = 0.4) +
  geom_line(linewidth = 0.8) +
  scale_colour_manual(values = CORES_MODELOS, labels = setNames(rot$rotulo, rot$modelo),
                      breaks = names(ROTULOS_MODELOS)) +
  coord_equal() +
  labs(title = "Curvas ROC dos quatro modelos (CDC)",
       subtitle = "Predições fora-do-fold de todas as pessoas (1ª repetição da CV)",
       x = "1 − Especificidade (taxa de falsos positivos)",
       y = "Sensibilidade", colour = NULL) +
  guides(colour = guide_legend(ncol = 2)) +
  tema_tcc()
ggsave(file.path(DIR_CDC_FIGURAS, "03_curvas_roc.png"), g_roc, width = 7, height = 7.5, dpi = 300)
