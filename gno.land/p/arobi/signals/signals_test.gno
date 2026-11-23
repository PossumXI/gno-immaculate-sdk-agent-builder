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
