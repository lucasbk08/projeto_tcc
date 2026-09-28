# =============================================================================
# 04_interpretabilidade.R — o que cada modelo "aprendeu"
# =============================================================================
# Os modelos finais são ajustados com TODOS os 768 pacientes (estratégia
# principal de ausentes). Aqui não se mede desempenho (isso é papel da CV),
# só se inspeciona o raciocínio de cada modelo.
#   - Regressão logística: odds ratios por 1 desvio-padrão, com IC 95%
#   - Árvore de decisão: a própria árvore + regras em texto
#   - Random forest: importância por permutação (queda de acurácia)
#   - Gradient boosting: influência relativa
# Saídas:
#   resultados/tabelas/04_odds_ratios.csv
#   resultados/tabelas/04_regras_arvore.txt
#   resultados/tabelas/04_importancia_variaveis.csv
#   resultados/figuras/04_odds_ratios.png
#   resultados/figuras/04_arvore_decisao.png
#   resultados/figuras/04_importancia_variaveis.png
#   resultados/modelos/modelos_finais.rds
# =============================================================================

set.seed(SEMENTE)
completo <- ESTRATEGIAS[[ESTRATEGIA_PRINCIPAL]](pima, pima[0, ])$treino

# ---- Regressão logística (preditores padronizados) ---------------------------
# Padronizar deixa os odds ratios comparáveis: "quanto a chance de diabetes
# muda quando a variável sobe 1 desvio-padrão".
vars <- names(ROTULOS_VARS)
padron <- completo
padron[vars] <- scale(completo[vars])
glm_final <- glm(diabetes ~ ., data = padron, family = binomial)
ic <- suppressMessages(confint.default(glm_final))
or <- data.frame(
  variavel  = names(coef(glm_final))[-1],
  rotulo    = ROTULOS_VARS[names(coef(glm_final))[-1]],
  dp_original = sapply(completo[vars], sd)[names(coef(glm_final))[-1]],
  odds_ratio = exp(coef(glm_final))[-1],
  ic95_inf   = exp(ic[-1, 1]),
  ic95_sup   = exp(ic[-1, 2]),
  p_valor    = summary(glm_final)$coefficients[-1, 4],
  row.names = NULL
)
or <- or[order(-or$odds_ratio), ]
write.csv(or, file.path(DIR_TABELAS, "04_odds_ratios.csv"), row.names = FALSE)
cat("\n== Regressão logística: odds ratio por +1 DP ==\n")
print(data.frame(variavel = or$rotulo,
                 `+1 DP =` = sprintf("%.1f", or$dp_original),
                 OR = sprintf("%.2f", or$odds_ratio),
                 IC95 = sprintf("[%.2f; %.2f]", or$ic95_inf, or$ic95_sup),
                 p = format.pval(or$p_valor, digits = 2, eps = 0.001),
                 check.names = FALSE), row.names = FALSE)

or$rotulo_f <- factor(or$rotulo, levels = rev(or$rotulo))
or$signif <- ifelse(or$p_valor < 0.05, "p < 0,05", "p ≥ 0,05")
g_or <- ggplot(or, aes(x = odds_ratio, y = rotulo_f)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "#b5b4ad") +
  geom_errorbarh(aes(xmin = ic95_inf, xmax = ic95_sup), height = 0.25,
                 colour = "#2a78d6", linewidth = 0.6) +
  geom_point(aes(shape = signif), size = 3, colour = "#2a78d6", fill = "white", stroke = 1.2) +
  geom_text(aes(x = ic95_sup, label = sprintf("%.2f", odds_ratio)), hjust = -0.3,
            size = 3.8, colour = "#0b0b0b") +
  scale_x_log10(expand = expansion(mult = c(0.05, 0.12))) +
  scale_shape_manual(values = c("p < 0,05" = 16, "p ≥ 0,05" = 21)) +
  labs(title = "Regressão logística: odds ratio por +1 desvio-padrão",
       subtitle = "IC 95%; OR > 1 aumenta a chance de diabetes (escala log)",
       x = "Odds ratio", y = NULL, shape = NULL) +
  tema_tcc()
ggsave(file.path(DIR_FIGURAS, "04_odds_ratios.png"), g_or, width = 8, height = 4.8, dpi = 300)

# ---- Árvore de decisão -------------------------------------------------------
set.seed(SEMENTE)
arvore_final <- MODELOS$arvore$ajustar(completo)
# Para o desenho, a mesma árvore é reajustada com nomes de variáveis em português
dados_pt <- completo
names(dados_pt)[match(names(ROTULOS_VARS), names(dados_pt))] <- ROTULOS_VARS
levels(dados_pt$diabetes) <- c("Não", "Sim")
arv_pt <- rpart(diabetes ~ ., data = dados_pt, method = "class", model = TRUE,
                control = rpart.control(cp = min(arvore_final$cptable[, "CP"]), minsplit = 20, xval = 0))
stopifnot(nrow(arv_pt$frame) == nrow(arvore_final$frame))  # mesma árvore podada
arv_party <- as.party(arv_pt)
png(file.path(DIR_FIGURAS, "04_arvore_decisao.png"), width = 9, height = 6,
    units = "in", res = 300)
plot(arv_party, type = "simple", gp = gpar(fontsize = 13),
     inner_panel = node_inner(arv_party, pval = FALSE, id = FALSE),
     terminal_panel = node_terminal(arv_party, id = FALSE, width = 11, height = 4,
       fill = "#fbe3d9", FUN = function(n) {
         p <- n$distribution / sum(n$distribution)
         c(ifelse(which.max(p) == 2, "DIABETES", "Sem diabetes"),
           sprintf("risco: %.0f%%", 100 * p[2]),
           sprintf("n = %d", sum(n$distribution)))
       }),
     main = "Árvore de decisão final (CART podada, regra do 1-SE)")
invisible(dev.off())
sink(file.path(DIR_TABELAS, "04_regras_arvore.txt"))
cat("Árvore de decisão final (CART podada pela regra do 1-SE)\n\n")
print(arvore_final)
cat("\nRegras (caminho da raiz até cada folha):\n")
folhas <- as.integer(rownames(arvore_final$frame)[arvore_final$frame$var == "<leaf>"])
for (f in folhas) {
  caminho <- path.rpart(arvore_final, nodes = f, print.it = FALSE)[[1]][-1]
  fr <- arvore_final$frame[as.character(f), ]
  cat(sprintf("SE %s ENTÃO %s (n = %d, P(diabetes) = %.2f)\n",
              paste(caminho, collapse = " E "),
              ifelse(fr$yval == 2, "diabetes", "sem diabetes"),
              fr$n, fr$yval2[, 5]))
}
sink()
cat("\nÁrvore final com", sum(arvore_final$frame$var == "<leaf>"), "folhas;",
    "regras em resultados/tabelas/04_regras_arvore.txt\n")

# ---- Random forest e gradient boosting --------------------------------------
set.seed(SEMENTE)
rf_final <- MODELOS$rf$ajustar(completo)
set.seed(SEMENTE)
gbm_final <- MODELOS$gbm$ajustar(completo)

imp_rf  <- importance(rf_final, type = 1, scale = FALSE)[, 1]
imp_gbm <- summary(gbm_final, n.trees = gbm_final$melhor_n, plotit = FALSE)
imp_gbm <- setNames(imp_gbm$rel.inf, imp_gbm$var)
imp_arv <- arvore_final$variable.importance
imp_arv <- setNames(imp_arv[vars], vars); imp_arv[is.na(imp_arv)] <- 0
imp_lr  <- setNames(abs(summary(glm_final)$coefficients[vars, "z value"]), vars)

normaliza <- function(x) 100 * x / max(x)
importancia <- rbind(
  data.frame(modelo = "logistica", variavel = vars, bruto = imp_lr[vars],  relativa = normaliza(imp_lr[vars])),
  data.frame(modelo = "arvore",    variavel = vars, bruto = imp_arv[vars], relativa = normaliza(imp_arv[vars])),
  data.frame(modelo = "rf",        variavel = vars, bruto = imp_rf[vars],  relativa = normaliza(pmax(imp_rf[vars], 0))),
  data.frame(modelo = "gbm",       variavel = vars, bruto = imp_gbm[vars], relativa = normaliza(imp_gbm[vars]))
)
importancia$ranking <- ave(-importancia$relativa, importancia$modelo, FUN = rank)
rownames(importancia) <- NULL
write.csv(importancia, file.path(DIR_TABELAS, "04_importancia_variaveis.csv"), row.names = FALSE)

cat("\n== Ranking de importância das variáveis (1 = mais importante) ==\n")
rk <- reshape(importancia[, c("modelo", "variavel", "ranking")], idvar = "variavel",
              timevar = "modelo", direction = "wide")
names(rk) <- sub("ranking.", "", names(rk))
rk$variavel <- ROTULOS_VARS[rk$variavel]
print(rk[order(rk$logistica), ], row.names = FALSE)

ordem_vars <- names(sort(tapply(importancia$relativa, importancia$variavel, mean)))
importancia$var_f <- factor(importancia$variavel, levels = ordem_vars,
                            labels = ROTULOS_VARS[ordem_vars])
importancia$modelo_f <- factor(importancia$modelo, levels = names(ROTULOS_MODELOS),
                               labels = ROTULOS_MODELOS)
g_imp <- ggplot(importancia, aes(x = relativa, y = var_f, fill = modelo)) +
  geom_col(width = 0.65) +
  facet_wrap(~ modelo_f, nrow = 1) +
  scale_fill_manual(values = CORES_MODELOS, guide = "none") +
  scale_x_continuous(breaks = c(0, 50, 100)) +
  labs(title = "Importância relativa das variáveis em cada modelo",
       subtitle = "100 = variável mais importante do modelo · logística: |z|; árvore: redução de impureza; RF: permutação; GBM: influência relativa",
       x = "Importância relativa", y = NULL) +
  tema_tcc(12) + theme(panel.spacing = unit(1.2, "lines"),
                       plot.subtitle = element_text(size = 9))
ggsave(file.path(DIR_FIGURAS, "04_importancia_variaveis.png"), g_imp, width = 11, height = 4.5, dpi = 300)

saveRDS(list(logistica = glm_final, arvore = arvore_final, rf = rf_final, gbm = gbm_final,
             dados = completo),
        file.path(DIR_MODELOS, "modelos_finais.rds"))
