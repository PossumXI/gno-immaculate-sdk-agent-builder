package signals

import "testing"

func TestKalmanRWGainFixedAndTracker(t *testing.T) {
	// For q = r = 1.0 (Scale), exact Riccati steady-state gain:
	// P^+ = (1 + sqrt(5))/2 = 1.6180339887..., K* = P^+ / (P^+ + 1) = (sqrt(5)-1)/2 = 0.6180339887...
	kGolden, err := KalmanRWGainFixed(Scale, Scale)
	if err != nil {
		t.Fatalf("KalmanRWGainFixed(1,1) err: %v", err)
	}
	if Abs64(kGolden-618034) > 2 {
		t.Fatalf("expected golden-ratio gain ~618034, got %d", kGolden)
	}

	// For q = 0.01, r = 1.0, K* = (-0.01 + sqrt(0.0401)) / 2? Wait:
	// P^+ = (0.01 + sqrt(0.0001 + 0.04))/2 = (0.01 + 0.20024984)/2 = 0.10512492
	// K* = 0.10512492 / 1.10512492 = 0.09512492 -> 95125
	kLow, err := KalmanRWGainFixed(10000, Scale)
	if err != nil {
		t.Fatalf("KalmanRWGainFixed(0.01,1) err: %v", err)
	}
	if Abs64(kLow-95125) > 2 {
		t.Fatalf("expected low-SNR gain ~95125, got %d", kLow)
	}

	tr, err := NewKalmanRWTracker(100000, Scale)
	if err != nil {
		t.Fatalf("NewKalmanRWTracker err: %v", err)
	}
	st0, inn0 := tr.Update(100 * Scale)
	if st0 != 100*Scale || inn0 != 0 || tr.Steps() != 1 {
		t.Fatalf("unexpected initial update: st=%d inn=%d steps=%d", st0, inn0, tr.Steps())
	}
	st1, inn1 := tr.Update(110 * Scale)
	if inn1 != 10*Scale || st1 <= 100*Scale || st1 >= 110*Scale {
		t.Fatalf("expected damped step in (100,110), got st=%d inn=%d", st1, inn1)
	}
	if _, err := KalmanRWGainFixed(0, Scale); err == nil {
		t.Fatal("expected error for non-positive variance")
	}
}

func TestHubnessNormalizeFixedSuppressesUniversalHub(t *testing.T) {
	// Four topic queries drawn from the query distribution (each has a topic peak + shared floor)
	// plus one universal hub sitting near the centroid of all queries.
	q0, _ := UnitNormalizeFixed([]int64{620000, 320000, 320000, 320000})
	q1, _ := UnitNormalizeFixed([]int64{320000, 620000, 320000, 320000})
	q2, _ := UnitNormalizeFixed([]int64{320000, 320000, 620000, 320000})
	q3, _ := UnitNormalizeFixed([]int64{320000, 320000, 320000, 620000})
	cal := [][]int64{q0, q1, q2, q3}

	// Specific target sits strongly on axis 0; universal hub sits at (0.5, 0.5, 0.5, 0.5).
	target, _ := UnitNormalizeFixed([]int64{920000, 120000, 120000, 120000})
	hub, _ := UnitNormalizeFixed([]int64{500000, 500000, 500000, 500000})
	testQuery, _ := UnitNormalizeFixed([]int64{600000, 330000, 330000, 330000})

	// Raw cosine lets the universal hub beat the axis-0 target on a noisy topic-0 query!
	rawTarget, _ := CosineFixed(testQuery, target)
	rawHub, _ := CosineFixed(testQuery, hub)
	if rawHub <= rawTarget {
		t.Fatalf("expected universal hub to outscore raw cosine: hub=%d target=%d", rawHub, rawTarget)
	}

	// Hubness z-score normalization suppresses the universal hub (z ~ 0) and recovers the true target!
	statsTarget, err := FitHubStatsFixed(cal, target, -1, 50000)
	if err != nil {
		t.Fatalf("FitHubStatsFixed target err: %v", err)
	}
	statsHub, err := FitHubStatsFixed(cal, hub, -1, 50000)
	if err != nil {
		t.Fatalf("FitHubStatsFixed hub err: %v", err)
	}
	zTarget, _ := HubNormalizeScoreFixed(testQuery, target, statsTarget, 50000)
	zHub, _ := HubNormalizeScoreFixed(testQuery, hub, statsHub, 50000)
	if zTarget <= zHub {
		t.Fatalf("expected hub-normalized target (%d) > hub (%d)", zTarget, zHub)
	}
}
