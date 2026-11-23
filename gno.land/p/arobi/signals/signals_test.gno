package signals

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestFixedPointMathAccuracy(t *testing.T) {
	uassert.Equal(t, int64(2500000), MulFixed(5000000, 500000)) // 5.0 * 0.5 = 2.5
	uassert.Equal(t, int64(-3750000), MulFixed(-1500000, 2500000))
	uassert.Equal(t, int64(2000000), DivFixed(5000000, 2500000)) // 5.0 / 2.5 = 2.0
	uassert.Equal(t, int64(1414213), SqrtFixed(2*Scale))         // sqrt(2) ~= 1.414213
	uassert.Equal(t, int64(3000000), MedianFixed([]int64{9000000, 1000000, 3000000, 5000000, 2000000}))
}

func TestRobustSmootherRemovesSpikesAndMatchesBatchCausally(t *testing.T) {
	// Clean baseline around 10.0 with a single +100.0 (+10sigma) adversarial spike at index 5.
	series := []int64{
		10000000, 10100000, 9900000, 10050000, 9950000,
		110000000, // +100.0 spike!
		10020000, 9980000, 10010000, 9990000,
	}

	batch, replaced, err := BatchRobustSmooth(series, 5, 3*Scale, 200000)
	uassert.NoError(t, err)
	uassert.True(t, replaced >= 1)

	// Streaming must match batch bit-for-bit on every sample.
	sm, err := NewRobustSmoother(5, 3*Scale, 200000)
	uassert.NoError(t, err)
	for i, v := range series {
		y, outlier, ev := sm.Update(v)
		uassert.Equal(t, batch[i], y)
		if i == 5 {
			uassert.True(t, outlier)
			uassert.True(t, ev.Alarm)
			// Smoothed value stays near 10.0, completely rejecting the 110.0 spike!
			uassert.True(t, Abs64(y-10000000) < 200000)
		}
	}

	// Causality check: modifying future sample 8 must never alter outputs 0..7.
	seriesMod := make([]int64, len(series))
	copy(seriesMod, series)
	seriesMod[8] = 999000000
	batchMod, _, err := BatchRobustSmooth(seriesMod, 5, 3*Scale, 200000)
	uassert.NoError(t, err)
	for i := 0; i < 8; i++ {
		uassert.Equal(t, batch[i], batchMod[i])
	}
}

func TestDriftDetectorsCatchShiftWhileHampelCusumIgnoresSingleSpike(t *testing.T) {
	// Quiet baseline around 10.0 with SD ~= 1.0.
	quiet := []int64{
		9000000, 11000000, 9500000, 10500000, 10000000,
		9200000, 10800000, 9600000, 10400000, 10000000,
		9100000, 10900000, 9700000, 10300000, 10000000,
	}
	base, err := BaselineFromSlice(quiet)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(10000000), base.MeanFixed)
	uassert.True(t, base.SDFixed > 500000 && base.SDFixed < 900000)

	// 1. Single isolated +12sigma spike trips raw CUSUM, but HampelCusum clamps it with ZERO false alarm!
	rawCu, err := NewCusum(base, 5*Scale, Scale)
	uassert.NoError(t, err)
	hc, err := NewHampelCusum(base, 5*Scale, Scale, 5, 3*Scale)
	uassert.NoError(t, err)

	spikyQuiet := []int64{10000000, 10100000, 9900000, 10050000, 22000000, 10000000, 9950000}
	rawTripped := false
	hcTripped := false
	for _, x := range spikyQuiet {
		if a, _, _ := rawCu.Update(x); a {
			rawTripped = true
		}
		if a, _, _, _ := hc.Update(x); a {
			hcTripped = true
		}
	}
	uassert.True(t, rawTripped)
	uassert.False(t, hcTripped)
	uassert.True(t, hc.SpikesClamped() >= 1)

	// 2. Sustained +3.5sigma regime shift MUST trigger both HampelCusum and Page-Hinkley quickly!
	// Warm up Page-Hinkley on quiet baseline samples first (Page-Hinkley tracks shift vs its running mean).
	ph, err := NewPageHinkley(base, 5*Scale, 500000)
	uassert.NoError(t, err)
	for _, qx := range quiet {
		ph.Update(qx)
	}
	hcAlarmAt := -1
	phAlarmAt := -1
	for step := 0; step < 12; step++ {
		val := int64(12500000) // sustained +3.5sigma shift
		if a, _, _, _ := hc.Update(val); a && hcAlarmAt < 0 {
			hcAlarmAt = step
		}
		if a, _, _ := ph.Update(val); a && phAlarmAt < 0 {
			phAlarmAt = step
		}
	}
	uassert.True(t, hcAlarmAt >= 0 && hcAlarmAt <= 6)
	uassert.True(t, phAlarmAt >= 0 && phAlarmAt <= 6)
}

func TestSphericalCoherenceOrderInvarianceAndPoisoningDetection(t *testing.T) {
	// Aligned coherent session embeddings.
	coherent := [][]int64{
		{980000, 199000, 10000, 0},
		{990000, 141000, 15000, 0},
		{975000, 220000, 5000, 0},
		{985000, 170000, 12000, 0},
	}
	// Permuted order MUST produce exact bit-identical scores & input digests!
	reordered := [][]int64{coherent[3], coherent[1], coherent[0], coherent[2]}

	r1, err := MeanResultantLengthFixed(coherent)
	uassert.NoError(t, err)
	r2, err := MeanResultantLengthFixed(reordered)
	uassert.NoError(t, err)
	uassert.Equal(t, r1, r2)
	uassert.True(t, r1 > 990000) // > 0.99

	c1, err := MeanPairwiseCosineFixed(coherent)
	uassert.NoError(t, err)
	c2, err := MeanPairwiseCosineFixed(reordered)
	uassert.NoError(t, err)
	uassert.Equal(t, c1, c2)
	uassert.True(t, c1 > 980000) // > 0.98

	// Poisoned / mixed cross-session embeddings (orthogonal & opposing).
	poisoned := [][]int64{
		{1000000, 0, 0, 0},
		{0, 1000000, 0, 0},
		{0, 0, 1000000, 0},
		{-1000000, 0, 0, 0},
	}
	passOk, scoreOk, evOk, err := CoherenceGate(coherent, 750000, false)
	uassert.NoError(t, err)
	uassert.True(t, passOk)
	uassert.False(t, evOk.Alarm)
	uassert.True(t, scoreOk > 950000)

	passBad, scoreBad, evBad, err := CoherenceGate(poisoned, 750000, false)
	uassert.NoError(t, err)
	uassert.False(t, passBad)
	uassert.True(t, evBad.Alarm)
	uassert.True(t, scoreBad < 500000)
}

func TestGeometricMedianResistsCoordinatedOutlierCluster(t *testing.T) {
	// 5 clean vectors near +e0 + 2 coordinated adversarial vectors near -e0 (28.6% poison).
	batch := [][]int64{
		{990000, 141000, 0, 0},
		{995000, 100000, 0, 0},
		{985000, 172000, 0, 0},
		{992000, 126000, 0, 0},
		{988000, 154000, 0, 0},
		{-900000, 435000, 0, 0},
		{-920000, 391000, 0, 0},
	}
	gm, err := GeometricMedianFixed(batch, 8)
	uassert.NoError(t, err)
	uassert.True(t, gm[0] > 900000)

	// Strictly order-invariant under reversed batch order.
	rev := make([][]int64, len(batch))
	for i := range batch {
		rev[i] = batch[len(batch)-1-i]
	}
	gmRev, err := GeometricMedianFixed(rev, 8)
	uassert.NoError(t, err)
	for j := range gm {
		uassert.Equal(t, gm[j], gmRev[j])
	}
}

func TestGeometricMedianExact180CancellationIsOrderInvariant(t *testing.T) {
	// Exact 180-degree symmetric cancellation: sum == 0.
	// Medoid initialization + canonical SHA-256 tie-break guarantees zero order divergence (E7a).
	u := []int64{Scale, 0, 0, 0}
	neg := []int64{-Scale, 0, 0, 0}
	b1 := [][]int64{u, u, neg, neg}
	b2 := [][]int64{neg, u, neg, u}
	b3 := [][]int64{neg, neg, u, u}

	gm1, err := GeometricMedianFixed(b1, 8)
	uassert.NoError(t, err)
	gm2, err := GeometricMedianFixed(b2, 8)
	uassert.NoError(t, err)
	gm3, err := GeometricMedianFixed(b3, 8)
	uassert.NoError(t, err)
	for j := range gm1 {
		uassert.Equal(t, gm1[j], gm2[j])
		uassert.Equal(t, gm1[j], gm3[j])
	}

	// AntipodalSplitGate catches balanced 180-degree split-brain (E7b) with 0 false alarms on clean sets.
	passSplit, fracSplit, evSplit, err := AntipodalSplitGate(b1, -500000, 100000)
	uassert.NoError(t, err)
	uassert.False(t, passSplit)
	uassert.True(t, evSplit.Alarm)
	uassert.True(t, fracSplit >= 500000) // 4/6 pairs are antipodal = 66.6%

	clean := [][]int64{
		{990000, 141000, 0, 0},
		{995000, 100000, 0, 0},
		{985000, 172000, 0, 0},
	}
	passClean, fracClean, evClean, err := AntipodalSplitGate(clean, -500000, 100000)
	uassert.NoError(t, err)
	uassert.True(t, passClean)
	uassert.False(t, evClean.Alarm)
	uassert.Equal(t, int64(0), fracClean)
}

func TestOpacityAwareHampelCusumCatchesPeriod6DrainAndIgnoresSingleSpike(t *testing.T) {
	base := Baseline{MeanFixed: 100 * Scale, SDFixed: 15 * Scale}
	oa, err := NewOpacityAwareHampelCusum(base, 5*Scale, Scale, 5, 3*Scale, 4*Scale, 24, 3)
	uassert.NoError(t, err)

	// 1. Single isolated +10sigma spike: clamped, clipCount == 1 < 3 -> NO alarm!
	for i := 0; i < 12; i++ {
		val := int64(100) * Scale
		if i == 6 {
			val = 250 * Scale // +10sigma transient spike
		}
		alarm, _, _, _ := oa.Update(val)
		uassert.False(t, alarm)
	}
	uassert.Equal(t, 1, oa.ClipCount())

	// 2. Reset and inject period-6 filter-evading bursts (+6sigma every 6th step, P=6 > w=5).
	oa.Reset()
	trippedOpacity := false
	for i := 0; i < 24; i++ {
		val := int64(100) * Scale
		if i >= 5 && (i-5)%6 == 0 {
			val = 190 * Scale // +6sigma burst
		}
		alarm, _, ch, ev := oa.Update(val)
		if alarm && (ch == "opacity_innovation_channel" || ch == "dual_cusum_and_opacity") {
			trippedOpacity = true
			uassert.True(t, ev.Alarm)
		}
	}
	uassert.True(t, trippedOpacity)
}

func TestCommonAverageReferenceDebiasFixedRemovesAnisotropicCone(t *testing.T) {
	// Shared anisotropic cone along e0 (weight 0.78); clean along +e1, poison along -e1.
	cone := []int64{Scale, 0, 0, 0}
	cleanRaw := []int64{780000, 625780, 0, 0}
	poisonRaw := []int64{780000, -625780, 0, 0}

	cleanDeb, err := CommonAverageReferenceDebiasFixed(cleanRaw, cone, 780000)
	uassert.NoError(t, err)
	poisonDeb, err := CommonAverageReferenceDebiasFixed(poisonRaw, cone, 780000)
	uassert.NoError(t, err)
	// After CAR cone subtraction, clean points along +e1 and poison points along -e1 (cos == -1)!
	uassert.True(t, cleanDeb[1] > 990000)
	uassert.True(t, poisonDeb[1] < -990000)
}

func TestWildbergerRationalQuadranceSpreadYoudenAndAR1Prewhitening(t *testing.T) {
	// 1. Wildberger Rational Quadrance & Spread (Experiment E10): zero ISqrt64, exact sign.
	u := []int64{300000, 400000, 0, 0} // norm 500,000
	v := []int64{400000, 300000, 0, 0} // dot = 24, cos = 24/25 = 0.96 -> cos^2 = 0.9216 = 921,600
	c2, err := SignedQuadranceCosSqFixed(u, v)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(921600), c2)

	sp, err := RationalSpreadFixed(u, v)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(78400), sp) // 1 - 0.9216 = 0.0784

	passHi, _, err := RationalCosGateFixed(u, v, 950000) // 0.96 >= 0.95 -> true
	uassert.NoError(t, err)
	uassert.True(t, passHi)
	passTooHi, _, err := RationalCosGateFixed(u, v, 970000) // 0.96 >= 0.97 -> false
	uassert.NoError(t, err)
	uassert.False(t, passTooHi)

	// 2. Youden-J optimal threshold & exact Mann-Whitney ROC-AUC (Experiment E11b).
	cleanSc := []int64{820000, 880000, 790000, 910000, 850000}
	attackSc := []int64{120000, 310000, 240000, 410000, 190000}
	bestT, jVal, auc, err := CalibrateThresholdYoudenFixed(cleanSc, attackSc)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(Scale), jVal)
	uassert.Equal(t, int64(Scale), auc)
	uassert.True(t, bestT > 410000 && bestT <= 790000)

	// 3. AR(1) lag estimation & prewhitened Hampel-CUSUM (Experiment E11a).
	quiet := []int64{
		100 * Scale, 108 * Scale, 112 * Scale, 109 * Scale, 103 * Scale,
		96 * Scale, 92 * Scale, 95 * Scale, 101 * Scale, 107 * Scale,
		110 * Scale, 106 * Scale,
	}
	base, rho, err := EstimateAR1Fixed(quiet)
	uassert.NoError(t, err)
	uassert.True(t, rho > 200000) // positive lag-1 autocorrelation
	arDet, err := NewAR1PrewhitenedHampelCusum(base, rho, 4*Scale, Scale, 5, 3*Scale, 4*Scale, 24, 3)
	uassert.NoError(t, err)
	alarmed := false
	for i := 0; i < 12; i++ {
		al, _, _, _ := arDet.Update(base.MeanFixed + 3*base.SDFixed)
		if al {
			alarmed = true
		}
	}
	uassert.True(t, alarmed)
}

func TestBenchWildbergerRationalCosGate100PairsGas(t *testing.T) {
	u := []int64{312450, 418920, -192830, 512340, 223110, -334120, 128900, 441230}
	v := []int64{298120, 391230, -181120, 489120, 210900, -310110, 119800, 430110}
	for i := 0; i < 100; i++ {
		v[0] = 298120 + int64(i)*100
		ok, _, err := RationalCosGateFixed(u, v, 550000)
		uassert.NoError(t, err)
		uassert.True(t, ok)
	}
}

func TestBenchClassicalUnitNormalizeCos100PairsGas(t *testing.T) {
	u := []int64{312450, 418920, -192830, 512340, 223110, -334120, 128900, 441230}
	v := []int64{298120, 391230, -181120, 489120, 210900, -310110, 119800, 430110}
	for i := 0; i < 100; i++ {
		v[0] = 298120 + int64(i)*100
		uu, err := UnitNormalizeFixed(u)
		uassert.NoError(t, err)
		vv, err := UnitNormalizeFixed(v)
		uassert.NoError(t, err)
		var dot int64
		for j := range uu {
			dot += MulFixed(uu[j], vv[j])
		}
		uassert.True(t, dot >= 550000)
	}
}
