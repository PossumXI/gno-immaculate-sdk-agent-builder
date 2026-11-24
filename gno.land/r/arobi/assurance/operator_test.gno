package assurance

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The operator is bound atomically to the deploying account inside init(), closing any
// post-deployment front-running window.
func TestOperatorIsTheDeployerAndAStrangerCannotTakeIt(cur realm, t *testing.T) {
	resetRealm()
	uassert.Equal(t, deployAcct, deployer, "init records deploying account")
	uassert.Equal(t, deployAcct, Operator(), "deployer is initial operator")

	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	uassert.AbortsContains(t, cur, "operator only", func() { SetSettlementSink(cross(cur), stranger) })
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	uassert.AbortsContains(t, cur, "operator only", func() { TransferOperator(cross(cur), stranger) })
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	uassert.AbortsContains(t, cur, "operator only", func() { SetPricing(cross(cur), 0, 0) })
	testing.SetRealm(testing.NewUserRealm(stranger))
	sendFee(0)
	uassert.AbortsContains(t, cur, "operator only", func() { CollectServiceFees(cross(cur), stranger) })

	uassert.Equal(t, deployer, Operator())
	uassert.Equal(t, address(""), settlementSink)
}

// Every payment function reads OriginSend only after asserting cur.Previous().IsUserCall(),
// refusing code-realm callers before any coins are counted.
func TestPaymentFunctionsRefuseCodeRealmCallers(cur realm, t *testing.T) {
	resetRealm()
	testing.SetRealm(testing.NewUserRealm(agentOwner))
	sendFee(0)
	RegisterAgent(cross(cur), "agent-code-caller", "Code Caller", policyDig1, "")

	for _, path := range []string{"gno.land/r/attacker/caller", "gno.land/r/demo/other"} {
		testing.SetRealm(testing.NewCodeRealm(path))
		sendFee(AnchorFeeUgnot())
		uassert.AbortsContains(t, cur, "direct user call", func() {
			AnchorCheckpoint(cross(cur), "agent-code-caller", policyDig2, zeroRoot, 1, 1, 0)
		})
		testing.SetRealm(testing.NewCodeRealm(path))
		sendFee(AgentPlanPriceUgnot())
		uassert.AbortsContains(t, cur, "direct user call", func() {
			SubscribeAgent(cross(cur), "agent-code-caller")
		})
	}
}
