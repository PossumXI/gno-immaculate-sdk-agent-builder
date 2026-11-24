package assurance

import (
	"testing"

	"gno.land/p/arobi/signals"
)

func TestE13MemoryVaultHubnessNormalizationRescuesRecall(t *testing.T) {
	cal := [][]int64{
		{620000, 320000, 320000, 320000},
		{320000, 620000, 320000, 320000},
		{320000, 320000, 620000, 320000},
		{320000, 320000, 320000, 620000},
	}
	vRaw := NewMemoryVault(MemoryVaultConfig{
		VaultID:                  "raw-hub-test",
		QuarantineThresholdFixed: -signals.Scale,
	})
	vHub := NewMemoryVault(MemoryVaultConfig{
		VaultID:                  "hub-norm-test",
		QuarantineThresholdFixed: -signals.Scale,
	})
	if err := vHub.SetHubnessCalibration(cal, 50000); err != nil {
		t.Fatalf("SetHubnessCalibration err: %v", err)
	}

	hubVec := []int64{500000, 500000, 500000, 500000}
	targetVec := []int64{920000, 120000, 120000, 120000}
	otherVec := []int64{120000, 920000, 120000, 120000}

	for _, vault := range []*MemoryVault{vRaw, vHub} {
		if _, err := vault.Ingest(MemoryKindSemantic, "agent", []byte("generic universal hub"), hubVec, signals.Scale, 1, HashString("hub-1")); err != nil {
			t.Fatalf("ingest hub err: %v", err)
		}
		if _, err := vault.Ingest(MemoryKindSemantic, "agent", []byte("specific axis zero"), targetVec, signals.Scale, 2, HashString("target-2")); err != nil {
			t.Fatalf("ingest target err: %v", err)
		}
		if _, err := vault.Ingest(MemoryKindSemantic, "agent", []byte("specific axis one"), otherVec, signals.Scale, 3, HashString("other-3")); err != nil {
			t.Fatalf("ingest other err: %v", err)
		}
	}

	query := []int64{600000, 330000, 330000, 330000}
	topRaw, _, err := vRaw.RetrieveTopK(query, "", 1, 10)
	if err != nil {
		t.Fatalf("raw RetrieveTopK err: %v", err)
	}
	topHub, _, err := vHub.RetrieveTopK(query, "", 1, 10)
	if err != nil {
		t.Fatalf("hub RetrieveTopK err: %v", err)
	}
	if topRaw[0].Record.ID != 1 {
		t.Fatalf("expected raw cosine to be hijacked by hub ID=1, got ID=%d", topRaw[0].Record.ID)
	}
	if topHub[0].Record.ID != 2 {
		t.Fatalf("expected hubness-normalized recall to recover target ID=2, got ID=%d", topHub[0].Record.ID)
	}
}

func TestE14CrossChainCheckpointAndOrderedReceiptTree(t *testing.T) {
	cp := CanonicalCheckpoint{
		ChainID:            "arobi-testnet-1",
		Height:             4200,
		HeaderHash:         HashString("hdr-4200"),
		AppHash:            HashString("app-4200"),
		ValidatorsHash:     HashString("val-4200"),
		NextValidatorsHash: HashString("nval-4200"),
	}
	dig1, err := cp.Digest()
	if err != nil {
		t.Fatalf("checkpoint Digest err: %v", err)
	}
	cpMut := cp
	cpMut.Height = 4201
	dig2, _ := cpMut.Digest()
	if dig1 == dig2 {
		t.Fatal("mutated checkpoint must produce a different digest")
	}

	r1 := ExecutionReceipt{
		ChainID:    "arobi-testnet-1",
		Height:     4200,
		TxIndex:    0,
		TxHash:     HashString("tx-0"),
		Caller:     "g1alice",
		Contract:   "wasm/escrow-v1",
		GasUsed:    125000,
		ExitCode:   0,
		ResultHash: HashString("res-0"),
	}
	r2 := ExecutionReceipt{
		ChainID:    "arobi-testnet-1",
		Height:     4200,
		TxIndex:    1,
		TxHash:     HashString("tx-1"),
		Caller:     "g1bob",
		Contract:   "wasm/escrow-v1",
		GasUsed:    98000,
		ExitCode:   0,
		ResultHash: HashString("res-1"),
	}
	r3 := ExecutionReceipt{
		ChainID:    "arobi-testnet-1",
		Height:     4201,
		TxIndex:    0,
		TxHash:     HashString("tx-2"),
		Caller:     "g1carol",
		Contract:   "wasm/govern-v1",
		GasUsed:    210000,
		ExitCode:   0,
		ResultHash: HashString("res-2"),
	}

	acc, root, err := BuildOrderedReceiptTree([]ExecutionReceipt{r1, r2, r3})
	if err != nil {
		t.Fatalf("BuildOrderedReceiptTree valid batch err: %v", err)
	}
	if acc.Size() != 3 {
		t.Fatalf("expected 3 leaves, got %d", acc.Size())
	}
	leaf1, _ := r2.LeafHash()
	proof1, err := acc.Proof(1, 3)
	if err != nil {
		t.Fatalf("Proof(1, 3) err: %v", err)
	}
	if !VerifyInclusion(1, 3, leaf1, proof1, root) {
		t.Fatal("valid receipt inclusion proof failed")
	}

	// Out-of-order and duplicate batches must fail closed with ErrNonCanonicalOrder.
	if _, _, err := BuildOrderedReceiptTree([]ExecutionReceipt{r2, r1}); err != ErrNonCanonicalOrder {
		t.Fatalf("expected ErrNonCanonicalOrder on swapped txIndex, got %v", err)
	}
	if _, _, err := BuildOrderedReceiptTree([]ExecutionReceipt{r1, r1}); err != ErrNonCanonicalOrder {
		t.Fatalf("expected ErrNonCanonicalOrder on duplicate (height, txIndex), got %v", err)
	}
	if _, _, err := BuildOrderedReceiptTree([]ExecutionReceipt{r3, r1}); err != ErrNonCanonicalOrder {
		t.Fatalf("expected ErrNonCanonicalOrder on decreasing height, got %v", err)
	}

	// Cross-language golden vector printed for Node.js parity test.
	println("E14_GOLDEN_CHECKPOINT_DIGEST=" + Hex(dig1))
	println("E14_GOLDEN_RECEIPT_ROOT=" + Hex(root))
	println("E14_GOLDEN_RECEIPT_LEAF1=" + Hex(leaf1))
}
