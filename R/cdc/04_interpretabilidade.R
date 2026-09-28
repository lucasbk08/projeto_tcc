# =============================================================================
# cdc/04_interpretabilidade.R — o que cada modelo aprendeu na base CDC
# =============================================================================
# Mesma lógica do Pima (R/04_interpretabilidade.R): os modelos finais são
# ajustados com todas as pessoas e só se inspeciona o raciocínio deles.
#   - Regressão logística: odds ratios com IC 95% (unidades em CDC_UNIDADE_OR)
#   - Árvore de decisão: regras em texto (+ desenho, se a árvore for pequena)
#   - Random forest: importância por permutação (ranger)
#   - Gradient boosting: influência relativa
# Os modelos não são salvos em .rds: com 253 mil pessoas a random forest
# ocuparia centenas de MB, e tudo pode ser recriado rodando o script.
# Saídas:
#   resultados/cdc/tabelas/04_odds_ratios.csv
#   resultados/cdc/tabelas/04_regras_arvore.txt
#   resultados/cdc/tabelas/04_importancia_variaveis.csv
#   resultados/cdc/figuras/04_odds_ratios.png
#   resultados/cdc/figuras/04_arvore_decisao.png   (só se tiver até 12 folhas)
#   resultados/cdc/figuras/04_importancia_variaveis.png
# =============================================================================

# ---- Regressão logística -----------------------------------------------------
# As variáveis contínuas/ordinais são divididas pela unidade escolhida, então
# o OR de IMC é "por +5 kg/m²", o de dias de saúde ruim é "por +10 dias" etc.
dados_or <- cdc
for (v in names(CDC_UNIDADE_OR)) dados_or[[v]] <- cdc[[v]] / CDC_UNIDADE_OR[[v]]
glm_cdc <- glm(diabetes ~ ., data = dados_or, family = binomial)
ic <- suppressMessages(confint.default(glm_cdc))
or_cdc <- data.frame(
  variavel   = CDC_VARS,
  rotulo     = ROTULOS_CDC[CDC_VARS],
  unidade    = ifelse(CDC_VARS %in% CDC_VARS_BINARIAS, "sim vs. não",
                      CDC_DESCR_UNIDADE[CDC_VARS]),
  odds_ratio = exp(coef(glm_cdc))[CDC_VARS],
  ic95_inf   = exp(ic[CDC_VARS, 1]),
  ic95_sup   = exp(ic[CDC_VARS, 2]),
  p_valor    = summary(glm_cdc)$coefficients[CDC_VARS, 4],
  row.names  = NULL
)
or_cdc <- or_cdc[order(-or_cdc$odds_ratio), ]
write.csv(or_cdc, file.path(DIR_CDC_TABELAS, "04_odds_ratios.csv"), row.names = FALSE)
cat("\n== Regressão logística (CDC): odds ratios ==\n")
print(data.frame(variavel = or_cdc$rotulo, unidade = or_cdc$unidade,
                 OR = sprintf("%.2f", or_cdc$odds_ratio),
                 IC95 = sprintf("[%.2f; %.2f]", or_cdc$ic95_inf, or_cdc$ic95_sup),
                 p = format.pval(or_cdc$p_valor, digits = 2, eps = 0.001)), row.names = FALSE)

or_cdc$rotulo_f <- factor(sprintf("%s  [%s]", or_cdc$rotulo, or_cdc$unidade),
                          levels = rev(sprintf("%s  [%s]", or_cdc$rotulo, or_cdc$unidade)))
or_cdc$efeito <- ifelse(or_cdc$ic95_inf > 1, "aumenta o risco",
                        ifelse(or_cdc$ic95_sup < 1, "reduz o risco", "IC inclui 1"))
g_or <- ggplot(or_cdc, aes(x = odds_ratio, y = rotulo_f, colour = efeito)) +
  geom_vline(xintercept = 1, linetype = "dashed", colour = "#b5b4ad") +
  geom_errorbar(aes(xmin = ic95_inf, xmax = ic95_sup), width = 0.3, linewidth = 0.6,
                orientation = "y") +
  geom_point(size = 2.6) +
  geom_text(aes(x = ic95_sup, label = num(odds_ratio, 2)), hjust = -0.3,
            size = 3.3, colour = "#0b0b0b") +
  scale_x_log10(expand = expansion(mult = c(0.05, 0.12))) +
  scale_colour_manual(values = c("aumenta o risco" = "#eb6834", "reduz o risco" = "#2a78d6",
                                 "IC inclui 1" = "#8a8983")) +
  labs(title = "Regressão logística (CDC): odds ratios",
       subtitle = "IC 95% · escala log · entre colchetes, a unidade do aumento",
       x = "Odds ratio", y = NULL, colour = NULL) +
  tema_tcc(12)
ggsave(file.path(DIR_CDC_FIGURAS, "04_odds_ratios.png"), g_or, width = 9.5, height = 7.5, dpi = 300)

# ---- Árvore de decisão ---------------------------------------------------------
set.seed(SEMENTE)
arvore_cdc <- MODELOS_CDC$arvore$ajustar(cdc)
n_folhas <- sum(arvore_cdc$frame$var == "<leaf>")

sink(file.path(DIR_CDC_TABELAS, "04_regras_arvore.txt"))
cat("Árvore de decisão final no CDC (CART podada pela regra do 1-SE)\n\n")
print(arvore_cdc)
cat("\nRegras (caminho da raiz até cada folha):\n")
folhas <- as.integer(rownames(arvore_cdc$frame)[arvore_cdc$frame$var == "<leaf>"])
for (f in folhas) {
  caminho <- path.rpart(arvore_cdc, nodes = f, print.it = FALSE)[[1]][-1]
  fr <- arvore_cdc$frame[as.character(f), ]
  cat(sprintf("SE %s ENTÃO %s (n = %d, P(diabetes) = %.2f)\n",
              paste(caminho, collapse = " E "),
              ifelse(fr$yval == 2, "pré-diabetes/diabetes", "sem diabetes"),
              fr$n, fr$yval2[, 5]))
}
sink()
cat("\nÁrvore final com", n_folhas, "folhas; regras em",
    file.path(DIR_CDC_TABELAS, "04_regras_arvore.txt"), "\n")

if (n_folhas <= 12) {
  # Reajusta a mesma árvore com nomes curtos em português, só para o desenho
  curtos <- sub(" \\(.*", "", ROTULOS_CDC)
  dados_pt <- cdc
  names(dados_pt)[match(CDC_VARS, names(dados_pt))] <- curtos[CDC_VARS]
  levels(dados_pt$diabetes) <- c("Não", "Sim")
  arv_pt <- rpart(diabetes ~ ., data = dados_pt, method = "class", model = TRUE,
                  control = rpart.control(cp = min(arvore_cdc$cptable[, "CP"]),
                                          minsplit = 20, xval = 0))
  stopifnot(nrow(arv_pt$frame) == nrow(arvore_cdc$frame))
  arv_party <- as.party(arv_pt)
  png(file.path(DIR_CDC_FIGURAS, "04_arvore_decisao.png"), width = 12, height = 7,
      units = "in", res = 300)
  plot(arv_party, type = "simple", gp = gpar(fontsize = 11),
       inner_panel = node_inner(arv_party, pval = FALSE, id = FALSE),
       terminal_panel = node_terminal(arv_party, id = FALSE, width = 11, height = 4,
         fill = "#fbe3d9", FUN = function(n) {
           p <- n$distribution / sum(n$distribution)
           c(ifelse(which.max(p) == 2, "DIABETES", "Sem diabetes"),
             sprintf("risco: %.0f%%", 100 * p[2]),
             sprintf("n = %s", fmt_n(sum(n$distribution))))
         }),
       main = "Árvore de decisão final no CDC (CART podada, regra do 1-SE)")
  invisible(dev.off())
} else {
  cat("Árvore grande demais para um desenho legível; veja as regras no TXT.\n")
}

# ---- Random forest e gradient boosting ------------------------------------------
set.seed(SEMENTE)
rf_cdc <- ranger(diabetes ~ ., data = cdc, num.trees = 500, probability = TRUE,
                 importance = "permutation", seed = SEMENTE, verbose = FALSE)
imp_rf <- ranger::importance(rf_cdc)
rm(rf_cdc); invisible(gc())

set.seed(SEMENTE)
gbm_cdc <- MODELOS_CDC$gbm$ajustar(cdc)
imp_gbm <- summary(gbm_cdc, n.trees = gbm_cdc$melhor_n, plotit = FALSE)
imp_gbm <- setNames(imp_gbm$rel.inf, imp_gbm$var)
cat(sprintf("Gradient boosting final: %d árvores (de 1500) escolhidas pelo erro OOB\n",
            gbm_cdc$melhor_n))

imp_arv <- arvore_cdc$variable.importance
imp_arv <- setNames(imp_arv[CDC_VARS], CDC_VARS); imp_arv[is.na(imp_arv)] <- 0
imp_lr  <- setNames(abs(summary(glm_cdc)$coefficients[CDC_VARS, "z value"]), CDC_VARS)

normaliza <- function(x) 100 * x / max(x)
imp_cdc <- rbind(
  data.frame(modelo = "logistica", variavel = CDC_VARS, bruto = imp_lr[CDC_VARS],  relativa = normaliza(imp_lr[CDC_VARS])),
  data.frame(modelo = "arvore",    variavel = CDC_VARS, bruto = imp_arv[CDC_VARS], relativa = normaliza(imp_arv[CDC_VARS])),
  data.frame(modelo = "rf",        variavel = CDC_VARS, bruto = imp_rf[CDC_VARS],  relativa = normaliza(pmax(imp_rf[CDC_VARS], 0))),
  data.frame(modelo = "gbm",       variavel = CDC_VARS, bruto = imp_gbm[CDC_VARS], relativa = normaliza(imp_gbm[CDC_VARS]))
)
imp_cdc$ranking <- ave(-imp_cdc$relativa, imp_cdc$modelo, FUN = rank)
rownames(imp_cdc) <- NULL
write.csv(imp_cdc, file.path(DIR_CDC_TABELAS, "04_importancia_variaveis.csv"), row.names = FALSE)

cat("\n== Ranking de importância das variáveis no CDC (1 = mais importante) ==\n")
rk <- reshape(imp_cdc[, c("modelo", "variavel", "ranking")], idvar = "variavel",
              timevar = "modelo", direction = "wide")
names(rk) <- sub("ranking.", "", names(rk), fixed = TRUE)
rk$variavel <- ROTULOS_CDC[rk$variavel]
print(rk[order(rk$logistica), ], row.names = FALSE)

ordem_vars <- names(sort(tapply(imp_cdc$relativa, imp_cdc$variavel, mean)))
imp_cdc$var_f <- factor(imp_cdc$variavel, levels = ordem_vars, labels = ROTULOS_CDC[ordem_vars])
imp_cdc$modelo_f <- factor(imp_cdc$modelo, levels = names(ROTULOS_MODELOS), labels = ROTULOS_MODELOS)
g_imp <- ggplot(imp_cdc, aes(x = relativa, y = var_f, fill = modelo)) +
  geom_col(width = 0.65) +
  facet_wrap(~ modelo_f, nrow = 1) +
  scale_fill_manual(values = CORES_MODELOS, guide = "none") +
  scale_x_continuous(breaks = c(0, 50, 100)) +
  labs(title = "Importância relativa das variáveis em cada modelo (CDC)",
       subtitle = "100 = variável mais importante do modelo · logística: |z|; árvore: redução de impureza; RF: permutação; GBM: influência relativa",
       x = "Importância relativa", y = NULL) +
  tema_tcc(12) + theme(panel.spacing = unit(1.2, "lines"),
                       plot.subtitle = element_text(size = 9))
ggsave(file.path(DIR_CDC_FIGURAS, "04_importancia_variaveis.png"), g_imp, width = 12, height = 7, dpi = 300)
