# =============================================================================
# cdc/01_dados.R — carga do CDC Diabetes Health Indicators e análise exploratória
# =============================================================================
# Saídas:
#   data/cdc_diabetes_health_indicators.csv   (baixado do UCI na 1ª execução)
#   resultados/cdc/tabelas/01_descritiva.csv
#   resultados/cdc/figuras/01_prevalencia_por_fator.png
# =============================================================================

# ---- Download (só na 1ª vez; depois usa a cópia versionada em data/) --------
# A cópia local protege o projeto caso o UCI retire a base, como fez com o Pima.
if (!file.exists(CDC_ARQUIVO)) {
  cat("Baixando o dataset do UCI...\n")
  download.file(CDC_URL, CDC_ARQUIVO, mode = "wb", quiet = TRUE)
}
cdc <- read.csv(CDC_ARQUIVO)
stopifnot(nrow(cdc) == 253680, all(c("Diabetes_binary", CDC_VARS) %in% names(cdc)),
          !anyNA(cdc))

# Mesmo formato do Pima: resposta "diabetes" com níveis neg/pos, sem o ID
cdc$diabetes <- factor(ifelse(cdc$Diabetes_binary == 1, "pos", "neg"), levels = c("neg", "pos"))
cdc <- cdc[, c(CDC_VARS, "diabetes")]

if (!is.na(CDC_AMOSTRA)) {
  # Amostra estratificada para testar o código rapidamente (--amostra=N)
  set.seed(SEMENTE)
  idx <- unlist(lapply(split(seq_len(nrow(cdc)), cdc$diabetes), function(i)
    sample(i, round(CDC_AMOSTRA * (length(i) / nrow(cdc))))))
  cdc <- cdc[sort(idx), ]
  cat(sprintf("*** MODO AMOSTRA: %d pessoas (resultados em %s) ***\n", nrow(cdc), DIR_CDC))
}
rownames(cdc) <- NULL

cat("\n== Dataset ==\n")
cat("Pessoas:", nrow(cdc), "| Variáveis preditoras:", length(CDC_VARS), "\n")
print(table(cdc$diabetes))
cat(sprintf("Prevalência de pré-diabetes ou diabetes: %.1f%%\n", 100 * mean(cdc$diabetes == "pos")))
cat("Valores ausentes:", sum(is.na(cdc)),
    "| linhas repetidas (mesmo perfil de respostas):", sum(duplicated(cdc)), "\n")

# ---- Estatística descritiva por grupo ----------------------------------------
# Com n = 253 mil, qualquer diferença vira p < 0,001, então o p-valor não
# informa nada. Em vez dele, usa-se a diferença padronizada (SMD): diferença
# de médias em unidades de desvio-padrão; |SMD| > 0,1 costuma ser considerada
# relevante, > 0,5 grande.
com <- cdc$diabetes == "pos"
descr <- do.call(rbind, lapply(CDC_VARS, function(v) {
  x <- cdc[[v]]
  smd <- (mean(x[com]) - mean(x[!com])) / sqrt((var(x[com]) + var(x[!com])) / 2)
  f <- if (v %in% CDC_VARS_BINARIAS) {
    function(z) sprintf("%.1f%%", 100 * mean(z))
  } else {
    function(z) sprintf("%.1f (%.1f)", mean(z), sd(z))
  }
  data.frame(variavel = v, rotulo = ROTULOS_CDC[[v]],
             tipo = if (v %in% CDC_VARS_BINARIAS) "% sim" else "média (DP)",
             geral = f(x), sem_diabetes = f(x[!com]), com_diabetes = f(x[com]),
             smd = round(smd, 3))
}))
descr <- descr[order(-abs(descr$smd)), ]
write.csv(descr, file.path(DIR_CDC_TABELAS, "01_descritiva.csv"), row.names = FALSE)
cat("\n== Por grupo (ordenado pela diferença padronizada) ==\n")
print(descr[, c("rotulo", "tipo", "sem_diabetes", "com_diabetes", "smd")], row.names = FALSE)

# ---- Figura: prevalência de diabetes com e sem cada fator binário ------------
prev <- do.call(rbind, lapply(setdiff(CDC_VARS_BINARIAS, "Sex"), function(v) data.frame(
  rotulo = ROTULOS_CDC[[v]],
  grupo  = c("Não", "Sim"),
  prev   = 100 * c(mean(com[cdc[[v]] == 0]), mean(com[cdc[[v]] == 1])))))
ordem <- prev[prev$grupo == "Sim", ]
prev$rotulo <- factor(prev$rotulo, levels = ordem$rotulo[order(ordem$prev)])
g_prev <- ggplot(prev, aes(x = prev, y = rotulo)) +
  geom_vline(xintercept = 100 * mean(com), linetype = "dashed", colour = "#b5b4ad") +
  geom_line(aes(group = rotulo), colour = "#b5b4ad", linewidth = 0.8) +
  geom_point(aes(colour = grupo), size = 3) +
  scale_colour_manual(values = c("Não" = "#2a78d6", "Sim" = "#eb6834")) +
  scale_x_continuous(labels = function(x) paste0(x, "%")) +
  labs(title = "Prevalência de pré-diabetes/diabetes por fator (CDC)",
       subtitle = sprintf("Linha tracejada = prevalência geral (%s%%) · n = %s",
                          num(100 * mean(com), 1), fmt_n(nrow(cdc))),
       x = "Pessoas com pré-diabetes ou diabetes", y = NULL,
       colour = "Tem o fator?") +
  tema_tcc()
ggsave(file.path(DIR_CDC_FIGURAS, "01_prevalencia_por_fator.png"), g_prev,
       width = 8.5, height = 5.5, dpi = 300)
