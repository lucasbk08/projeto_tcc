# Rascunho — Metodologia e Resultados (Projeto de Pesquisa Completo, N2)

> Texto-base gerado a partir dos scripts em `R/`. Os números vêm de `resultados_log.txt`
> e `resultados/tabelas/`. Revisar a redação com o grupo e ajustar ao modelo ABNT da disciplina.

## Metodologia

### Dados

Foi utilizado o Pima Indians Diabetes Dataset (SMITH et al., 1988), na versão distribuída pelo pacote
`mlbench` da linguagem R (versão 2.1-3.1). O dataset foi posteriormente retirado do UCI Machine Learning
Repository e do próprio `mlbench` (a partir da versão 2.1-10); por isso, uma cópia é mantida no
repositório do projeto. O conjunto reúne 768 pacientes do sexo feminino, com pelo menos 21 anos e de origem
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
os dados de treino de cada partição e depois aplicados aos dados de teste; na validação cruzada, a
variável resposta não foi usada na imputação.

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

Como complemento ao limiar de 0,5, avaliou-se um ponto de operação de triagem: a maior especificidade
obtida por cada modelo mantendo a sensibilidade em pelo menos 80%, calculada na curva ROC de cada
partição. A calibração foi avaliada pelo intercepto e pela inclinação de calibração nas predições
fora-da-partição (valores ideais 0 e 1; VAN CALSTER et al., 2019), além de curvas de calibração por decis.

A interpretabilidade foi analisada nos modelos ajustados com todos os pacientes: odds ratios
padronizados (por aumento de um desvio-padrão) na regressão logística, as regras da árvore de decisão,
a importância por permutação no random forest e a influência relativa no gradient boosting. Os
intervalos de confiança dos odds ratios foram obtidos por imputação múltipla (20 conjuntos imputados,
combinados pelas regras de Rubin; RUBIN, 1987). Diferentemente da validação cruzada, cujo objetivo é
a predição, aqui o objetivo é estimar associações, e a variável resposta foi incluída no modelo de
imputação, como recomendado nesse contexto (MOONS et al., 2006).

Para responder ao objetivo central, a interpretabilidade também foi descrita por critérios explícitos,
aplicados igualmente aos quatro modelos: (i) tamanho do modelo, isto é, o número de elementos que
precisariam ser lidos para compreendê-lo por inteiro (coeficientes ou nós de árvore); (ii) número de
variáveis efetivamente usadas; (iii) possibilidade de calcular o risco manualmente; (iv) possibilidade
de identificar a direção e a magnitude do efeito de cada variável; e (v) possibilidade de explicar a
predição de um paciente individual sem ferramentas pós-hoc.

Todo o experimento foi implementado em R (R CORE TEAM, 2024), com semente fixa (2026), e pode ser
reproduzido pelo script `run_all.R`.

## Resultados

### Desempenho preditivo

Com a estratégia MICE, o gradient boosting obteve a maior AUC média (0,838 ± 0,045), seguido de perto
pela regressão logística (0,836 ± 0,042) e pelo random forest (0,829 ± 0,048). A árvore de decisão
teve desempenho claramente inferior (0,731 ± 0,063). A regressão logística apresentou a maior acurácia
(0,767) e o menor escore de Brier (0,157). Em todos
os modelos, a especificidade (0,84–0,88) foi bem maior que a sensibilidade (0,53–0,59), reflexo do
limiar de 0,5 e do desbalanceamento das classes.

No ponto de operação de triagem (sensibilidade ≥ 80%), a especificidade foi de 0,692 ± 0,094 na
regressão logística, 0,716 ± 0,085 no random forest e 0,731 ± 0,081 no gradient boosting, sem diferença
significativa em relação à logística (p = 0,34 e 0,23). A árvore de decisão, por gerar apenas três
níveis de risco, não possui ponto de corte intermediário e caiu para 0,165.

Quanto à calibração, a regressão logística (intercepto −0,002; inclinação 0,93) e o random forest
(−0,014; 1,00) produziram probabilidades próximas do risco observado. O gradient boosting apresentou
inclinação de 1,37, indicando probabilidades comprimidas em torno da média, e a árvore de decisão,
inclinação de 0,76.

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
um aumento de um desvio-padrão na glicose (≈ 30 mg/dL) multiplicou a chance de diabetes por 3,28
(IC 95%: 2,45–4,38); no IMC (≈ 6,9 kg/m²), por 1,84 (1,38–2,45). Gestações (OR = 1,50) e histórico
familiar (OR = 1,34) também foram significativos. Com imputação múltipla, os intervalos ficaram em
média 13% mais largos do que com uma imputação única. Insulina, dobra cutânea, pressão e idade não tiveram
efeito significativo depois de ajustadas pelas demais variáveis. A árvore podada ficou com apenas três
folhas: pacientes com glicose ≥ 127,5 mg/dL e IMC ≥ 29,95 kg/m² têm 73% de chance de diabetes, contra
19% entre os que têm glicose < 127,5 mg/dL.

### Desempenho versus interpretabilidade (objetivo central)

| Modelo | AUC | Perda vs. melhor | Tamanho do modelo | Variáveis | Cálculo manual | Direção do efeito | Explicação individual |
|---|---|---|---|---|---|---|---|
| Regressão logística | 0,836 | 0,002 | 9 coeficientes | 8 | Sim | Sim (OR e IC 95%) | Sim |
| Árvore de decisão | 0,731 | 0,107 | 5 nós | 2 | Sim | Parcial | Sim |
| Random forest | 0,829 | 0,009 | 124.748 nós | 8 | Não | Não | Não |
| Gradient boosting | 0,838 | — | 1.589 nós | 7 | Não | Não | Não |

A regressão logística é o único modelo que permanece dentro da faixa de perda não relevante (≤ 0,05) e
atende aos três critérios práticos de interpretabilidade, com nove coeficientes a interpretar, contra
1.589 nós no gradient boosting e 124.748 no random forest. A árvore de decisão é ainda mais compacta,
mas perde desempenho de forma clinicamente relevante.

### Análise de robustez: base CDC Diabetes Health Indicators

Para verificar se a conclusão depende do tamanho e da especificidade do Pima, a mesma comparação foi
repetida na base CDC Diabetes Health Indicators (UCI, id 891), derivada do levantamento telefônico
BRFSS: 253.680 pessoas, 21 variáveis autodeclaradas e 13,9% com pré-diabetes ou diabetes. Por causa do
tamanho, usou-se validação cruzada estratificada 5-fold repetida 2 vezes, e o random forest foi
ajustado com o pacote `ranger` (WRIGHT; ZIEGLER, 2017). Os demais modelos, hiperparâmetros e critérios
foram mantidos. Como as variáveis diferem das do Pima, trata-se de uma replicação do experimento, e
não de validação externa dos modelos.

As AUCs foram muito próximas das do Pima: gradient boosting 0,829, regressão logística 0,822, random
forest 0,822 e árvore de decisão 0,730. Com 330 vezes mais dados, a vantagem do gradient boosting sobre
a logística tornou-se estatisticamente significativa (+0,007; IC 95%: 0,006 a 0,009; p < 0,001), mas
o intervalo inteiro permaneceu muito abaixo do limite de 0,05: a diferença é real, porém clinicamente
irrelevante. A perda ao trocar o melhor modelo pela árvore voltou a ser relevante (0,100).

### Síntese

A regressão logística oferece o melhor equilíbrio entre desempenho e interpretabilidade no Pima
Dataset: o desempenho é equivalente ao do melhor ensemble, as probabilidades são bem calibradas e os
coeficientes têm leitura clínica direta. A conclusão se repetiu numa base 330 vezes maior. O resultado
está de acordo com Rudin (2019), segundo quem modelos interpretáveis podem ter desempenho comparável
ao de caixas-pretas em dados tabulares estruturados.

## Referências a acrescentar

BREIMAN, L. Random forests. **Machine Learning**, v. 45, n. 1, p. 5-32, 2001.

BREIMAN, L.; FRIEDMAN, J. H.; OLSHEN, R. A.; STONE, C. J. **Classification and regression trees**.
Belmont: Wadsworth, 1984.

FRIEDMAN, J. H. Greedy function approximation: a gradient boosting machine. **The Annals of
Statistics**, v. 29, n. 5, p. 1189-1232, 2001.

MOONS, K. G. M. et al. Using the outcome for imputation of missing predictor values was preferred.
**Journal of Clinical Epidemiology**, v. 59, n. 10, p. 1092-1101, 2006.

NADEAU, C.; BENGIO, Y. Inference for the generalization error. **Machine Learning**, v. 52, n. 3,
p. 239-281, 2003.

R CORE TEAM. **R: a language and environment for statistical computing**. Vienna: R Foundation for
Statistical Computing, 2024.

RUBIN, D. B. **Multiple imputation for nonresponse in surveys**. New York: Wiley, 1987.

UCI MACHINE LEARNING REPOSITORY. **CDC Diabetes Health Indicators** (id 891). Disponível em:
https://archive.ics.uci.edu/dataset/891. Acesso em: 28 set. 2026.

VAN BUUREN, S.; GROOTHUIS-OUDSHOORN, K. mice: multivariate imputation by chained equations in R.
**Journal of Statistical Software**, v. 45, n. 3, p. 1-67, 2011.

VAN CALSTER, B. et al. Calibration: the Achilles heel of predictive analytics. **BMC Medicine**,
v. 17, art. 230, 2019.

WRIGHT, M. N.; ZIEGLER, A. ranger: a fast implementation of random forests for high dimensional data
in C++ and R. **Journal of Statistical Software**, v. 77, n. 1, p. 1-17, 2017.
