package assurance

import (
	"strconv"
	"testing"
)

// LedgerAccumulator stores its leaves differently, and must answer exactly as Accumulator does: the same indexes,
// roots, leaves, audit paths and consistency proofs, at every size, for every pair.
func TestLedgerAccumulatorAnswersExactlyAsAccumulator(t *testing.T) {
	var slice Accumulator
	var ledger LedgerAccumulator
	if ledger.Root() != slice.Root() || ledger.Size() != 0 {
		t.Fatal("the empty trees differ")
	}
	const n = 33
	for i := 0; i < n; i++ {
		leaf := HashString("ledger-leaf-" + strconv.Itoa(i))
		if a, b := slice.Append(leaf), ledger.Append(leaf); a != b {
			t.Fatalf("append %d: index %d vs %d", i, a, b)
		}
		if slice.Root() != ledger.Root() {
			t.Fatalf("root differs after %d leaves", i+1)
		}
	}
	if ledger.Size() != n {
		t.Fatalf("size %d, want %d", ledger.Size(), n)
	}
	for i := uint64(0); i < n; i++ {
		a, _ := slice.Leaf(i)
		b, ok := ledger.Leaf(i)
		if !ok || a != b {
			t.Fatalf("leaf %d differs", i)
		}
	}
	if _, ok := ledger.Leaf(n); ok {
		t.Fatal("a leaf past the end was returned")
	}
	for size := uint64(0); size <= n; size++ {
		ra, _ := slice.RootAt(size)
		rb, err := ledger.RootAt(size)
		if err != nil || ra != rb {
			t.Fatalf("RootAt(%d) differs", size)
		}
		for index := uint64(0); index < size; index++ {
			pa, _ := slice.Proof(index, size)
			pb, err := ledger.Proof(index, size)
			if err != nil || !ledgerSameDigests(pa, pb) {
				t.Fatalf("Proof(%d, %d) differs", index, size)
			}
			leaf, _ := ledger.Leaf(index)
			if !VerifyInclusion(index, size, leaf, pb, rb) {
				t.Fatalf("Proof(%d, %d) does not verify", index, size)
			}
		}
		for first := uint64(1); first <= size; first++ {
			ca, _ := slice.ConsistencyProof(first, size)
			cb, err := ledger.ConsistencyProof(first, size)
			if err != nil || !ledgerSameDigests(ca, cb) {
				t.Fatalf("ConsistencyProof(%d, %d) differs", first, size)
			}
		}
	}
	if _, err := ledger.RootAt(n + 1); err == nil {
		t.Fatal("RootAt past the end did not fail")
	}
	if _, err := ledger.Proof(0, n+1); err == nil {
		t.Fatal("Proof past the end did not fail")
	}
	if _, err := ledger.ConsistencyProof(0, n); err == nil {
		t.Fatal("ConsistencyProof from size 0 did not fail")
	}
}

func ledgerSameDigests(a, b [][32]byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
