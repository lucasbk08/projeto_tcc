# =============================================================================
# 01_dados.R — carga do Pima Indians Diabetes Dataset e análise exploratória
# =============================================================================
# Saídas:
#   data/pima_bruto.csv
#   resultados/tabelas/01_descritiva.csv
#   resultados/tabelas/01_zeros_invalidos.csv
#   resultados/figuras/01_zeros_invalidos.png
#   resultados/figuras/01_distribuicoes.png
# =============================================================================

data(PimaIndiansDiabetes, package = "mlbench")
pima <- PimaIndiansDiabetes
write.csv(pima, file.path(DIR_DADOS, "pima_bruto.csv"), row.names = FALSE)

cat("\n== Dataset ==\n")
cat("Pacientes:", nrow(pima), "| Variáveis preditoras:", ncol(pima) - 1, "\n")
print(table(pima$diabetes))
cat(sprintf("Prevalência de diabetes: %.1f%%\n", 100 * mean(pima$diabetes == "pos")))

# ---- Zeros inválidos (dados ausentes disfarçados) ----------------------------
zeros <- data.frame(
  variavel   = VARS_ZERO_INVALIDO,
  rotulo     = ROTULOS_VARS[VARS_ZERO_INVALIDO],
  n_zeros    = sapply(VARS_ZERO_INVALIDO, function(v) sum(pima[[v]] == 0)),
  row.names  = NULL
)
zeros$pct_zeros <- round(100 * zeros$n_zeros / nrow(pima), 1)
zeros <- zeros[order(-zeros$n_zeros), ]
write.csv(zeros, file.path(DIR_TABELAS, "01_zeros_invalidos.csv"), row.names = FALSE)
cat("\n== Zeros inválidos por variável ==\n"); print(zeros, row.names = FALSE)

pima_na <- zeros_para_na(pima)
cat("Pacientes com pelo menos um ausente:", sum(!complete.cases(pima_na)),
    "| casos completos:", sum(complete.cases(pima_na)), "\n")

# ---- Estatística descritiva por grupo (zeros tratados como ausentes) --------
vars <- names(ROTULOS_VARS)
descr <- do.call(rbind, lapply(vars, function(v) {
  f <- function(x) sprintf("%.1f (%.1f)", mean(x, na.rm = TRUE), sd(x, na.rm = TRUE))
  data.frame(
    variavel      = ROTULOS_VARS[[v]],
    geral         = f(pima_na[[v]]),
    sem_diabetes  = f(pima_na[[v]][pima_na$diabetes == "neg"]),
    com_diabetes  = f(pima_na[[v]][pima_na$diabetes == "pos"]),
    ausentes      = sum(is.na(pima_na[[v]])),
    p_valor_wilcox = signif(wilcox.test(pima_na[[v]] ~ pima_na$diabetes)$p.value, 3)
  )
}))
write.csv(descr, file.path(DIR_TABELAS, "01_descritiva.csv"), row.names = FALSE)
cat("\n== Média (DP) por grupo ==\n"); print(descr, row.names = FALSE)

# ---- Figura: zeros inválidos -------------------------------------------------
zeros$rotulo <- factor(zeros$rotulo, levels = rev(zeros$rotulo))
g_zeros <- ggplot(zeros, aes(x = pct_zeros, y = rotulo)) +
  geom_col(fill = "#2a78d6", width = 0.6) +
  geom_text(aes(label = sprintf("%d (%.1f%%)", n_zeros, pct_zeros)),
            hjust = -0.1, colour = "#0b0b0b", size = 4) +
  scale_x_continuous(limits = c(0, 62), breaks = seq(0, 50, 10), expand = c(0, 0),
                     labels = function(x) paste0(x, "%")) +
  labs(title = "Zeros fisiologicamente impossíveis no Pima Dataset",
       subtitle = "Registrados como 0, mas na prática são valores ausentes (n = 768)",
       x = "Pacientes com valor zero", y = NULL) +
  tema_tcc()
ggsave(file.path(DIR_FIGURAS, "01_zeros_invalidos.png"), g_zeros,
       width = 8, height = 4, dpi = 300)

# ---- Figura: distribuições por grupo -----------------------------------------
longo <- do.call(rbind, lapply(vars, function(v) data.frame(
  variavel = ROTULOS_VARS[[v]], valor = pima_na[[v]],
  grupo = ifelse(pima_na$diabetes == "pos", "Com diabetes", "Sem diabetes"))))
longo <- longo[!is.na(longo$valor), ]
longo$variavel <- factor(longo$variavel, levels = ROTULOS_VARS)
g_dist <- ggplot(longo, aes(x = grupo, y = valor, fill = grupo)) +
  geom_boxplot(width = 0.55, outlier.size = 0.6, outlier.alpha = 0.5,
               colour = "#52514e", linewidth = 0.3) +
  facet_wrap(~ variavel, scales = "free_y", ncol = 4) +
  scale_fill_manual(values = c("Sem diabetes" = "#2a78d6", "Com diabetes" = "#eb6834")) +
  labs(title = "Distribuição das variáveis clínicas por diagnóstico",
       subtitle = "Zeros inválidos excluídos da visualização",
       x = NULL, y = NULL, fill = NULL) +
  tema_tcc(12) + theme(axis.text.x = element_blank())
ggsave(file.path(DIR_FIGURAS, "01_distribuicoes.png"), g_dist,
       width = 10, height = 5.5, dpi = 300)
