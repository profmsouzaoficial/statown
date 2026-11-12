class_name StatCore
extends RefCounted
## Biblioteca matematica pura do StaTown (GDScript, sem dependencias nativas).
##
## Todos os metodos sao estaticos e deterministicos. As funcoes especiais
## (erf, beta/gama incompletas) seguem Abramowitz & Stegun e Numerical Recipes,
## com erro absoluto < 1e-7 nas regioes de interesse. A suite
## `tests/headless_validation.gd` compara cada rotina com gabaritos analiticos.
##
## Convencoes:
##   - Vetores de dados sao PackedFloat64Array.
##   - Quantis usam o metodo 7 de Hyndman & Fan (mesmo do R/Numpy, type=7).
##   - p-valores sao sempre bilaterais quando nao indicado.

# ============================================================================
# 1. FUNCOES ESPECIAIS
# ============================================================================

## Funcao erro de Gauss.
## |x| < 3: serie de Taylor (precisao de maquina).
## |x| >= 3: P(1/2, x^2) via gama incompleta regularizada (fracao continuada).
static func erf(x: float) -> float:
	if x == 0.0:
		return 0.0
	var ax := absf(x)
	var y: float
	if ax < 3.0:
		var termo := ax
		var soma := ax
		var n := 0
		while n < 400:
			n += 1
			termo *= -ax * ax / float(n)
			var parcela := termo / float(2 * n + 1)
			soma += parcela
			if absf(parcela) < absf(soma) * 1e-17:
				break
		y = 2.0 / sqrt(PI) * soma
	else:
		y = gamma_reg_p(0.5, ax * ax)
	return y if x > 0.0 else -y


## Complemento da funcao erro, erfc(x) = 1 - erf(x), estavel na cauda positiva.
static func erfc(x: float) -> float:
	if x < 0.0:
		return 2.0 - erfc(-x)
	if x > 3.0:
		return gamma_reg_q(0.5, x * x)
	return 1.0 - erf(x)


## Log-gama de Lanczos (g=7, n=9): preciso para x > 0.
static func ln_gamma(x: float) -> float:
	if x < 0.5:
		# reflexao: G(x)G(1-x) = pi / sin(pi x)
		return log(PI / sin(PI * x)) - ln_gamma(1.0 - x)
	var g := 7.0
	var c: Array = [0.99999999999980993, 676.5203681218851, -1259.1392167224028,
		771.32342877765313, -176.61502916214059, 12.507343278686905,
		-0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
	var z := x - 1.0
	var sum := float(c[0])
	for i in range(1, 9):
		sum += float(c[i]) / (z + float(i))
	var tt := z + g + 0.5
	return 0.5 * log(2.0 * PI) + (z + 0.5) * log(tt) - tt + log(sum)


static func ln_factorial(n: int) -> float:
	if n <= 1:
		return 0.0
	return ln_gamma(float(n) + 1.0)


## Beta incompleta regularizada I_x(a,b) por fracao continuada (Lentz).
static func beta_reg_inc(a: float, b: float, x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var lbeta := ln_gamma(a + b) - ln_gamma(a) - ln_gamma(b)
	var front := exp(lbeta + a * log(x) + b * log(1.0 - x))
	if x < (a + 1.0) / (a + b + 2.0):
		return front * _betacf(a, b, x) / a
	return 1.0 - front * _betacf(b, a, 1.0 - x) / b


static func _betacf(a: float, b: float, x: float) -> float:
	var tiny := 1e-30
	var qab := a + b
	var qap := a + 1.0
	var qam := a - 1.0
	var c := 1.0
	var d := 1.0 - qab * x / qap
	if absf(d) < tiny:
		d = tiny
	d = 1.0 / d
	var h := d
	for m in range(1, 300):
		var mf := float(m)
		var m2 := 2.0 * mf
		var aa := mf * (b - mf) * x / ((qam + m2) * (a + m2))
		d = 1.0 + aa * d
		if absf(d) < tiny:
			d = tiny
		c = 1.0 + aa / c
		if absf(c) < tiny:
			c = tiny
		d = 1.0 / d
		h *= d * c
		aa = -(a + mf) * (qab + mf) * x / ((a + m2) * (qap + m2))
		d = 1.0 + aa * d
		if absf(d) < tiny:
			d = tiny
		c = 1.0 + aa / c
		if absf(c) < tiny:
			c = tiny
		d = 1.0 / d
		var de := d * c
		h *= de
		if absf(de - 1.0) < 1e-12:
			break
	return h


## Gama incompleta regularizada P(a,x) = gama(a,x)/G(a).
static func gamma_reg_p(a: float, x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x < a + 1.0:
		return _gamma_series(a, x)
	return 1.0 - _gamma_cf(a, x)


static func gamma_reg_q(a: float, x: float) -> float:
	return 1.0 - gamma_reg_p(a, x)


static func _gamma_series(a: float, x: float) -> float:
	var ap := a
	var sum := 1.0 / a
	var del := sum
	for _i in range(500):
		ap += 1.0
		del *= x / ap
		sum += del
		if absf(del) < absf(sum) * 1e-14:
			break
	return sum * exp(-x + a * log(x) - ln_gamma(a))


static func _gamma_cf(a: float, x: float) -> float:
	var tiny := 1e-30
	var b := x + 1.0 - a
	var c := 1.0 / tiny
	var d := 1.0 / b
	var h := d
	for i in range(1, 500):
		var an := -float(i) * (float(i) - a)
		b += 2.0
		d = an * d + b
		if absf(d) < tiny:
			d = tiny
		c = b + an / c
		if absf(c) < tiny:
			c = tiny
		d = 1.0 / d
		var de := d * c
		h *= de
		if absf(de - 1.0) < 1e-14:
			break
	return exp(-x + a * log(x) - ln_gamma(a)) * h


# ============================================================================
# 2. DISTRIBUICOES
# ============================================================================

static func normal_pdf(x: float, mu: float = 0.0, sigma: float = 1.0) -> float:
	if sigma <= 0.0:
		return 0.0
	var z := (x - mu) / sigma
	return exp(-0.5 * z * z) / (sigma * sqrt(2.0 * PI))


static func normal_cdf(x: float, mu: float = 0.0, sigma: float = 1.0) -> float:
	if sigma <= 0.0:
		return 0.0
	return 0.5 * (1.0 + erf((x - mu) / (sigma * sqrt(2.0))))


## Quantil normal (Acklam) refinado por Newton.
static func normal_quantile(p: float, mu: float = 0.0, sigma: float = 1.0) -> float:
	if p <= 0.0:
		return -INF
	if p >= 1.0:
		return INF
	var a := [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
		1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
	var b := [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
		6.680131188771972e+01, -1.328068155288572e+01]
	var c := [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
		-2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
	var d := [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
		3.754408661907416e+00]
	var pl := 0.02425
	var q: float
	var x: float
	if p < pl:
		q = sqrt(-2.0 * log(p))
		x = (((((float(c[0]) * q + float(c[1])) * q + float(c[2])) * q + float(c[3])) * q + float(c[4])) * q + float(c[5])) / ((((float(d[0]) * q + float(d[1])) * q + float(d[2])) * q + float(d[3])) * q + 1.0)
	elif p <= 1.0 - pl:
		q = p - 0.5
		var r := q * q
		x = (((((float(a[0]) * r + float(a[1])) * r + float(a[2])) * r + float(a[3])) * r + float(a[4])) * r + float(a[5])) * q / (((((float(b[0]) * r + float(b[1])) * r + float(b[2])) * r + float(b[3])) * r + float(b[4])) * r + 1.0)
	else:
		q = sqrt(-2.0 * log(1.0 - p))
		x = -(((((float(c[0]) * q + float(c[1])) * q + float(c[2])) * q + float(c[3])) * q + float(c[4])) * q + float(c[5])) / ((((float(d[0]) * q + float(d[1])) * q + float(d[2])) * q + float(d[3])) * q + 1.0)
	# refinamento de Halley
	var e := normal_cdf(x) - p
	var u := e * sqrt(2.0 * PI) * exp(x * x / 2.0)
	x = x - u / (1.0 + x * u / 2.0)
	return mu + sigma * x


static func binomial_pmf(k: int, n: int, p: float) -> float:
	if k < 0 or k > n:
		return 0.0
	if p <= 0.0:
		return 1.0 if k == 0 else 0.0
	if p >= 1.0:
		return 1.0 if k == n else 0.0
	var ln_c := ln_factorial(n) - ln_factorial(k) - ln_factorial(n - k)
	return exp(ln_c + k * log(p) + (n - k) * log(1.0 - p))


static func binomial_cdf(k: int, n: int, p: float) -> float:
	var s := 0.0
	for i in range(0, mini(k, n) + 1):
		s += binomial_pmf(i, n, p)
	return clampf(s, 0.0, 1.0)


static func poisson_pmf(k: int, lam: float) -> float:
	if k < 0 or lam < 0.0:
		return 0.0
	if lam == 0.0:
		return 1.0 if k == 0 else 0.0
	return exp(-lam + k * log(lam) - ln_factorial(k))


static func poisson_cdf(k: int, lam: float) -> float:
	var s := 0.0
	for i in range(0, k + 1):
		s += poisson_pmf(i, lam)
	return clampf(s, 0.0, 1.0)


## CDF da t de Student. P(T <= t).
static func t_cdf(t: float, df: float) -> float:
	if df <= 0.0:
		return NAN
	var x := df / (df + t * t)
	var ib := beta_reg_inc(df / 2.0, 0.5, x)
	return 1.0 - 0.5 * ib if t > 0.0 else 0.5 * ib


static func t_two_sided_p(t: float, df: float) -> float:
	if df <= 0.0:
		return NAN
	return beta_reg_inc(df / 2.0, 0.5, df / (df + t * t))


static func t_quantile(p: float, df: float) -> float:
	if p <= 0.0 or p >= 1.0:
		return NAN
	var lo := -1000.0
	var hi := 1000.0
	for _i in range(200):
		var mid := (lo + hi) * 0.5
		if t_cdf(mid, df) < p:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func chi2_cdf(x: float, df: float) -> float:
	if x <= 0.0:
		return 0.0
	return gamma_reg_p(df / 2.0, x / 2.0)


static func chi2_p_value(x: float, df: float) -> float:
	return 1.0 - chi2_cdf(x, df)


static func f_cdf(x: float, d1: float, d2: float) -> float:
	if x <= 0.0:
		return 0.0
	return beta_reg_inc(d1 / 2.0, d2 / 2.0, d1 * x / (d1 * x + d2))


static func f_p_value(f: float, d1: float, d2: float) -> float:
	return 1.0 - f_cdf(f, d1, d2)


# ============================================================================
# 3. ESTATISTICA DESCRITIVA
# ============================================================================

static func mean(v: PackedFloat64Array) -> float:
	var n := v.size()
	if n == 0:
		return NAN
	var s := 0.0
	for x in v:
		s += x
	return s / float(n)


static func median(v: PackedFloat64Array) -> float:
	return quantile(sorted(v), 0.5)


## Quantil tipo 7 (Hyndman-Fan), igual a numpy.percentile/R type=7.
static func quantile(sorted_v: PackedFloat64Array, q: float) -> float:
	var n := sorted_v.size()
	if n == 0:
		return NAN
	if n == 1:
		return sorted_v[0]
	var h := (float(n) - 1.0) * clampf(q, 0.0, 1.0)
	var lo := int(floor(h))
	var hi := mini(lo + 1, n - 1)
	var frac := h - float(lo)
	return sorted_v[lo] + frac * (sorted_v[hi] - sorted_v[lo])


static func mode_of(v: PackedFloat64Array) -> float:
	if v.is_empty():
		return NAN
	var counts := {}
	var best := v[0]
	var best_n := 0
	for x in v:
		var k := snappedf(x, 0.0001)
		counts[k] = int(counts.get(k, 0)) + 1
		if int(counts[k]) > best_n:
			best_n = int(counts[k])
			best = k
	return best


static func variance(v: PackedFloat64Array) -> float:
	var n := v.size()
	if n < 2:
		return NAN
	var m := mean(v)
	var s := 0.0
	for x in v:
		s += (x - m) * (x - m)
	return s / float(n - 1)


static func std_dev(v: PackedFloat64Array) -> float:
	return sqrt(variance(v))


static func variance_pop(v: PackedFloat64Array) -> float:
	var n := v.size()
	if n < 1:
		return NAN
	var m := mean(v)
	var s := 0.0
	for x in v:
		s += (x - m) * (x - m)
	return s / float(n)


static func min_of(v: PackedFloat64Array) -> float:
	var m := INF
	for x in v:
		m = minf(m, x)
	return m


static func max_of(v: PackedFloat64Array) -> float:
	var m := -INF
	for x in v:
		m = maxf(m, x)
	return m


static func iqr(v: PackedFloat64Array) -> float:
	var s := sorted(v)
	return quantile(s, 0.75) - quantile(s, 0.25)


static func cv_percent(v: PackedFloat64Array) -> float:
	var m := mean(v)
	if m == 0.0:
		return NAN
	return std_dev(v) / absf(m) * 100.0


## Assimetria de Fisher-Pearson ajustada (g1), igual ao SPSS/SciPy bias=False.
static func skewness(v: PackedFloat64Array) -> float:
	var n := v.size()
	if n < 3:
		return NAN
	var m := mean(v)
	var s := std_dev(v)
	if s == 0.0:
		return 0.0
	var s3 := 0.0
	for x in v:
		s3 += pow((x - m) / s, 3.0)
	return float(n) / (float(n - 1) * float(n - 2)) * s3


## Excesso de curtose amostral (g2), igual ao SPSS/SciPy bias=False.
static func kurtosis(v: PackedFloat64Array) -> float:
	var n := v.size()
	if n < 4:
		return NAN
	var m := mean(v)
	var s := std_dev(v)
	if s == 0.0:
		return 0.0
	var s4 := 0.0
	for x in v:
		s4 += pow((x - m) / s, 4.0)
	var a := float(n) * float(n + 1) / (float(n - 1) * float(n - 2) * float(n - 3))
	var b := 3.0 * pow(float(n - 1), 2.0) / (float(n - 2) * float(n - 3))
	return a * s4 - b


## Regra de Sturges para numero de classes.
static func sturges_classes(n: int) -> int:
	return maxi(2, int(ceil(1.0 + 3.322 * log(float(maxi(n, 1))) / log(10.0))))


## Tabela de frequencias para histograma.
static func histogram(v: PackedFloat64Array, n_classes: int = 0) -> Dictionary:
	var n := v.size()
	if n == 0:
		return {"bins": PackedFloat64Array(), "counts": PackedFloat64Array(), "width": 0.0}
	if n_classes <= 0:
		n_classes = sturges_classes(n)
	var lo := min_of(v)
	var hi := max_of(v)
	if is_equal_approx(lo, hi):
		hi = lo + 1.0
	var w := (hi - lo) / float(n_classes)
	var bins := PackedFloat64Array()
	var counts := PackedFloat64Array()
	bins.resize(n_classes + 1)
	counts.resize(n_classes)
	for i in range(n_classes + 1):
		bins[i] = lo + w * float(i)
	for i in range(n_classes):
		counts[i] = 0.0
	for x in v:
		var idx := int(floor((x - lo) / w))
		idx = clampi(idx, 0, n_classes - 1)
		counts[idx] += 1.0
	return {"bins": bins, "counts": counts, "width": w}


## Estatisticas descritivas completas (usada pelos paineis e pelo relatorio).
static func sorted(v: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = v.duplicate()
	out.sort()
	return out


## Estatisticas descritivas completas (usada pelos paineis e pelo relatorio).
static func describe(v: PackedFloat64Array) -> Dictionary:
	var s := sorted(v)
	var d := {
		"n": v.size(),
		"media": mean(v),
		"mediana": quantile(s, 0.5),
		"moda": mode_of(v),
		"q1": quantile(s, 0.25),
		"q3": quantile(s, 0.75),
		"iqr": quantile(s, 0.75) - quantile(s, 0.25),
		"p10": quantile(s, 0.10),
		"p90": quantile(s, 0.90),
		"min": min_of(v),
		"max": max_of(v),
		"amplitude": max_of(v) - min_of(v),
		"variancia": variance(v),
		"desvio_padrao": std_dev(v),
		"cv": cv_percent(v),
		"assimetria": skewness(v),
		"curtose": kurtosis(v),
		"erro_padrao": std_dev(v) / sqrt(float(maxi(v.size(), 1))),
	}
	return d


## Mapa de frequencias para variavel qualitativa.
static func frequency_table(values: PackedStringArray) -> Array:
	var counts := {}
	var order: Array = []
	for s in values:
		if not counts.has(s):
			counts[s] = 0
			order.append(s)
		counts[s] = int(counts[s]) + 1
	var total := maxi(values.size(), 1)
	var out: Array = []
	for k in order:
		out.append({"categoria": k, "n": int(counts[k]), "pct": 100.0 * float(counts[k]) / float(total)})
	return out


# ============================================================================
# 4. INFERENCIA: TESTES PARAMETRICOS
# ============================================================================

## Teste t para duas amostras independentes. welch=true aplica correcao de Welch.
static func t_test_independent(a: PackedFloat64Array, b: PackedFloat64Array, welch: bool = true) -> Dictionary:
	var n1 := a.size()
	var n2 := b.size()
	if n1 < 2 or n2 < 2:
		return {"erro": "amostras insuficientes"}
	var m1 := mean(a)
	var m2 := mean(b)
	var v1 := variance(a)
	var v2 := variance(b)
	var diff := m1 - m2
	var se: float
	var df: float
	if welch:
		se = sqrt(v1 / float(n1) + v2 / float(n2))
		var num := pow(v1 / float(n1) + v2 / float(n2), 2.0)
		var den := pow(v1 / float(n1), 2.0) / float(n1 - 1) + pow(v2 / float(n2), 2.0) / float(n2 - 1)
		df = num / den if den > 0.0 else float(n1 + n2 - 2)
	else:
		var sp2 := (float(n1 - 1) * v1 + float(n2 - 1) * v2) / float(n1 + n2 - 2)
		se = sqrt(sp2 * (1.0 / float(n1) + 1.0 / float(n2)))
		df = float(n1 + n2 - 2)
	if se == 0.0:
		return {"erro": "variancia zero"}
	var t := diff / se
	var p := t_two_sided_p(t, df)
	var tcrit := t_quantile(0.975, df)
	return {
		"teste": "t de Welch" if welch else "t de Student",
		"n1": n1, "n2": n2,
		"media1": m1, "media2": m2,
		"diff": diff, "se": se, "gl": df, "t": t, "p": p,
		"ic95": [diff - tcrit * se, diff + tcrit * se],
		"d_cohen": diff / sqrt((v1 + v2) * 0.5) if (v1 + v2) > 0.0 else 0.0,
	}


static func t_test_paired(antes: PackedFloat64Array, depois: PackedFloat64Array) -> Dictionary:
	var n := mini(antes.size(), depois.size())
	if n < 2:
		return {"erro": "amostras insuficientes"}
	var d := PackedFloat64Array()
	d.resize(n)
	for i in range(n):
		d[i] = depois[i] - antes[i]
	var md := mean(d)
	var sd := std_dev(d)
	if sd == 0.0:
		return {"erro": "diferencas sem variabilidade"}
	var t := md / (sd / sqrt(float(n)))
	var df := float(n - 1)
	var p := t_two_sided_p(t, df)
	var tc := t_quantile(0.975, df)
	return {
		"teste": "t pareado", "n": n, "diff_media": md, "sd_diff": sd,
		"gl": df, "t": t, "p": p,
		"ic95": [md - tc * sd / sqrt(float(n)), md + tc * sd / sqrt(float(n))],
	}


## ANOVA one-way. grupos: Array de PackedFloat64Array.
static func anova_one_way(grupos: Array) -> Dictionary:
	var k := grupos.size()
	if k < 2:
		return {"erro": "grupos insuficientes"}
	var n_total := 0
	var soma_total := 0.0
	var lista: Array = []
	for g in grupos:
		var gg: PackedFloat64Array = g
		if gg.size() < 2:
			return {"erro": "cada grupo precisa de n >= 2"}
		n_total += gg.size()
		var m := mean(gg)
		lista.append({"n": gg.size(), "media": m, "var": variance(gg)})
		soma_total += m * float(gg.size())
	var grande_media := soma_total / float(n_total)
	var sq_entre := 0.0
	for item in lista:
		sq_entre += float(item["n"]) * pow(float(item["media"]) - grande_media, 2.0)
	var sq_dentro := 0.0
	for i in range(k):
		var item: Dictionary = lista[i]
		var gg: PackedFloat64Array = grupos[i]
		var m: float = item["media"]
		for x in gg:
			sq_dentro += (x - m) * (x - m)
	var gl_entre := float(k - 1)
	var gl_dentro := float(n_total - k)
	if gl_dentro <= 0.0:
		return {"erro": "graus de liberdade invalidos"}
	var qm_entre := sq_entre / gl_entre
	var qm_dentro := sq_dentro / gl_dentro
	if qm_dentro == 0.0:
		return {"erro": "variancia residual zero"}
	var f := qm_entre / qm_dentro
	var p := f_p_value(f, gl_entre, gl_dentro)
	var eta2 := sq_entre / (sq_entre + sq_dentro)
	return {
		"teste": "ANOVA one-way", "k": k, "n": n_total,
		"sq_entre": sq_entre, "sq_dentro": sq_dentro,
		"gl_entre": gl_entre, "gl_dentro": gl_dentro,
		"qm_entre": qm_entre, "qm_dentro": qm_dentro,
		"F": f, "p": p, "eta2": eta2,
		"medias": lista,
	}


## Comparacoes post-hoc por Bonferroni (t entre pares com alfa ajustado).
static func posthoc_bonferroni(grupos: Array, nomes: PackedStringArray) -> Array:
	var out: Array = []
	var k := grupos.size()
	var pares := k * (k - 1) / 2
	if pares == 0:
		return out
	for i in range(k):
		for j in range(i + 1, k):
			var r := t_test_independent(grupos[i], grupos[j], true)
			if r.has("erro"):
				continue
			var p_adj := minf(1.0, float(r["p"]) * float(pares))
			out.append({"a": nomes[i] if i < nomes.size() else str(i),
				"b": nomes[j] if j < nomes.size() else str(j),
				"diff": r["diff"], "p_bruto": r["p"], "p_ajustado": p_adj,
				"significante": p_adj < 0.05})
	return out


# ============================================================================
# 5. INFERENCIA: TESTES NAO-PARAMETRICOS
# ============================================================================

static func _rank_all(valores: PackedFloat64Array) -> PackedFloat64Array:
	var n := valores.size()
	var idx: Array = []
	for i in range(n):
		idx.append(i)
	idx.sort_custom(func(p, q): return valores[p] < valores[q])
	var ranks := PackedFloat64Array()
	ranks.resize(n)
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and is_equal_approx(valores[idx[j + 1]], valores[idx[i]]):
			j += 1
		var avg := (float(i + 1) + float(j + 1)) * 0.5
		for t in range(i, j + 1):
			ranks[idx[t]] = avg
		i = j + 1
	return ranks


## Teste U de Mann-Whitney com correcao de empates e continuidade.
static func mann_whitney(a: PackedFloat64Array, b: PackedFloat64Array) -> Dictionary:
	var n1 := a.size()
	var n2 := b.size()
	if n1 < 2 or n2 < 2:
		return {"erro": "amostras insuficientes"}
	var all := PackedFloat64Array()
	all.append_array(a)
	all.append_array(b)
	var ranks := _rank_all(all)
	var r1 := 0.0
	for i in range(n1):
		r1 += ranks[i]
	var u1 := r1 - float(n1 * (n1 + 1)) / 2.0
	var u2 := float(n1 * n2) - u1
	var u := minf(u1, u2)
	# correcao de empates
	var counts := {}
	for x in all:
		var k := snappedf(x, 0.00001)
		counts[k] = int(counts.get(k, 0)) + 1
	var tie_sum := 0.0
	for k in counts:
		var t := float(counts[k])
		if t > 1.0:
			tie_sum += t * t * t - t
	var n := float(n1 + n2)
	var var_u := float(n1 * n2) / 12.0 * ((n + 1.0) - tie_sum / (n * (n - 1.0)))
	if var_u <= 0.0:
		return {"erro": "variancia nula"}
	var mu_u := float(n1 * n2) / 2.0
	var z := (u - mu_u + 0.5) / sqrt(var_u)
	var p := 2.0 * (1.0 - normal_cdf(absf(z)))
	return {
		"teste": "Mann-Whitney U", "n1": n1, "n2": n2,
		"U": u, "U1": u1, "U2": u2, "z": z, "p": p,
		"mediana1": median(a), "mediana2": median(b),
	}


## Teste H de Kruskal-Wallis com correcao de empates.
static func kruskal_wallis(grupos: Array) -> Dictionary:
	var k := grupos.size()
	if k < 2:
		return {"erro": "grupos insuficientes"}
	var all := PackedFloat64Array()
	var ns := PackedFloat64Array()
	for g in grupos:
		var gg: PackedFloat64Array = g
		if gg.size() < 1:
			return {"erro": "grupo vazio"}
		all.append_array(gg)
		ns.append(float(gg.size()))
	var n := all.size()
	if n < 3:
		return {"erro": "amostra total insuficiente"}
	var ranks := _rank_all(all)
	var h := 0.0
	var pos := 0
	for g in grupos:
		var gg: PackedFloat64Array = g
		var rsum := 0.0
		for i in range(pos, pos + gg.size()):
			rsum += ranks[i]
		pos += gg.size()
		h += rsum * rsum / float(gg.size())
	h = 12.0 / (float(n) * float(n + 1)) * h - 3.0 * float(n + 1)
	var counts := {}
	for x in all:
		var kk := snappedf(x, 0.00001)
		counts[kk] = int(counts.get(kk, 0)) + 1
	var tie_sum := 0.0
	for kk in counts:
		var t := float(counts[kk])
		if t > 1.0:
			tie_sum += t * t * t - t
	var corr := 1.0 - tie_sum / (float(n * n * n) - float(n))
	if corr > 0.0:
		h /= corr
	var df := float(k - 1)
	var p := chi2_p_value(h, df)
	return {"teste": "Kruskal-Wallis", "H": h, "gl": df, "p": p, "k": k, "n": n}


## Qui-quadrado de independencia. tabela: Array de PackedFloat64Array (linhas).
static func chi2_independence(tabela: Array, yates: bool = true) -> Dictionary:
	var lin := tabela.size()
	if lin < 2:
		return {"erro": "tabela invalida"}
	var col := 0
	for row in tabela:
		var r: PackedFloat64Array = row
		if col == 0:
			col = r.size()
		elif r.size() != col:
			return {"erro": "linhas com tamanhos diferentes"}
	if col < 2:
		return {"erro": "tabela invalida"}
	var tot_lin := PackedFloat64Array()
	tot_lin.resize(lin)
	var tot_col := PackedFloat64Array()
	tot_col.resize(col)
	var n := 0.0
	for i in range(lin):
		var r: PackedFloat64Array = tabela[i]
		for j in range(col):
			tot_lin[i] += r[j]
			tot_col[j] += r[j]
			n += r[j]
	if n == 0.0:
		return {"erro": "tabela vazia"}
	var chi2 := 0.0
	var min_esperado := INF
	var n_baixos := 0
	for i in range(lin):
		var r: PackedFloat64Array = tabela[i]
		for j in range(col):
			var e := tot_lin[i] * tot_col[j] / n
			min_esperado = minf(min_esperado, e)
			if e < 5.0:
				n_baixos += 1
			var diff := absf(r[j] - e)
			if yates and lin == 2 and col == 2:
				diff = maxf(0.0, diff - 0.5)
			if e > 0.0:
				chi2 += diff * diff / e
	var df := float((lin - 1) * (col - 1))
	var p := chi2_p_value(chi2, df)
	var v := sqrt(chi2 / (n * minf(float(lin - 1), float(col - 1))))
	return {
		"teste": "Qui-quadrado de Pearson" + (" (Yates)" if yates and lin == 2 and col == 2 else ""),
		"chi2": chi2, "gl": df, "p": p, "n": n,
		"v_cramer": v, "min_esperado": min_esperado, "celulas_abaixo_5": n_baixos,
		"recomenda_fisher": (lin == 2 and col == 2 and min_esperado < 5.0),
		"totais_linha": tot_lin, "totais_coluna": tot_col,
	}


## Teste exato de Fisher (tabela 2x2) por log-fatoriais.
static func fisher_exact(a: int, b: int, c: int, d: int) -> Dictionary:
	var n := a + b + c + d
	if n == 0:
		return {"erro": "tabela vazia"}
	var r1 := a + b
	var c1 := a + c
	var ln_n := ln_factorial(n)
	var p_obs := exp(ln_factorial(r1) + ln_factorial(n - r1) + ln_factorial(c1) + ln_factorial(n - c1)
		- ln_n - ln_factorial(a) - ln_factorial(b) - ln_factorial(c) - ln_factorial(d))
	var p := 0.0
	var lo := maxi(0, r1 + c1 - n)
	var hi := mini(r1, c1)
	for x in range(lo, hi + 1):
		var y := r1 - x
		var z := c1 - x
		var w := n - x - y - z
		if w < 0:
			continue
		var px := exp(ln_factorial(r1) + ln_factorial(n - r1) + ln_factorial(c1) + ln_factorial(n - c1)
			- ln_n - ln_factorial(x) - ln_factorial(y) - ln_factorial(z) - ln_factorial(w))
		if px <= p_obs * (1.0 + 1e-9):
			p += px
	return {
		"teste": "Exato de Fisher", "p": minf(1.0, p), "p_observado": p_obs,
		"odds_ratio": (float(a) * float(d)) / (float(b) * float(c)) if b * c > 0 else INF,
	}


# ============================================================================
# 6. CORRELACAO E REGRESSAO
# ============================================================================

static func pearson(x: PackedFloat64Array, y: PackedFloat64Array) -> Dictionary:
	var n := mini(x.size(), y.size())
	if n < 3:
		return {"erro": "amostra insuficiente"}
	var mx := 0.0
	var my := 0.0
	for i in range(n):
		mx += x[i]
		my += y[i]
	mx /= float(n)
	my /= float(n)
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in range(n):
		var dx := x[i] - mx
		var dy := y[i] - my
		sxy += dx * dy
		sxx += dx * dx
		syy += dy * dy
	if sxx == 0.0 or syy == 0.0:
		return {"erro": "variancia zero"}
	var r := sxy / sqrt(sxx * syy)
	r = clampf(r, -1.0, 1.0)
	var df := float(n - 2)
	var t := r * sqrt(df / maxf(1e-12, 1.0 - r * r))
	var p := t_two_sided_p(t, df)
	return {"r": r, "r2": r * r, "n": n, "t": t, "gl": df, "p": p}


static func spearman(x: PackedFloat64Array, y: PackedFloat64Array) -> Dictionary:
	var n := mini(x.size(), y.size())
	if n < 3:
		return {"erro": "amostra insuficiente"}
	var rx := _rank_all(x)
	var ry := _rank_all(y)
	var pr := pearson(rx, ry)
	if pr.has("erro"):
		return pr
	return {"rho": pr["r"], "n": n, "p": pr["p"], "t": pr["t"], "gl": pr["gl"]}


static func linear_regression(x: PackedFloat64Array, y: PackedFloat64Array) -> Dictionary:
	var n := mini(x.size(), y.size())
	if n < 3:
		return {"erro": "amostra insuficiente"}
	var mx := mean(x)
	var my := mean(y)
	var sxy := 0.0
	var sxx := 0.0
	for i in range(n):
		sxy += (x[i] - mx) * (y[i] - my)
		sxx += (x[i] - mx) * (x[i] - mx)
	if sxx == 0.0:
		return {"erro": "variancia zero em X"}
	var b1 := sxy / sxx
	var b0 := my - b1 * mx
	var sq_res := 0.0
	var sq_tot := 0.0
	for i in range(n):
		var yhat := b0 + b1 * x[i]
		sq_res += (y[i] - yhat) * (y[i] - yhat)
		sq_tot += (y[i] - my) * (y[i] - my)
	var df := float(n - 2)
	var s2 := sq_res / df
	var se_b1 := sqrt(s2 / sxx)
	var t := b1 / se_b1 if se_b1 > 0.0 else 0.0
	var p := t_two_sided_p(t, df)
	var tc := t_quantile(0.975, df)
	var r2 := 1.0 - sq_res / sq_tot if sq_tot > 0.0 else 0.0
	var se_b0 := sqrt(s2 * (1.0 / float(n) + mx * mx / sxx))
	return {
		"b0": b0, "b1": b1, "se_b1": se_b1, "t": t, "gl": df, "p": p,
		"ic95_b1": [b1 - tc * se_b1, b1 + tc * se_b1],
		"se_b0": se_b0, "r2": r2, "r2_ajustado": 1.0 - (1.0 - r2) * float(n - 1) / df,
		"n": n, "sq_res": sq_res, "sq_tot": sq_tot, "rmse": sqrt(s2),
	}


## Regressao logistica binaria por descida de gradiente (com regularizacao L2).
## Retorna coeficientes, acuracias e matriz de confusao no conjunto de teste.
static func logistic_regression(X: Array, y: PackedFloat64Array, taxa: float = 0.6,
		epocas: int = 900, l2: float = 0.002, seed: int = 12345,
		test_frac: float = 0.3) -> Dictionary:
	var n := X.size()
	if n < 20:
		return {"erro": "amostra insuficiente (minimo 20)"}
	var p := (X[0] as PackedFloat64Array).size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var idx: Array = []
	for i in range(n):
		idx.append(i)
	# embaralha Fisher-Yates
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	var n_test := maxi(1, int(round(float(n) * test_frac)))
	var train_idx: Array = idx.slice(0, n - n_test)
	var test_idx: Array = idx.slice(n - n_test)

	var w := PackedFloat64Array()
	w.resize(p)
	for i in range(p):
		w[i] = 0.0
	var b := 0.0
	var n_train := train_idx.size()
	for _e in range(epocas):
		var gw := PackedFloat64Array()
		gw.resize(p)
		var gb := 0.0
		for i in train_idx:
			var xi: PackedFloat64Array = X[i]
			var z := b
			for k in range(p):
				z += w[k] * xi[k]
			var pr := 1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0)))
			var err := pr - y[i]
			for k in range(p):
				gw[k] += err * xi[k]
			gb += err
		for k in range(p):
			w[k] -= taxa * (gw[k] / float(n_train) + l2 * w[k])
		b -= taxa * gb / float(n_train)

	var acc_train := _logistic_metrics(X, y, train_idx, w, b)
	var acc_test := _logistic_metrics(X, y, test_idx, w, b)
	return {
		"pesos": w, "bias": b, "n": n, "n_treino": n_train, "n_teste": n_test,
		"treino": acc_train, "teste": acc_test, "p": p,
	}


static func _logistic_metrics(X: Array, y: PackedFloat64Array, idx: Array,
		w: PackedFloat64Array, b: float) -> Dictionary:
	var tp := 0
	var fp := 0
	var tn := 0
	var fn := 0
	var scores: Array = []
	var reais: Array = []
	for i in idx:
		var xi: PackedFloat64Array = X[i]
		var z := b
		for k in range(w.size()):
			z += w[k] * xi[k]
		var pr := 1.0 / (1.0 + exp(-clampf(z, -30.0, 30.0)))
		var pred := 1 if pr >= 0.5 else 0
		var real := int(y[i])
		scores.append(pr)
		reais.append(real)
		if pred == 1 and real == 1:
			tp += 1
		elif pred == 1 and real == 0:
			fp += 1
		elif pred == 0 and real == 0:
			tn += 1
		else:
			fn += 1
	var total := maxi(tp + fp + tn + fn, 1)
	var sens := float(tp) / float(maxi(tp + fn, 1))
	var espec := float(tn) / float(maxi(tn + fp, 1))
	return {
		"acuracia": float(tp + tn) / float(total),
		"sensibilidade": sens, "especificidade": espec,
		"ppv": float(tp) / float(maxi(tp + fp, 1)),
		"npv": float(tn) / float(maxi(tn + fn, 1)),
		"tp": tp, "fp": fp, "tn": tn, "fn": fn,
		"auc": roc_auc(scores, reais),
	}


## Area sob a curva ROC por trapezios.
static func roc_auc(scores: Array, labels: Array) -> float:
	var n := scores.size()
	if n == 0:
		return 0.0
	var pares: Array = []
	for i in range(n):
		pares.append([float(scores[i]), int(labels[i])])
	pares.sort_custom(func(a, b): return a[0] > b[0])
	var pos := 0
	var neg := 0
	for p in pares:
		if p[1] == 1:
			pos += 1
		else:
			neg += 1
	if pos == 0 or neg == 0:
		return 0.5
	var auc := 0.0
	var tp := 0.0
	var fp := 0.0
	var prev_tp := 0.0
	var prev_fp := 0.0
	var i := 0
	while i < n:
		var j := i
		while j < n and is_equal_approx(pares[j][0], pares[i][0]):
			if pares[j][1] == 1:
				tp += 1.0
			else:
				fp += 1.0
			j += 1
		auc += (fp - prev_fp) * (tp + prev_tp) * 0.5
		prev_tp = tp
		prev_fp = fp
		i = j
	auc /= float(pos * neg)
	return auc


## Curva ROC para plotagem: retorna arrays de FPR e TPR.
static func roc_curve(scores: Array, labels: Array) -> Dictionary:
	var n := scores.size()
	var pares: Array = []
	for i in range(n):
		pares.append([float(scores[i]), int(labels[i])])
	pares.sort_custom(func(a, b): return a[0] > b[0])
	var pos := 0
	var neg := 0
	for p in pares:
		if p[1] == 1:
			pos += 1
		else:
			neg += 1
	var fpr := PackedFloat64Array([0.0])
	var tpr := PackedFloat64Array([0.0])
	var tp := 0.0
	var fp := 0.0
	for p in pares:
		if p[1] == 1:
			tp += 1.0
		else:
			fp += 1.0
		fpr.append(fp / float(maxi(neg, 1)))
		tpr.append(tp / float(maxi(pos, 1)))
	fpr.append(1.0)
	tpr.append(1.0)
	return {"fpr": fpr, "tpr": tpr}


# ============================================================================
# 7. MEDIDAS DE ASSOCIACAO EPIDEMIOLOGICA
# ============================================================================

static func odds_ratio(a: int, b: int, c: int, d: int) -> Dictionary:
	var orv := (float(a) * float(d)) / (float(b) * float(c)) if b * c > 0 else INF
	var se := sqrt(1.0 / float(maxi(a, 1)) + 1.0 / float(maxi(b, 1)) + 1.0 / float(maxi(c, 1)) + 1.0 / float(maxi(d, 1)))
	var lo := exp(log(maxf(orv, 1e-9)) - 1.96 * se)
	var hi := exp(log(maxf(orv, 1e-9)) + 1.96 * se)
	return {"or": orv, "ic95": [lo, hi], "se_log": se}


static func relative_risk(a: int, n1: int, c: int, n2: int) -> Dictionary:
	var r1 := float(a) / float(maxi(n1, 1))
	var r2 := float(c) / float(maxi(n2, 1))
	var rr := r1 / r2 if r2 > 0.0 else INF
	var se := sqrt(1.0 / float(maxi(a, 1)) - 1.0 / float(maxi(n1, 1)) + 1.0 / float(maxi(c, 1)) - 1.0 / float(maxi(n2, 1)))
	var lo := exp(log(maxf(rr, 1e-9)) - 1.96 * se)
	var hi := exp(log(maxf(rr, 1e-9)) + 1.96 * se)
	return {"rr": rr, "risco_expostos": r1, "risco_nao_expostos": r2, "ic95": [lo, hi],
		"rar": r1 - r2, "nnt": (1.0 / (r1 - r2)) if not is_equal_approx(r1, r2) else INF}


## Intervalo de confianca de Wald para uma proporcao.
static func proportion_ci(k: int, n: int, confianca: float = 0.95) -> Dictionary:
	if n <= 0:
		return {"p": NAN, "ic95": [NAN, NAN]}
	var p := float(k) / float(n)
	var z := normal_quantile(1.0 - (1.0 - confianca) * 0.5)
	var se := sqrt(p * (1.0 - p) / float(n))
	return {"p": p, "se": se, "ic95": [maxf(0.0, p - z * se), minf(1.0, p + z * se)]}


# ============================================================================
# 8. AMOSTRAGEM E DIMENSIONAMENTO
# ============================================================================

## Tamanho amostral para proporcao com populacao finita.
static func sample_size_proportion(N: int, p_hat: float, erro: float,
		confianca: float = 0.95) -> Dictionary:
	if erro <= 0.0:
		return {"erro": "erro amostral deve ser > 0"}
	var z := normal_quantile(1.0 - (1.0 - confianca) * 0.5)
	var n0 := z * z * p_hat * (1.0 - p_hat) / (erro * erro)
	var n := n0
	if N > 0:
		n = (float(N) * n0) / (float(N) + n0 - 1.0)
	return {"n0": n0, "n": int(ceil(n)), "z": z, "N": N, "p": p_hat, "erro": erro}


## Tamanho amostral para media (desvio-piloto conhecido).
static func sample_size_mean(N: int, s: float, erro: float,
		confianca: float = 0.95) -> Dictionary:
	if erro <= 0.0 or s <= 0.0:
		return {"erro": "parametros invalidos"}
	var z := normal_quantile(1.0 - (1.0 - confianca) * 0.5)
	var n0 := pow(z * s / erro, 2.0)
	var n := n0
	if N > 0:
		n = (float(N) * n0) / (float(N) + n0 - 1.0)
	return {"n0": n0, "n": int(ceil(n)), "z": z, "N": N, "s": s, "erro": erro}


static func sample_simple_random(ids: PackedInt32Array, n: int, seed: int = 0) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 20261104
	var pool: Array = []
	for i in ids:
		pool.append(i)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var out := PackedInt32Array()
	for i in range(mini(n, pool.size())):
		out.append(pool[i])
	return out


static func sample_systematic(ids: PackedInt32Array, n: int, seed: int = 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	if n <= 0 or ids.is_empty():
		return out
	var k := maxi(1, ids.size() / n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 20261104
	var start := rng.randi_range(0, k - 1)
	var i := start
	while i < ids.size() and out.size() < n:
		out.append(ids[i])
		i += k
	return out


## Estratificada proporcional: estratos = {nome: PackedInt32Array de ids}.
static func sample_stratified(estratos: Dictionary, n: int, seed: int = 0,
		proporcional: bool = true) -> Dictionary:
	var out := {}
	var total := 0
	for k in estratos:
		total += (estratos[k] as PackedInt32Array).size()
	if total == 0:
		return out
	var usado := 0
	var chaves: Array = estratos.keys()
	chaves.sort()
	for i in range(chaves.size()):
		var k: String = chaves[i]
		var ids: PackedInt32Array = estratos[k]
		var quota: int
		if i == chaves.size() - 1:
			quota = maxi(1, n - usado)
		else:
			quota = maxi(1, int(round(float(n) * float(ids.size()) / float(total))))
		quota = mini(quota, ids.size())
		usado += quota
		out[k] = sample_simple_random(ids, quota, seed + i)
	return out


# ============================================================================
# 9. UTILITARIOS
# ============================================================================

static func z_score(x: float, mu: float, sigma: float) -> float:
	if sigma == 0.0:
		return 0.0
	return (x - mu) / sigma


static func clamp01(x: float) -> float:
	return clampf(x, 0.0, 1.0)


## Formata numero com separador de milhar pt-BR.
static func fmt(x: float, decimals: int = 2) -> String:
	if is_nan(x):
		return "NA"
	if is_inf(x):
		return "inf" if x > 0.0 else "-inf"
	var neg := x < 0.0
	var s := ("%." + str(decimals) + "f") % absf(x)
	var parts := s.split(".")
	var inteiro := parts[0]
	var out := ""
	var count := 0
	for i in range(inteiro.length() - 1, -1, -1):
		out = inteiro[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	if parts.size() > 1:
		out += "," + parts[1]
	return ("-" if neg else "") + out


## Formata p-valor no padrao cientifico.
static func fmt_p(p: float) -> String:
	if is_nan(p):
		return "NA"
	if p < 0.001:
		return "< 0,001"
	return ("%.3f" % p).replace(".", ",")


static func interpret_p(p: float, alfa: float = 0.05) -> String:
	if is_nan(p):
		return "p-valor indisponivel"
	if p < alfa:
		return "Rejeita-se H0 (p < alfa): evidencia de diferenca/associacao."
	return "Nao se rejeita H0 (p >= alfa): sem evidencia suficiente."


static func interpret_skewness(g1: float) -> String:
	if is_nan(g1):
		return "indisponivel"
	if absf(g1) < 0.15:
		return "aproximadamente simetrica"
	if g1 > 0.0:
		return "assimetrica positiva (cauda a direita)"
	return "assimetrica negativa (cauda a esquerda)"


static func interpret_kurtosis(g2: float) -> String:
	if is_nan(g2):
		return "indisponivel"
	if absf(g2) < 0.15:
		return "mesocurtica (proxima da normal)"
	if g2 > 0.0:
		return "leptocurtica (picos mais altos)"
	return "platicurtica (mais achatada)"
