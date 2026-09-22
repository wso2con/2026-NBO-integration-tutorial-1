// Amani General Insurance - claims handling toolset (MCP).
//
// The "after" to claimmcp's "before". Same backend, same five REST endpoints
// underneath, entirely different contract with the agent:
//
//   claimmcp    tools named after routes, raw records out, no rules. The model is
//               told what to decide by its system prompt, because the tools give it
//               nothing to decide with - and nothing stops it settling a claim the
//               policy does not cover.
//   claimtools  tools named after the handler's task. One call returns a complete
//               brief including policy, coverage and the claimant's history - none of
//               which any claimapi endpoint returns. Writes enforce the rules that
//               claimapi has never had.
//
// A NOTE ON REFUSALS, which is the whole design:
//
// ballerina/mcp turns a returned `error` into the literal string
// "Tool '<name>' failed unexpectedly." and logs the real message server-side
// (service_utils.bal:151, toToolExecutionError). The model never sees why.
//
// So a guardrail refusal is NOT an error here. It is a successful result carrying
// status "REFUSED", a code, a human-readable message, and a `remedy` naming the exact
// tool and arguments that would move the claim forward. `error` is reserved for
// genuine infrastructure failure, where "failed unexpectedly" is the honest answer.

import ballerina/mcp;

configurable int servicePort = 9091;

listener mcp:StreamableHttpListener mcpListener = new (servicePort);

@mcp:StreamableHttpServiceConfig {
    info: {
        name: "Amani General Insurance - Claims Handling",
        version: "1.0.0"
    },
    // Allows this MCP server to be called cross-origin (e.g. from a browser-based
    // client on WSO2 Integration Platform Cloud) - CORS is opt-in and otherwise
    // absent, which is what previously surfaced as a CORS error on Cloud.
    httpConfig: {
        cors: {
            allowOrigins: ["*"],
            allowMethods: ["GET", "POST", "OPTIONS"],
            allowHeaders: ["Content-Type", "Authorization", "Mcp-Session-Id"],
            exposeHeaders: ["Mcp-Session-Id"]
        }
    },
    sessionMode: mcp:STATELESS,
    options: {
        instructions: "Tools for handling a household insurance claim end to end. " +
                "Call getClaimAssessment first; it returns the claim, the policy, the coverage " +
                "finding and any blockers in one call. Call getCustomerProfile before deciding " +
                "or escalating to see the claimant's other claims, open and closed. Tools refuse " +
                "with a status of REFUSED and a remedy rather than failing - read the remedy and " +
                "follow it. Never decide a claim that still has outstanding documents."
    }
}
service mcp:StreamableHttpService /mcp on mcpListener {

    # Load everything needed to act on a claim: the claim itself, the claimant, their
    # policy, whether the loss is covered and for how much, their prior-claim history,
    # your authority limit, and any blockers currently preventing a decision.
    # Call this first, and again after documents arrive.
    #
    # + claimId - The claim to assess, for example CLM-1042
    # + return - The full assessment brief, or a refusal if the claim does not exist
    @mcp:Tool {
        description: "Load everything needed to act on a claim in one call: the claim, the " +
                "claimant, their policy, the coverage finding and payable amount, their " +
                "prior-claim history, your authority limit, and any blockers preventing a " +
                "decision. Call this first, and again after documents arrive."
    }
    isolated remote function getClaimAssessment(string claimId) returns ToolResponse|error {
        Claim|ToolResponse claim = check fetchClaim(claimId);
        if claim is ToolResponse {
            return claim;
        }

        Policy? policy = getPolicy(claim.customerId);
        if policy is () {
            return refused("NO_POLICY_ON_RECORD",
                    string `No policy found for claimant ${claim.customerId}. A human adjuster ` +
                    "must confirm cover before this claim can proceed.",
                    {tool: "escalateToAdjuster",
                        arguments: {claimId, reason: COVERAGE_AMBIGUOUS}});
        }

        Customer customer = check fetchCustomer(claim.customerId);
        Coverage coverage = determineCoverage(policy, claim);

        ToolResponse response = ok("ASSESSMENT_READY",
                string `Assessment for ${claimId}. Decide, request documents, or escalate ` +
                "based on the blockers and limits below.");
        response.assessment = buildAssessment(claim, customer, policy, coverage);
        return response;
    }

    # Look up a claimant's contact details plus a summary of every claim they have on
    # file, open and closed. Use this to see the claimant's full picture beyond the
    # single claim you were asked about - for example, before escalating or deciding,
    # to check whether they have other claims open at the same time.
    #
    # + customerId - The claimant to look up, for example CUST-2002
    # + return - The customer profile brief, or a refusal if the customer does not exist
    @mcp:Tool {
        description: "Look up a claimant's contact details plus a summary of every claim they " +
                "have on file (open and closed), including how many are currently open. Use this " +
                "before deciding or escalating to see the claimant's full picture - for example, " +
                "to notice several claims open at once - beyond the single claim in front of you."
    }
    isolated remote function getCustomerProfile(string customerId) returns ToolResponse|error {
        Customer|ToolResponse customer = check fetchCustomerProfile(customerId);
        if customer is ToolResponse {
            return customer;
        }

        Claim[] allClaims = check fetchAllClaims();

        ToolResponse response = ok("PROFILE_READY",
                string `Profile for ${customerId}: ${customer.name}, ` +
                string `contactable at ${customer.email}.`);
        response.assessment = buildCustomerProfile(customer, allClaims);
        return response;
    }

    # Ask the claimant for specific documents. You choose which documents to request,
    # based on what is outstanding and what the claim type actually warrants.
    #
    # + claimId - The claim
    # + documents - Filenames to request, for example repair_estimate.pdf
    # + return - The updated claim, or a refusal
    @mcp:Tool {
        description: "Ask the claimant for specific documents. You choose which documents to " +
                "request. The claim then waits for the claimant to respond."
    }
    isolated remote function requestMissingDocuments(string claimId, string[] documents) returns ToolResponse|error {
        Claim|ToolResponse claim = check fetchClaim(claimId);
        if claim is ToolResponse {
            return claim;
        }
        if documents.length() == 0 {
            return refused("NO_DOCUMENTS_SPECIFIED",
                    "Specify at least one document to request. The outstanding documents for " +
                    "this claim are listed under documents.outstanding in getClaimAssessment.");
        }

        json _ = check backendClient->post(string `/claims/${claimId}/request-documents`,
                {missingDocuments: documents});
        return ok("DOCUMENTS_REQUESTED",
                string `Requested ${documents.length()} document(s) from the claimant: ` +
                string:'join(", ", ...documents) + ". The claim is now waiting on them.");
    }

    # Record documents the claimant has submitted. Call this when you are told documents
    # have arrived, then re-assess the claim before deciding.
    #
    # + claimId - The claim
    # + documents - Filenames the claimant submitted
    # + return - The updated claim, or a refusal
    @mcp:Tool {
        description: "Record documents the claimant has submitted. Call this when you are told " +
                "documents have arrived, then call getClaimAssessment again before deciding."
    }
    isolated remote function recordDocumentsReceived(string claimId, string[] documents) returns ToolResponse|error {
        Claim|ToolResponse claim = check fetchClaim(claimId);
        if claim is ToolResponse {
            return claim;
        }
        if documents.length() == 0 {
            return refused("NO_DOCUMENTS_SPECIFIED", "Specify at least one document that was received.");
        }

        json _ = check backendClient->post(string `/claims/${claimId}/documents-received`, {documents});
        return ok("DOCUMENTS_RECORDED",
                string `Recorded ${documents.length()} document(s). Re-assess the claim before deciding.`);
    }

    # Record your decision on a claim. Refuses - it does not throw - if the claim is not
    # eligible for the decision you are making.
    #
    # + claimId - The claim
    # + decision - APPROVED or REJECTED
    # + rationale - Why. Quote the coverage basis or the policy clause. Required.
    # + return - The recorded decision, or a refusal carrying the remedy
    @mcp:Tool {
        description: "Record your decision on a claim. Returns status REFUSED with a remedy if " +
                "the claim is not eligible for this decision - outstanding documents, a loss the " +
                "policy does not cover, or an amount above your authority limit. It never throws " +
                "for a refusal: read the response and follow the remedy."
    }
    isolated remote function decideClaim(string claimId, Decision decision, string rationale)
            returns ToolResponse|error {
        Claim|ToolResponse claim = check fetchClaim(claimId);
        if claim is ToolResponse {
            return claim;
        }
        if rationale.trim().length() == 0 {
            return refused("RATIONALE_REQUIRED",
                    "Every decision needs a rationale. Cite the coverage basis or the policy " +
                    "clause you are relying on - it is shown to the claimant.");
        }

        Policy? policy = getPolicy(claim.customerId);
        if policy is () {
            return refused("NO_POLICY_ON_RECORD",
                    string `No policy on record for ${claim.customerId}.`,
                    {tool: "escalateToAdjuster", arguments: {claimId, reason: COVERAGE_AMBIGUOUS}});
        }
        Coverage coverage = determineCoverage(policy, claim);
        Blocker[] blockers = blockersFor(claim, coverage);

        // Evaluation order matters: gather documents, then establish cover, then check
        // authority. Each refusal names the single next action that clears it.
        if claim.decision !is () {
            return refused("ALREADY_DECIDED",
                    string `${claimId} was already decided: ${claim.decision ?: ""}.`, (), blockers);
        }
        if claim.missingDocuments.length() > 0 {
            return refused("DOCUMENTS_OUTSTANDING",
                    string `${claimId} still has outstanding documents: ` +
                    string:'join(", ", ...claim.missingDocuments) +
                    ". Request them, and record them when they arrive, before deciding.",
                    {tool: "requestMissingDocuments",
                        arguments: {claimId, documents: claim.missingDocuments}},
                    blockers);
        }
        if decision == APPROVED && !coverage.covered {
            return refused("NOT_COVERED",
                    string `${claimId} cannot be approved: ${coverage.basis} ` +
                    "Reject it citing that clause, or escalate if you believe cover is arguable.",
                    {tool: "decideClaim",
                        arguments: {claimId, decision: REJECTED, rationale: coverage.basis}},
                    blockers);
        }
        if decision == APPROVED && coverage.estimatedPayable > autoApprovalLimit {
            return refused("EXCEEDS_AUTHORITY",
                    string `Payable ${coverage.estimatedPayable} exceeds your auto-approval ` +
                    string `limit of ${autoApprovalLimit}. Hand it to a human adjuster.`,
                    {tool: "escalateToAdjuster",
                        arguments: {claimId, reason: EXCEEDS_AUTHORITY}},
                    blockers);
        }

        json updated = check backendClient->post(string `/claims/${claimId}/decision`,
                {decision: decision, reason: rationale});
        return ok("DECISION_RECORDED",
                decision == APPROVED
                    ? string `${claimId} approved. Settle it to pay ${coverage.estimatedPayable} ` +
                        string `(claim ${claim.amount} less ${coverage.deductible} deductible).`
                    : string `${claimId} rejected. The claimant will be notified with your rationale.`,
                updated);
    }

    # Hand the claim to a human adjuster. Use this when a decision is above your
    # authority, when cover is genuinely arguable, or when something looks wrong.
    #
    # + claimId - The claim
    # + reason - Why it needs a human
    # + summary - What you found and what the adjuster should look at. Required.
    # + return - Confirmation, or a refusal
    @mcp:Tool {
        description: "Hand the claim to a human adjuster, with a summary of what you found. Use " +
                "this when decideClaim refuses because the amount is above your authority, or " +
                "when cover is genuinely arguable. Gather outstanding documents first."
    }
    isolated remote function escalateToAdjuster(string claimId, EscalationReason reason, string summary)
            returns ToolResponse|error {
        Claim|ToolResponse claim = check fetchClaim(claimId);
        if claim is ToolResponse {
            return claim;
        }
        if summary.trim().length() == 0 {
            return refused("SUMMARY_REQUIRED",
                    "Summarise what you found and what the adjuster needs to look at.");
        }
        if claim.decision !is () {
            return refused("ALREADY_DECIDED",
                    string `${claimId} was already decided: ${claim.decision ?: ""}. ` +
                    "There is nothing left to escalate.");
        }
        // Without this, a second escalation silently overwrites the summary the
        // adjuster is working from.
        if claim.status == "ESCALATED" {
            return refused("ALREADY_ESCALATED",
                    string `${claimId} is already with a human adjuster. Do not escalate it twice.`);
        }
        // An adjuster picking this up wants the file complete, so the same
        // documents guardrail applies here as on decideClaim.
        if claim.missingDocuments.length() > 0 {
            return refused("DOCUMENTS_OUTSTANDING",
                    string `Gather the outstanding documents before escalating ${claimId}: ` +
                    string:'join(", ", ...claim.missingDocuments) + ".",
                    {tool: "requestMissingDocuments",
                        arguments: {claimId, documents: claim.missingDocuments}});
        }

        json updated = check backendClient->post(string `/claims/${claimId}/escalate`,
                {reason: reason, summary: summary});
        return ok("ESCALATED",
                string `${claimId} is now with a human adjuster (${reason}). No further action ` +
                "from you on this claim.", updated);
    }

    # Pay an approved claim, net of the policy deductible, and notify the claimant.
    #
    # + claimId - The claim to settle
    # + return - The settled claim, or a refusal
    @mcp:Tool {
        description: "Pay an approved claim, net of the policy deductible, and notify the " +
                "claimant. Refuses unless the claim has already been approved."
    }
    isolated remote function settleClaim(string claimId) returns ToolResponse|error {
        Claim|ToolResponse claim = check fetchClaim(claimId);
        if claim is ToolResponse {
            return claim;
        }

        // Read the decision column, not status: claimapi overwrites status with 'PAID'
        // and uses 'DECIDED' for both approvals and rejections.
        string? decision = claim.decision;
        if claim.paymentStatus == "PAID" {
            return refused("ALREADY_PAID", string `${claimId} has already been settled.`);
        }
        if decision is () {
            return refused("NOT_DECIDED",
                    string `${claimId} has not been decided yet. Decide it before settling.`,
                    {tool: "getClaimAssessment", arguments: {claimId}});
        }
        if decision != APPROVED {
            return refused("DECISION_WAS_REJECTED",
                    string `${claimId} was rejected, so there is nothing to pay.`);
        }

        Policy? policy = getPolicy(claim.customerId);
        decimal deductible = policy is () ? 0.00 : policy.deductible;
        decimal payable = claim.amount - deductible;
        if payable < 0d {
            payable = 0.00;
        }

        json updated = check backendClient->post(string `/claims/${claimId}/payment`, {});
        return ok("SETTLED",
                string `Paid ${payable} on ${claimId} (claim ${claim.amount} less ` +
                string `${deductible} deductible). The claimant has been notified.`, updated);
    }
}
