package assurance

import (
	"chain/runtime"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// A `gnokey maketx run` script executes as the ephemeral realm gno.land/e/<addr>/run.
// runtime's IsUser() accepts that realm (through IsUserRun), but IsUserCall() does not, and a
// run script could spend the transaction's coin envelope before a payment function counts it.
// So every payment function guards with IsUserCall(). This test pins that choice: if a guard
// were relaxed to IsUser(), the MsgRun caller below would get through and the test would fail.
func TestPaymentFunctionsRefuseMsgRunCallers(cur realm, t *testing.T) {
	resetRealm()
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RegisterAgent(cross(cur), "agent-msgrun", "MsgRun Caller", policyDig1, "")

	run := runtime.NewRealm(agentOwner, "gno.land/e/"+agentOwner.String()+"/run")
	uassert.True(t, run.IsUser(), "IsUser() accepts a MsgRun realm")
	uassert.False(t, run.IsUserCall(), "IsUserCall() does not")

	feesBefore := accruedServiceFees
	sizeBefore := Size()
	testing.SetRealm(run)
	sendFee(AnchorFeeUgnot())
	uassert.AbortsContains(t, cur, "direct user call", func() {
		AnchorCheckpoint(cross(cur), "agent-msgrun", policyDig2, zeroRoot, 1, 1, 0)
	})
	testing.SetRealm(run)
	sendFee(AgentPlanPriceUgnot())
	uassert.AbortsContains(t, cur, "direct user call", func() {
		SubscribeAgent(cross(cur), "agent-msgrun")
	})
	uassert.Equal(t, feesBefore, accruedServiceFees, "nothing was charged")
	uassert.Equal(t, sizeBefore, Size(), "nothing was anchored")
}
