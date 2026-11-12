extends SceneTree
## Suite de validacao numerica do StatCore.
## Executar:  godot --headless --script tests/test_statcore.gd
##
## Cada caso compara o resultado do GDScript com um gabarito calculado em
## Python/NumPy/SciPy. Tolerancia padrao 1e-6 (absoluta) salvo indicacao.

var ok := 0
var fail := 0
var falhas: Array[String] = []

func check(nome: String, obtido: float, esperado: float, tol: float = 1e-6) -> void:
	var d := absf(obtido - esperado)
	if d <= tol:
		ok += 1
	elif is_nan(obtido) and is_nan(esperado):
		ok += 1
	else:
		fail += 1
		falhas.append("%s obtido=%.10f esperado=%.10f |d|=%s" % [nome.rpad(42, "."), obtido, esperado, String.num_scientific(d)])

func check_str(nome: String, obtido: String, esperado: String) -> void:
	if obtido == esperado:
		ok += 1
	else:
		fail += 1
		falhas.append("%s obtido='%s' esperado='%s'" % [nome.rpad(42, "."), obtido, esperado])

func _initialize() -> void:
	var A := PackedFloat64Array([12.1, 14.3, 11.8, 15.2, 13.9, 10.4, 16.1, 12.7, 13.3, 14.8])
	var B := PackedFloat64Array([15.6, 17.2, 16.8, 14.9, 18.1, 15.1, 16.4, 17.7])
	var C := PackedFloat64Array([9.0, 10.0, 11.0, 12.0])

	print("== Distribuicoes / funcoes especiais ==")
	check("normal_cdf(1.96)", StatCore.normal_cdf(1.96), 0.975002104852, 1e-9)
	check("normal_quantile(0.975)", StatCore.normal_quantile(0.975), 1.959963984540, 1e-9)
	check("t_quantile(0.975,16)", StatCore.t_quantile(0.975, 16.0), 2.119905299221, 1e-7)
	check("t_two_sided_p(2.5,12)", StatCore.t_two_sided_p(2.5, 12.0), 0.027915399571, 1e-9)
	check("chi2_p_value(7.3,3)", StatCore.chi2_p_value(7.3, 3.0), 0.062926236459, 1e-9)
	check("f_p_value(4.5,2,17)", StatCore.f_p_value(4.5, 2.0, 17.0), 0.027011106419, 1e-9)
	check("binom_pmf(3,10,.3)", StatCore.binomial_pmf(3, 10, 0.3), 0.266827932000, 1e-9)
	check("binom_cdf(3,10,.3)", StatCore.binomial_cdf(3, 10, 0.3), 0.649610718400, 1e-9)
	check("poisson_pmf(4,2.5)", StatCore.poisson_pmf(4, 2.5), 0.133601885781, 1e-9)
	check("poisson_cdf(4,2.5)", StatCore.poisson_cdf(4, 2.5), 0.891178018914, 1e-9)
	check("erf(1.0)", StatCore.erf(1.0), 0.842700792950, 1e-7)
	check("ln_gamma(5)", StatCore.ln_gamma(5.0), 3.178053830348, 1e-9)

	print("== Descritiva ==")
	check("media A", StatCore.mean(A), 13.46, 1e-12)
	check("mediana A", StatCore.median(A), 13.6, 1e-12)
	check("desvio A", StatCore.std_dev(A), 1.7404980130, 1e-9)
	check("q25 A", StatCore.quantile(StatCore.sorted(A), 0.25), 12.25, 1e-12)
	check("q75 A", StatCore.quantile(StatCore.sorted(A), 0.75), 14.675, 1e-12)
	check("p10 A", StatCore.quantile(StatCore.sorted(A), 0.10), 11.66, 1e-12)
	check("iqr A", StatCore.iqr(A), 2.425, 1e-12)
	check("assimetria A", StatCore.skewness(A), -0.2485009473, 1e-9)
	check("curtose A", StatCore.kurtosis(A), -0.5214634321, 1e-9)
	check("cv A", StatCore.cv_percent(A), 12.93089162720612, 1e-9)

	print("== Testes ==")
	var tw := StatCore.t_test_independent(A, B, true)
	check("welch t", float(tw["t"]), -4.3518370173, 1e-9)
	check("welch p", float(tw["p"]), 0.000515143890, 1e-9)
	check("welch gl", float(tw["gl"]), 15.6995355639, 1e-8)
	var ts := StatCore.t_test_independent(A, B, false)
	check("student t", float(ts["t"]), -4.1697229169, 1e-9)
	check("student p", float(ts["p"]), 0.000722860745, 1e-9)
	var mw := StatCore.mann_whitney(A, B)
	check("mann-whitney U", float(mw["U"]), 5.0, 1e-9)
	check("mann-whitney p", float(mw["p"]), 0.0021737510, 1e-6)
	var tab: Array = [PackedFloat64Array([30.0, 20.0]), PackedFloat64Array([15.0, 35.0])]
	var cq := StatCore.chi2_independence(tab, true)
	check("chi2 yates", float(cq["chi2"]), 7.919191919191919, 1e-9)
	check("chi2 yates p", float(cq["p"]), 0.004891311452, 1e-9)
	var cq2 := StatCore.chi2_independence(tab, false)
	check("chi2 sem yates", float(cq2["chi2"]), 9.09090909090909, 1e-9)
	var fe := StatCore.fisher_exact(8, 2, 1, 5)
	check("fisher p", float(fe["p"]), 0.034965034965, 1e-9)
	var an := StatCore.anova_one_way([A, B, C])
	check("anova F", float(an["F"]), 22.72885580717676, 1e-9)
	check("anova p", float(an["p"]), 9.121112657412588e-06, 1e-11)
	var kw := StatCore.kruskal_wallis([A, B, C])
	check("kruskal H", float(kw["H"]), 14.935375494071138, 1e-9)
	check("kruskal p", float(kw["p"]), 0.0005712476400113411, 1e-11)

	print("== Correlacao / regressao ==")
	var x := PackedFloat64Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	var pr := StatCore.pearson(x, A)
	check("pearson r", float(pr["r"]), 0.2213948622240502, 1e-9)
	check("pearson p", float(pr["p"]), 0.5387471132952806, 1e-9)
	var lr := StatCore.linear_regression(x, A)
	check("reg b1", float(lr["b1"]), 0.12727273, 1e-8)
	check("reg b0", float(lr["b0"]), 12.76, 1e-8)
	check("reg se_b1", float(lr["se_b1"]), 0.19820266779400617, 1e-9)
	check("reg p", float(lr["p"]), 0.5387471132952808, 1e-9)

	print("== Amostragem ==")
	var ss := StatCore.sample_size_proportion(3400, 0.35, 0.05, 0.95)
	# n0 = 1.959964^2*0.35*0.65/0.05^2 = 349.67 ; corrigido p/ N=3400 -> 316.99 -> 317
	check("n0 prop", float(ss["n0"]), 349.57275268314606, 1e-9)
	check("n corrigido", float(ss["n"]), 318.0, 0.0)
	var ic := StatCore.proportion_ci(35, 100)
	check("prop p", float(ic["p"]), 0.35, 1e-12)
	check("prop ic lo", float(ic["ic95"][0]), 0.35 - 1.959963984540 * sqrt(0.35 * 0.65 / 100.0), 1e-8)

	print("")
	if fail == 0:
		print("OK  %d verificacoes passaram." % ok)
	else:
		for f in falhas:
			print("FALHA ", f)
		print("%d falhas de %d verificacoes." % [fail, ok + fail])
	quit(0 if fail == 0 else 1)
