# Rascunho — Metodologia e Resultados (Projeto de Pesquisa Completo, N2)

> Texto-base gerado a partir dos scripts em `R/`. Os números vêm de `resultados_log.txt`
> e `resultados/tabelas/`. Revisar a redação com o grupo e ajustar ao modelo ABNT da disciplina.

## Metodologia

### Dados

Foi utilizado o Pima Indians Diabetes Dataset (SMITH et al., 1988), disponível no pacote `mlbench`
da linguagem R. O conjunto reúne 768 pacientes do sexo feminino, com pelo menos 21 anos e de origem
Pima, descritas por oito variáveis clínicas: número de gestações, glicose plasmática, pressão
diastólica, espessura da dobra cutânea do tríceps, insulina sérica, índice de massa corporal (IMC),
função de histórico familiar de diabetes (DPF) e idade. A variável resposta indica a presença de
diabetes, observada em 268 pacientes (34,9%).

### Tratamento dos valores ausentes

Cinco variáveis apresentam valores iguais a zero fisiologicamente impossíveis: insulina (374
pacientes; 48,7%), dobra cutânea (227; 29,6%), pressão diastólica (35; 4,6%), IMC (11; 1,4%) e
glicose (5; 0,7%). Esses zeros foram interpretados como dados ausentes. Ao todo, 376 pacientes
possuem pelo menos um valor ausente, restando 392 casos completos.

Para atender ao quarto objetivo específico, quatro estratégias foram comparadas: (a) manter os zeros,
como linha de base; (b) remover os pacientes com algum valor ausente; (c) imputar pela mediana; e
(d) imputação múltipla por equações encadeadas (MICE), com *predictive mean matching*
(VAN BUUREN; GROOTHUIS-OUDSHOORN, 2011). A MICE foi definida, antes da análise, como a estratégia
principal, por preservar os 768 pacientes e respeitar a distribuição observada das variáveis.
Para evitar vazamento de informação, a mediana e o modelo de imputação foram estimados apenas com
os dados de treino de cada partição e depois aplicados aos dados de teste; a variável resposta não
foi usada na imputação.

### Modelos

Foram implementados quatro classificadores de complexidade crescente:

1. **Regressão logística**, com todas as variáveis como preditoras;
2. **Árvore de decisão** CART (BREIMAN et al., 1984), podada pela regra de um erro-padrão sobre
   o erro de validação cruzada interna;
3. **Random forest** (BREIMAN, 2001), com 500 árvores e parâmetros padrão do pacote `randomForest`;
4. **Gradient boosting** (FRIEDMAN, 2001), pacote `gbm`, com profundidade de interação 3, taxa de
   aprendizado 0,01, subamostragem de 80% e número de árvores escolhido pelo erro *out-of-bag*.

Os hiperparâmetros foram fixados previamente, sem busca em grade, para que a comparação refletisse
configurações usuais de cada método.

### Validação e métricas

O desempenho foi estimado por validação cruzada estratificada com 10 partições, repetida 5 vezes
(50 avaliações por modelo). As mesmas partições foram usadas para todos os modelos e estratégias, o
que permite comparações pareadas. A métrica principal foi a área sob a curva ROC (AUC-ROC); como
métricas secundárias, foram calculadas acurácia, sensibilidade, especificidade, precisão, F1 e escore
de Brier, com limiar de classificação de 0,5.

As diferenças de AUC entre modelos foram avaliadas com o teste t corrigido para validação cruzada
repetida (NADEAU; BENGIO, 2003), que considera a dependência entre partições cujos conjuntos de treino
se sobrepõem. Conforme o terceiro objetivo específico, uma perda de AUC maior que 0,05 ao substituir o
melhor modelo por um modelo interpretável foi considerada clinicamente relevante.

A interpretabilidade foi analisada nos modelos ajustados com todos os pacientes: odds ratios
padronizados (por aumento de um desvio-padrão) na regressão logística, as regras da árvore de decisão,
a importância por permutação no random forest e a influência relativa no gradient boosting.

Todo o experimento foi implementado em R (R CORE TEAM, 2024), com semente fixa (2026), e pode ser
reproduzido pelo script `run_all.R`.

## Resultados

### Desempenho preditivo

Com a estratégia MICE, o gradient boosting obteve a maior AUC média (0,838 ± 0,045), seguido de perto
pela regressão logística (0,836 ± 0,042) e pelo random forest (0,829 ± 0,048). A árvore de decisão
teve desempenho claramente inferior (0,731 ± 0,063). A regressão logística apresentou a maior acurácia
(0,767) e o menor escore de Brier (0,157), o que indica probabilidades mais bem calibradas. Em todos
os modelos, a especificidade (0,84–0,88) foi bem maior que a sensibilidade (0,53–0,59), reflexo do
limiar de 0,5 e do desbalanceamento das classes.

### Ensembles versus regressão logística (objetivo 2)

Nenhum método ensemble superou a regressão logística de forma estatisticamente significativa: a
diferença de AUC foi de +0,002 para o gradient boosting (IC 95%: −0,015 a 0,019; p = 0,85) e de
−0,007 para o random forest (IC 95%: −0,028 a 0,013; p = 0,46). O mesmo padrão se repetiu nas quatro
estratégias de tratamento de ausentes.

### Custo da interpretabilidade (objetivo 3)

Substituir o gradient boosting pela regressão logística custa 0,002 de AUC (IC 95%: −0,015 a 0,019).
Como o limite superior do intervalo fica abaixo de 0,05, a perda **não** é clinicamente relevante.
Já a troca pela árvore de decisão custa 0,107 de AUC (IC 95%: 0,064 a 0,150), uma perda relevante
pelo critério adotado.

### Efeito do tratamento dos ausentes (objetivo 4)

Tratar os zeros como ausentes, por mediana ou MICE, aumentou discretamente a AUC em relação a mantê-los
(de +0,000 a +0,017), sem diferença pareada significativa (p ≥ 0,22). A árvore de decisão foi o modelo
mais sensível ao tratamento. A remoção de casos incompletos produziu AUCs nominalmente maiores
(0,845–0,855 nos três melhores modelos), mas foi avaliada em uma amostra diferente (392 pacientes) e
com maior variabilidade entre partições, então esses valores não são diretamente comparáveis e
indicam menor estabilidade.

### Interpretabilidade

Glicose e IMC foram as duas variáveis mais importantes nos quatro modelos. Na regressão logística,
um aumento de um desvio-padrão na glicose (≈ 30 mg/dL) multiplicou a chance de diabetes por 3,05
(IC 95%: 2,38–3,90); no IMC (≈ 6,9 kg/m²), por 1,78 (1,37–2,32). Gestações (OR = 1,51) e histórico
familiar (OR = 1,33) também foram significativos. Insulina, dobra cutânea, pressão e idade não tiveram
efeito significativo depois de ajustadas pelas demais variáveis. A árvore podada ficou com apenas três
folhas: pacientes com glicose ≥ 127,5 mg/dL e IMC ≥ 29,95 kg/m² têm 73% de chance de diabetes, contra
19% entre os que têm glicose < 127,5 mg/dL.

### Síntese

A regressão logística oferece o melhor equilíbrio entre desempenho e interpretabilidade no Pima
Dataset: o desempenho é equivalente ao do melhor ensemble, as probabilidades são as mais bem calibradas
e os coeficientes têm leitura clínica direta. O resultado está de acordo com Rudin (2019), segundo quem
modelos interpretáveis podem ter desempenho comparável ao de caixas-pretas em dados tabulares
estruturados.

## Referências a acrescentar

BREIMAN, L. Random forests. **Machine Learning**, v. 45, n. 1, p. 5-32, 2001.

BREIMAN, L.; FRIEDMAN, J. H.; OLSHEN, R. A.; STONE, C. J. **Classification and regression trees**.
Belmont: Wadsworth, 1984.

FRIEDMAN, J. H. Greedy function approximation: a gradient boosting machine. **The Annals of
Statistics**, v. 29, n. 5, p. 1189-1232, 2001.

NADEAU, C.; BENGIO, Y. Inference for the generalization error. **Machine Learning**, v. 52, n. 3,
p. 239-281, 2003.

R CORE TEAM. **R: a language and environment for statistical computing**. Vienna: R Foundation for
Statistical Computing, 2024.

VAN BUUREN, S.; GROOTHUIS-OUDSHOORN, K. mice: multivariate imputation by chained equations in R.
**Journal of Statistical Software**, v. 45, n. 3, p. 1-67, 2011.
