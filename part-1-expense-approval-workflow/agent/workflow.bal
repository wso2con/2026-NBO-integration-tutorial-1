import ballerina/ai;
import ballerina/io;
import ballerina/workflow;

// Claims at or below this amount skip the human task and go straight to
// reimbursement; larger ones pause for a manager's decision. Same policy and
// same threshold as ../backend's plain workflow.
const decimal autoApproveThreshold = 500.0;

// The WSO2 default model provider, configured via `ballerina.ai.wso2ProviderConfig`
// in Config.toml (the Ballerina VS Code extension can generate it - see Config.toml).
final ai:ModelProvider claimsModel = check ai:getDefaultModelProvider();

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

// A conversational durable agent that implements the same claim-approval
// policy as ../backend's expenseApproval workflow: the agent itself decides,
// per the system prompt, whether to reimburse directly or hand off to the
// "approveExpense" human task - the same task name, role and result type
// ../backend uses - which durably suspends processing until a manager decides.
// Named `expenseApproval` (not `expenseAgent`) so its workflow type in
// Temporal matches ../backend's exactly - the web UI filters on that name.
final workflow:DurableAgent expenseApproval = check new ({
    systemPrompt: {
        role: "You are the claims assistant for Acme Insurance.",
        instructions: string `You receive an insurance expense claim as a JSON object with
                fields claimId, userId, userName, amount, currency, category and description.
                Always call the validateClaim tool with the full claim first. If it returns
                false, reply with exactly: "Claim <claimId> failed policy validation." and stop.
                If the amount is ${autoApproveThreshold} or less, call the reimburse tool
                directly. If the amount is greater than ${autoApproveThreshold}, call the
                approveExpense tool with the claim id, user id, user name, amount, currency,
                category and description; if the manager rejects it, reply with exactly:
                "Claim <claimId> rejected by manager: <comment>." and stop - otherwise call
                the reimburse tool.
                After a successful reimburse call, reply with exactly:
                "Claim <claimId> reimbursed. Reference: <reference>."
                Reply with only that single sentence, substituting the real values - no other
                commentary.`
    },
    model: claimsModel,
    activities: [validateClaim, reimburse],
    humanTasks: [
        {
            name: "approveExpense",
            roles: "MANAGER",
            resultType: ApprovalDecision,
            title: "Approve insurance claim",
            description: "Requests a manager's approval to reimburse a claim over the "
                + "auto-approve threshold. Includes the claim id, user, amount, currency, "
                + "category and description."
        }
    ]
});
