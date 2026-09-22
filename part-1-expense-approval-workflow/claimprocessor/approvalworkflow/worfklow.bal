import ballerina/io;
import ballerina/workflow;

// Claims at or below this amount skip the human task and go straight to
// reimbursement; larger ones pause for a manager's decision.
const decimal autoApproveThreshold = 500.0;

@workflow:Workflow
function expenseApproval(workflow:Context ctx, Claim claim) returns string|error {
    boolean withinPolicy = check ctx->callActivity(validateClaim, {"claim": claim});
    if !withinPolicy {
        return string `Claim ${claim.claimId} failed policy validation.`;
    }

    if claim.amount > autoApproveThreshold {
        ApprovalDecision decision = check ctx->awaitHumanTask("approveExpense",
                claim,
                userRoles = "MANAGER",
                administratorRoles = "admin",
                title = string `Approve claim ${claim.claimId}`,
                description = string `${claim.userName} submitted a ${claim.amount} ${claim.currency} claim for ${claim.category}: ${claim.description}`);
        if !decision.approved {
            return string `Claim ${claim.claimId} rejected by manager: ${decision.comment}`;
        }
    }

    string reimbursementRef = check ctx->callActivity(reimburse, {"claimId": claim.claimId, "amount": claim.amount});
    return string `Claim ${claim.claimId} reimbursed. Reference: ${reimbursementRef}`;
}

@workflow:Activity
function validateClaim(Claim claim) returns boolean|error {
    io:println(string `Validating claim ${claim.claimId} for ${claim.userName}`);
    return claim.amount > 0d;
}

@workflow:Activity
function reimburse(string claimId, decimal amount) returns string|error {
    io:println(string `Reimbursing ${amount} for claim ${claimId}`);
    return string `PAY-${claimId}`;
}
