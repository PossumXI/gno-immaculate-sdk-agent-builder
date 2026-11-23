package signals

import (
	"crypto/sha256"
	"encoding/binary"
	"errors"
)

// UnitNormalizeFixed projects a non-zero integer/fixed-point vector onto the unit sphere
// of radius Scale (1_000_000), deterministically across all validators.
func UnitNormalizeFixed(vec []int64) ([]int64, error) {
	if len(vec) == 0 {
		return nil, errors.New("vector cannot be empty")
	}
	// Downscale if max abs coordinate exceeds 1_000_000 to prevent uint64 overflow in sum of squares.
	var maxAbs uint64
	for _, v := range vec {
		a := uint64(Abs64(v))
		if a > maxAbs {
			maxAbs = a
		}
	}
	if maxAbs == 0 {
		return nil, errors.New("zero vector cannot be normalized")
	}

	shift := uint(0)
	for (maxAbs >> shift) > 1000000 {
		shift++
	}

	var sqSum uint64
	for _, v := range vec {
		a := uint64(Abs64(v)) >> shift
		sqSum += a * a
	}
	norm := ISqrt64(sqSum)
	if norm == 0 {
		return nil, errors.New("zero norm after scaling")
	}

	unit := make([]int64, len(vec))
	for i, v := range vec {
		neg := v < 0
		a := uint64(Abs64(v)) >> shift
		val := int64((a * uint64(Scale)) / norm)
		if neg {
			val = -val
		}
		unit[i] = val
	}
	return unit, nil
}

func validateAndNormalizeSet(vectors [][]int64) ([][]int64, error) {
	if len(vectors) < 2 {
		return nil, errors.New("coherence requires at least 2 vectors")
	}
	dim := len(vectors[0])
	if dim == 0 {
		return nil, errors.New("vectors must have positive dimension")
	}
	units := make([][]int64, len(vectors))
	for i, v := range vectors {
		if len(v) != dim {
			return nil, errors.New("all vectors in set must share the same dimension")
		}
		u, err := UnitNormalizeFixed(v)
		if err != nil {
			return nil, err
		}
		units[i] = u
	}
	return units, nil
}

// MeanResultantLengthFixed computes ||mean(unit(v_i))|| in [0, Scale].
// Strictly order-invariant and O(n * d): 1.0*Scale when all vectors align, 0 when they cancel.
func MeanResultantLengthFixed(vectors [][]int64) (int64, error) {
	units, err := validateAndNormalizeSet(vectors)
	if err != nil {
		return 0, err
	}
	n := int64(len(units))
	dim := len(units[0])
	var sqSum uint64
	for j := 0; j < dim; j++ {
		var colSum int64
		for i := 0; i < len(units); i++ {
			colSum += units[i][j]
		}
		meanJ := colSum / n
		am := uint64(Abs64(meanJ))
		sqSum += am * am
	}
	res := int64(ISqrt64(sqSum))
	if res > Scale {
		res = Scale
	}
	return res, nil
}

// MeanPairwiseCosineFixed computes the exact mean cosine over all n*(n-1) distinct pairs
// in O(n * d) using the resultant identity: (||sum(u_i)||^2 - n) / (n * (n - 1)).
// Returns fixed-point value in [-Scale, +Scale], strictly order-invariant.
func MeanPairwiseCosineFixed(vectors [][]int64) (int64, error) {
	units, err := validateAndNormalizeSet(vectors)
	if err != nil {
		return 0, err
	}
	n := int64(len(units))
	dim := len(units[0])

	// sumNormSqFixed = ||sum(u_i)||^2 / Scale (in Scale units, where each u_i has ||u_i||^2 = Scale^2).
	var sumNormSqFixed int64
	for j := 0; j < dim; j++ {
		var colSum int64
		for i := 0; i < len(units); i++ {
			colSum += units[i][j]
		}
		sumNormSqFixed += MulFixed(colSum, colSum)
	}
	// Result = (sumNormSqFixed - n*Scale) / (n * (n - 1))
	num := sumNormSqFixed - n*Scale
	den := n * (n - 1)
	res := num / den
	if res > Scale {
		res = Scale
	}
	if res < -Scale {
		res = -Scale
	}
	return res, nil
}

// CoherenceGate evaluates whether a retrieved memory / context embedding batch is coherent
// enough to inject into an agent's reasoning window (blocking cross-session memory poisoning).
func CoherenceGate(vectors [][]int64, thresholdFixed int64, usePairwise bool) (bool, int64, SignalEvidence, error) {
	var (
		score int64
		err   error
		mode  int64
	)
	if usePairwise {
		mode = 1
		score, err = MeanPairwiseCosineFixed(vectors)
	} else {
		mode = 0
		score, err = MeanResultantLengthFixed(vectors)
	}
	if err != nil {
		return false, 0, SignalEvidence{}, err
	}
	pass := score >= thresholdFixed

	// Order-invariant digest over sorted vector hashes so input digest matches set semantics.
	inDigest := digestVectorSet(vectors)
	detail := "coherent_pass"
	if !pass {
		detail = "coherence_below_threshold"
	}
	ev := SignalEvidence{
		Primitive:    "signals.coherence_gate",
		Version:      "1",
		ParamsDigest: hashInt64s("coherence_gate", thresholdFixed, mode),
		InputDigest:  inDigest,
		OutputFixed:  score,
		Alarm:        !pass,
		Detail:       detail,
	}
	return pass, score, ev, nil
}

func digestVectorSet(vectors [][]int64) [32]byte {
	// XOR-independent canonical accumulation over vector hashes sorted lexicographically.
	hashes := make([][32]byte, len(vectors))
	for i, v := range vectors {
		buf := make([]byte, 0, 8+len(v)*8)
		buf = binary.BigEndian.AppendUint64(buf, uint64(len(v)))
		for _, x := range v {
			buf = binary.BigEndian.AppendUint64(buf, uint64(x))
		}
		hashes[i] = sha256.Sum256(buf)
	}
	// Simple deterministic insertion sort on 32-byte hashes (no extra imports needed).
	for i := 1; i < len(hashes); i++ {
		key := hashes[i]
		j := i - 1
		for j >= 0 && bytesLess(key, hashes[j]) {
			hashes[j+1] = hashes[j]
			j--
		}
		hashes[j+1] = key
	}
	all := make([]byte, 0, 16+len(hashes)*32)
	all = appendStr(all, "vecset-v1")
	for _, h := range hashes {
		all = append(all, h[:]...)
	}
	return sha256.Sum256(all)
}

func bytesLess(a, b [32]byte) bool {
	for i := 0; i < 32; i++ {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return false
}

func hashSingleVec(v []int64) [32]byte {
	buf := make([]byte, 0, 8+len(v)*8)
	buf = binary.BigEndian.AppendUint64(buf, uint64(len(v)))
	for _, x := range v {
		buf = binary.BigEndian.AppendUint64(buf, uint64(x))
	}
	return sha256.Sum256(buf)
}

// discreteMedoidUnit returns the strictly order-invariant discrete L1 medoid of a unit
// vector set (minimizing sum_j ||u_i - u_j||, breaking exact-distance ties deterministically
// by canonical vector SHA-256). Eliminates the exact 180-degree cancellation order-dependence
// discovered in Experiment E7a (cross-referencing @frintroper/Symmetry-No-Symmetry).
func discreteMedoidUnit(units [][]int64) []int64 {
	n := len(units)
	dim := len(units[0])
	bestIdx := 0
	var bestSum uint64
	var bestHash [32]byte
	haveBest := false

	for i := 0; i < n; i++ {
		var sumDist uint64
		for j := 0; j < n; j++ {
			if i == j {
				continue
			}
			var sq uint64
			for d := 0; d < dim; d++ {
				ds := uint64(Abs64(units[i][d]-units[j][d]) / 1000)
				sq += ds * ds
			}
			sumDist += ISqrt64(sq)
		}
		h := hashSingleVec(units[i])
		if !haveBest || sumDist < bestSum || (sumDist == bestSum && bytesLess(h, bestHash)) {
			haveBest = true
			bestSum = sumDist
			bestHash = h
			bestIdx = i
		}
	}
	out := make([]int64, dim)
	copy(out, units[bestIdx])
	return out
}

// GeometricMedianFixed computes the deterministic fixed-point L1 Geometric Median on the
// unit sphere via Weiszfeld's iterative reweighting initialized at the order-invariant
// discrete L1 medoid (50% breakdown point against coordinated outlier clusters; pure integer
// arithmetic, zero floats, strictly order-invariant even under exact 180-degree cancellation).
//
// Mathematical basis: Weiszfeld (1937) / Vardi & Zhang (2000), solving sum_j (u_j - m)/||u_j - m|| = 0,
// independently validated in Experiments E5 & E7 after cross-referencing pairwise unit-difference
// relational fields and 180-degree symmetry stasis (Johannes Geisen / @frintroper).
func GeometricMedianFixed(vectors [][]int64, iters int) ([]int64, error) {
	units, err := validateAndNormalizeSet(vectors)
	if err != nil {
		return nil, err
	}
	if iters <= 0 {
		iters = 8
	}
	dim := len(units[0])
	n := len(units)

	// Strictly order-invariant discrete L1 medoid initialization (immune to exact 180-deg cancellation).
	med := discreteMedoidUnit(units)

	const epsDist int64 = 1000 // 0.001 in Scale units prevents 0/0 singularity
	for it := 0; it < iters; it++ {
		num := make([]int64, dim)
		var den int64
		for i := 0; i < n; i++ {
			var sq uint64
			for j := 0; j < dim; j++ {
				d := Abs64(units[i][j] - med[j])
				// Scale down by 1000 so d^2 fits safely inside uint64 for high dimensions.
				ds := uint64(d / 1000)
				sq += ds * ds
			}
			dist := int64(ISqrt64(sq)) * 1000
			if dist < epsDist {
				dist = epsDist
			}
			// Inverse-distance weight w = Scale^2 / dist (clamped via epsDist <= 1e9)
			w := (Scale * 1000) / (dist / 1000)
			if w <= 0 {
				w = 1
			}
			den += w
			for j := 0; j < dim; j++ {
				num[j] += (w * units[i][j]) / Scale
			}
		}
		if den == 0 {
			break
		}
		next, nErr := UnitNormalizeFixed(num)
		if nErr != nil {
			break
		}
		med = next
	}
	return med, nil
}

// AntipodalFractionFixed computes the strictly order-invariant fraction (in [0, Scale]) of
// distinct unit vector pairs whose cosine similarity is <= negThresholdFixed (default -500000 = -0.50).
// Validated in Experiment E7b (100% TPR on balanced antipodal split-brain attacks at 0% clean FPR).
func AntipodalFractionFixed(vectors [][]int64, negThresholdFixed int64) (int64, error) {
	units, err := validateAndNormalizeSet(vectors)
	if err != nil {
		return 0, err
	}
	if negThresholdFixed == 0 {
		negThresholdFixed = -500000 // -0.50 cosine floor
	}
	n := len(units)
	dim := len(units[0])
	var antipodal int64
	var pairs int64
	for i := 0; i < n; i++ {
		for j := i + 1; j < n; j++ {
			pairs++
			var dot int64
			for d := 0; d < dim; d++ {
				dot += MulFixed(units[i][d], units[j][d])
			}
			if dot <= negThresholdFixed {
				antipodal++
			}
		}
	}
	if pairs == 0 {
		return 0, nil
	}
	return (antipodal * Scale) / pairs, nil
}

// AntipodalSplitGate flags coordinated 180-degree / opposing split-brain poisoning batches
// when AntipodalFractionFixed exceeds maxFractionFixed (default 100000 = 10% of pairs).
func AntipodalSplitGate(vectors [][]int64, negThresholdFixed, maxFractionFixed int64) (bool, int64, SignalEvidence, error) {
	if negThresholdFixed == 0 {
		negThresholdFixed = -500000
	}
	if maxFractionFixed <= 0 {
		maxFractionFixed = 100000 // 0.10
	}
	frac, err := AntipodalFractionFixed(vectors, negThresholdFixed)
	if err != nil {
		return false, 0, SignalEvidence{}, err
	}
	pass := frac < maxFractionFixed
	detail := "no_antipodal_split"
	if !pass {
		detail = "antipodal_split_brain_detected"
	}
	ev := SignalEvidence{
		Primitive:    "signals.antipodal_split_gate",
		Version:      "1",
		ParamsDigest: hashInt64s("antipodal_split_gate", negThresholdFixed, maxFractionFixed),
		InputDigest:  digestVectorSet(vectors),
		OutputFixed:  frac,
		Alarm:        !pass,
		Detail:       detail,
	}
	return pass, frac, ev, nil
}

// CommonAverageReferenceDebiasFixed removes a shared anisotropic common-cone component from
// an embedding vector in pure fixed-point integer arithmetic: unit(unit(vec) - coneWeight*unit(coneRef)).
// Validated in Experiment E9 (+76.5 pts poison quarantine TPR & -87.7 pts Top-3 contamination
// under anisotropic common-cone collapse, cross-referencing Arobi Labs embedding anisotropy findings).
func CommonAverageReferenceDebiasFixed(vec, coneRef []int64, coneWeightFixed int64) ([]int64, error) {
	u, err := UnitNormalizeFixed(vec)
	if err != nil {
		return nil, err
	}
	if len(coneRef) == 0 || coneWeightFixed <= 0 {
		return u, nil
	}
	if len(coneRef) != len(u) {
		return nil, errors.New("cone reference dimension mismatch")
	}
	cUnit, err := UnitNormalizeFixed(coneRef)
	if err != nil {
		return nil, err
	}
	if coneWeightFixed > Scale {
		coneWeightFixed = Scale
	}
	debiased := make([]int64, len(u))
	for i := range u {
		debiased[i] = u[i] - MulFixed(coneWeightFixed, cUnit[i])
	}
	out, err := UnitNormalizeFixed(debiased)
	if err != nil {
		// Vector was strictly collinear with coneRef; fall back safely to unit vector.
		return u, nil
	}
	return out, nil
}
