# =============================================================================
# 04_interpretabilidade.R — o que cada modelo "aprendeu"
# =============================================================================
# Os modelos finais são ajustados com TODOS os 768 pacientes (estratégia
# principal de ausentes). Aqui não se mede desempenho (isso é papel da CV),
# só se inspeciona o raciocínio de cada modelo.
#   - Regressão logística: odds ratios por 1 desvio-padrão, IC 95% por imputação múltipla
#   - Árvore de decisão: a própria árvore + regras em texto
#   - Random forest: importância por permutação (queda de acurácia)
#   - Gradient boosting: influência relativa
# Saídas:
#   resultados/tabelas/04_odds_ratios.csv
#   resultados/tabelas/04_regras_arvore.txt
#   resultados/tabelas/04_importancia_variaveis.csv
#   resultados/tabelas/04_criterios_interpretabilidade.csv
#   resultados/figuras/04_odds_ratios.png
#   resultados/figuras/04_arvore_decisao.png
#   resultados/figuras/04_importancia_variaveis.png
#   resultados/figuras/04_equilibrio.png
#   resultados/modelos/modelos_finais.rds
# =============================================================================

set.seed(SEMENTE)
completo <- ESTRATEGIAS[[ESTRATEGIA_PRINCIPAL]](pima, pima[0, ])$treino

# ---- Regressão logística: odds ratios com imputação múltipla -----------------
# Imputar uma vez só e tratar os valores estimados como se tivessem sido
# medidos deixa os ICs estreitos demais. Aqui se usa imputação múltipla:
# 20 bases imputadas, uma regressão em cada, e os resultados combinados pelas
# regras de Rubin (mice::pool), que somam a incerteza da imputação ao IC.
# Diferente da CV (predição, em que o diagnóstico do teste é desconhecido),
# aqui o objetivo é ESTIMAR associações, e a resposta entra no modelo de
# imputação; sem ela, os OR ficariam puxados para 1 (Moons et al., 2006).
# Unidade: +1 desvio-padrão observado, para os OR serem comparáveis entre si.
vars <- names(ROTULOS_VARS)
# Limites do IC no resultado de pool(): colunas "2.5 %" e "97.5 %" (ou "2,5 %"
# com vírgula decimal), localizadas pela posição para não depender do separador
ic_inf <- function(s) s[[grep("%$", names(s))[1]]]
ic_sup <- function(s) s[[grep("%$", names(s))[2]]]
pima_na <- zeros_para_na(pima)
dp_obs <- sapply(pima_na[vars], sd, na.rm = TRUE)
imp_or <- mice(pima_na, m = 20, maxit = 10, method = "pmm", printFlag = FALSE,
               seed = SEMENTE)
ajustes_or <- lapply(complete(imp_or, "all"), function(d) {
  d[vars] <- sweep(d[vars], 2, dp_obs, "/")
  glm(diabetes ~ ., data = d, family = binomial)
})
combinado <- summary(pool(as.mira(ajustes_or)), conf.int = TRUE)
combinado <- combinado[match(vars, combinado$term), ]
or <- data.frame(
  variavel    = vars,
  rotulo      = ROTULOS_VARS[vars],
  dp_original = dp_obs[vars],
  odds_ratio  = exp(combinado$estimate),
  ic95_inf    = exp(ic_inf(combinado)),
  ic95_sup    = exp(ic_sup(combinado)),
  p_valor     = combinado$p.value,
  row.names   = NULL
)

# Sensibilidade: o que muda de (A) imputação única sem a resposta (a usada na
# CV) para (C) imputação múltipla com a resposta? São DUAS mudanças, separadas
# por um passo intermediário (B) = múltipla SEM a resposta:
#   A -> B: efeito de imputar 20 vezes (o IC ganha a incerteza da imputação)
#   B -> C: efeito de incluir a resposta (os OR "desencolhem", afastando-se de 1)
unica <- completo; unica[vars] <- sweep(unica[vars], 2, dp_obs, "/")
fit_a <- glm(diabetes ~ ., data = unica, family = binomial)
imp_sem_resp <- mice(pima_na[vars], m = 20, maxit = 10, method = "pmm",
                     printFlag = FALSE, seed = SEMENTE)
comb_b <- summary(pool(as.mira(lapply(complete(imp_sem_resp, "all"), function(d) {
  d[vars] <- sweep(d[vars], 2, dp_obs, "/"); d$diabetes <- pima$diabetes
  glm(diabetes ~ ., data = d, family = binomial)
}))), conf.int = TRUE)
comb_b <- comb_b[match(vars, comb_b$term), ]
ic_a <- suppressMessages(confint.default(fit_a))[vars, ]
sens_imp <- data.frame(
  cenario = c("A: única, sem resposta", "B: múltipla (m = 20), sem resposta",
              "C: múltipla (m = 20), com resposta [usado]"),
  or_glicose = exp(c(coef(fit_a)["glucose"], comb_b$estimate[vars == "glucose"],
                     combinado$estimate[vars == "glucose"])),
  or_imc     = exp(c(coef(fit_a)["mass"], comb_b$estimate[vars == "mass"],
                     combinado$estimate[vars == "mass"])),
  largura_ic_media = c(mean(ic_a[, 2] - ic_a[, 1]),
                       mean(ic_sup(comb_b) - ic_inf(comb_b)),
                       mean(ic_sup(combinado) - ic_inf(combinado))))
sens_imp$largura_vs_A <- sens_imp$largura_ic_media / sens_imp$largura_ic_media[1]
write.csv(sens_imp, file.path(DIR_TABELAS, "04_or_sensibilidade_imputacao.csv"), row.names = FALSE)
cat("\n== Sensibilidade dos odds ratios à imputação (largura do IC em escala log) ==\n")
print(data.frame(cenario = sens_imp$cenario,
                 `OR glicose` = num(sens_imp$or_glicose, 2),
                 `OR IMC` = num(sens_imp$or_imc, 2),
                 `IC vs. A` = sprintf("%+.0f%%", 100 * (sens_imp$largura_vs_A - 1)),
                 check.names = FALSE), row.names = FALSE)

# Modelo final para uso preditivo (unidades originais, base imputada única)
glm_final <- glm(diabetes ~ ., data = completo, family = binomial)
or <- or[order(-or$odds_ratio), ]
write.csv(or, file.path(DIR_TABELAS, "04_odds_ratios.csv"), row.names = FALSE)
cat("\n== Regressão logística: odds ratio por +1 DP (imputação múltipla, m = 20) ==\n")
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
  geom_errorbar(aes(xmin = ic95_inf, xmax = ic95_sup), width = 0.25, orientation = "y",
                colour = "#2a78d6", linewidth = 0.6) +
  geom_point(aes(shape = signif), size = 3, colour = "#2a78d6", fill = "white", stroke = 1.2) +
  geom_text(aes(x = ic95_sup, label = num(odds_ratio, 2)), hjust = -0.3,
            size = 3.8, colour = "#0b0b0b") +
  scale_x_log10(expand = expansion(mult = c(0.05, 0.12))) +
  scale_shape_manual(values = c("p < 0,05" = 16, "p ≥ 0,05" = 21)) +
  labs(title = "Regressão logística: odds ratio por +1 desvio-padrão",
       subtitle = "IC 95% por imputação múltipla (m = 20) · OR > 1 aumenta a chance · escala log",
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
imp_lr  <- setNames(abs(combinado$statistic), vars)   # |t| combinado das 20 imputações

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
       subtitle = "100 = variável mais importante do modelo · logística: |t| combinado; árvore: redução de impureza; RF: permutação; GBM: influência relativa",
       x = "Importância relativa", y = NULL) +
  tema_tcc(12) + theme(panel.spacing = unit(1.2, "lines"),
                       plot.subtitle = element_text(size = 9))
ggsave(file.path(DIR_FIGURAS, "04_importancia_variaveis.png"), g_imp, width = 11, height = 4.5, dpi = 300)

# ---- Critérios de interpretabilidade (objetivo central: o "equilíbrio") -----
# O desempenho tem número (AUC); aqui a interpretabilidade também ganha:
#   tamanho do modelo  = quantos elementos alguém precisaria ler para entender
#                        o modelo inteiro (coeficientes ou nós das árvores)
#   variáveis usadas   = quantas variáveis o modelo de fato consulta
# e três critérios práticos, iguais para todos os modelos:
#   cálculo à mão      = um profissional consegue obter o risco sem computador?
#   direção do efeito  = dá para saber se a variável AUMENTA ou REDUZ o risco?
#   explicação individual = dá para dizer POR QUE este paciente recebeu este risco?
nos_arvore <- nrow(arvore_final$frame)
nos_rf     <- sum(rf_final$forest$ndbigtree)
divisoes_gbm <- sum(vapply(seq_len(gbm_final$melhor_n), function(i)
  sum(pretty.gbm.tree(gbm_final, i.tree = i)$SplitVar != -1), numeric(1)))
nos_gbm    <- 2 * divisoes_gbm + gbm_final$melhor_n   # divisões + folhas
vars_arvore <- setdiff(unique(as.character(arvore_final$frame$var)), "<leaf>")

resumo_auc <- read.csv(file.path(DIR_TABELAS, "03_resumo_desempenho.csv"))
resumo_auc <- resumo_auc[resumo_auc$estrategia == ESTRATEGIA_PRINCIPAL, ]
auc_de <- setNames(resumo_auc$auc_media, resumo_auc$modelo)
dp_de  <- setNames(resumo_auc$auc_dp, resumo_auc$modelo)

criterios <- data.frame(
  modelo = names(ROTULOS_MODELOS),
  auc_media = auc_de[names(ROTULOS_MODELOS)],
  auc_dp    = dp_de[names(ROTULOS_MODELOS)],
  perda_vs_melhor = max(auc_de) - auc_de[names(ROTULOS_MODELOS)],
  tamanho_modelo = c(length(coef(glm_final)), nos_arvore, nos_rf, nos_gbm),
  unidade_tamanho = c("coeficientes",
                      sprintf("nós (%d perguntas, %d folhas)",
                              sum(arvore_final$frame$var != "<leaf>"),
                              sum(arvore_final$frame$var == "<leaf>")),
                      sprintf("nós em %d árvores", rf_final$ntree),
                      sprintf("nós em %d árvores", gbm_final$melhor_n)),
  variaveis_usadas = c(length(vars), length(vars_arvore),
                       # RF: varUsed conta as divisões; a importância por permutação
                       # pode sair negativa por acaso mesmo numa variável usada
                       sum(varUsed(rf_final) > 0), sum(imp_gbm[vars] > 0)),
  calculo_a_mao = c("Sim: soma de 9 termos na fórmula logística",
                    sprintf("Sim: até %d perguntas sim/não",
                            max(floor(log2(as.integer(rownames(arvore_final$frame)))))),
                    "Não", "Não"),
  direcao_do_efeito = c("Sim, com magnitude e IC 95% (odds ratio)",
                        "Parcial: só nas variáveis usadas, por limiar",
                        "Não: a importância não tem sinal",
                        "Não: a importância não tem sinal"),
  explicacao_individual = c("Sim: contribuição de cada variável",
                            "Sim: o caminho até a folha",
                            "Não sem ferramenta pós-hoc (ex.: SHAP)",
                            "Não sem ferramenta pós-hoc (ex.: SHAP)"),
  row.names = NULL
)
write.csv(criterios, file.path(DIR_TABELAS, "04_criterios_interpretabilidade.csv"), row.names = FALSE)
cat("\n== Desempenho x interpretabilidade (objetivo central) ==\n")
print(data.frame(modelo = ROTULOS_MODELOS[criterios$modelo],
                 AUC = sprintf("%.3f", criterios$auc_media),
                 perda = sprintf("%.3f", criterios$perda_vs_melhor),
                 tamanho = format(criterios$tamanho_modelo, big.mark = " "),
                 vars = criterios$variaveis_usadas,
                 `à mão` = sub(":.*", "", criterios$calculo_a_mao),
                 `direção` = sub(":.*|,.*", "", criterios$direcao_do_efeito),
                 `explica paciente` = ifelse(startsWith(criterios$explicacao_individual, "Sim"), "Sim", "Não"),
                 check.names = FALSE), row.names = FALSE)

criterios$rotulo <- sprintf("%s\n%s %s", ROTULOS_MODELOS[criterios$modelo],
                            format(criterios$tamanho_modelo, big.mark = ".", decimal.mark = ","),
                            ifelse(criterios$modelo == "logistica", "coeficientes", "nós"))
g_eq <- ggplot(criterios, aes(x = tamanho_modelo, y = auc_media, colour = modelo)) +
  annotate("rect", xmin = 1, xmax = 1e7, ymin = max(criterios$auc_media) - DELTA_AUC_RELEVANTE,
           ymax = max(criterios$auc_media), fill = "#e8f2fc", alpha = 0.7) +
  annotate("text", x = 150, y = max(criterios$auc_media) - DELTA_AUC_RELEVANTE + 0.006,
           label = "faixa de perda ≤ 0,05 (não relevante)", colour = "#2a78d6", size = 3.4) +
  geom_errorbar(aes(ymin = auc_media - auc_dp, ymax = auc_media + auc_dp), width = 0.08,
                linewidth = 0.6) +
  geom_point(size = 3.5) +
  geom_text(aes(label = rotulo), nudge_x = 0.12, hjust = 0, size = 3.4, lineheight = 0.9,
            colour = "#0b0b0b") +
  scale_x_log10(breaks = 10^(0:5), labels = c("1", "10", "100", "1.000", "10.000", "100.000")) +
  coord_cartesian(xlim = c(3, 6e5)) +
  scale_colour_manual(values = CORES_MODELOS, guide = "none") +
  labs(title = "Desempenho × tamanho do modelo",
       subtitle = "AUC-ROC média ± 1 DP (CV 10×5, MICE) · eixo x: quantos elementos seria preciso ler para entender o modelo (escala log)",
       x = "Tamanho do modelo (coeficientes ou nós de árvore)", y = "AUC-ROC") +
  tema_tcc() + theme(plot.subtitle = element_text(size = 9.5))
ggsave(file.path(DIR_FIGURAS, "04_equilibrio.png"), g_eq, width = 9, height = 5, dpi = 300)

saveRDS(list(logistica = glm_final, arvore = arvore_final, rf = rf_final, gbm = gbm_final,
             dados = completo),
        file.path(DIR_MODELOS, "modelos_finais.rds"))
