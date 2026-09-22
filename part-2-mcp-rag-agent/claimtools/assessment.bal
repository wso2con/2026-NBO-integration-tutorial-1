// The claims backend client, the assessment builder, and the response envelope.

import ballerina/http;

configurable string backendUrl = "http://localhost:8080";
configurable string customersBackendUrl = "http://localhost:8081";

# The most this agent may approve on its own. Anything above it must be escalated
# to a human adjuster - this is the agent's authority limit, not a system limit.
configurable decimal autoApprovalLimit = 1000.00;

final http:Client backendClient = check new (backendUrl);
final http:Client customersBackendClient = check new (customersBackendUrl);

// ---------------------------------------------------------------------------
// Envelope helpers
// ---------------------------------------------------------------------------

isolated function ok(string code, string message, json? claim = ()) returns ToolResponse {
    ToolResponse response = {status: "OK", code, message};
    if claim !is () {
        response.claim = claim;
    }
    return response;
}

isolated function refused(string code, string message, Remedy? remedy = (), Blocker[]? blockers = ())
        returns ToolResponse {
    ToolResponse response = {status: "REFUSED", code, message};
    if remedy !is () {
        response.remedy = remedy;
    }
    if blockers !is () {
        response.blockers = blockers;
    }
    return response;
}

// ---------------------------------------------------------------------------
// Backend access
// ---------------------------------------------------------------------------

// A missing claim is a refusal the model can act on, not an infrastructure failure,
// so it is separated from genuine transport errors here.
isolated function fetchClaim(string claimId) returns Claim|ToolResponse|error {
    Claim|http:ClientError claim = backendClient->get(string `/claims/${claimId}`);
    if claim is http:ClientRequestError {
        return refused("CLAIM_NOT_FOUND", string `No claim with id ${claimId} exists.`);
    }
    return claim;
}

isolated function fetchCustomer(string customerId) returns Customer|error {
    return customersBackendClient->get(string `/customers/${customerId}`);
}

// Mirrors fetchClaim's not-found-as-refusal handling: a customer that doesn't
// exist is something the agent can act on (e.g. tell the caller), not an
// infrastructure failure.
isolated function fetchCustomerProfile(string customerId) returns Customer|ToolResponse|error {
    Customer|http:ClientError customer = customersBackendClient->get(string `/customers/${customerId}`);
    if customer is http:ClientRequestError {
        return refused("CUSTOMER_NOT_FOUND", string `No customer with id ${customerId} exists.`);
    }
    return customer;
}

isolated function fetchAllClaims() returns Claim[]|error {
    return backendClient->get("/claims");
}

// ---------------------------------------------------------------------------
// Blockers - the objective reasons a claim cannot be decided right now
// ---------------------------------------------------------------------------

isolated function blockersFor(Claim claim, Coverage coverage) returns Blocker[] {
    Blocker[] blockers = [];

    if claim.missingDocuments.length() > 0 {
        blockers.push({
            code: "DOCUMENTS_OUTSTANDING",
            detail: string `${claim.missingDocuments.length()} document(s) not yet received: ` +
                    string:'join(", ", ...claim.missingDocuments)
        });
    }
    if !coverage.covered {
        blockers.push({code: "NOT_COVERED", detail: coverage.basis});
    }
    if coverage.covered && coverage.estimatedPayable > autoApprovalLimit {
        blockers.push({
            code: "EXCEEDS_AUTHORITY",
            detail: string `Payable ${coverage.estimatedPayable} exceeds your ` +
                    string `auto-approval limit of ${autoApprovalLimit}.`
        });
    }
    if claim.decision !is () {
        blockers.push({code: "ALREADY_DECIDED", detail: string `Already decided: ${claim.decision ?: ""}.`});
    }
    if claim.paymentStatus == "PAID" {
        blockers.push({code: "ALREADY_PAID", detail: "This claim has already been settled."});
    }
    if claim.status == "ESCALATED" {
        blockers.push({code: "ALREADY_ESCALATED", detail: "This claim is with a human adjuster."});
    }
    return blockers;
}

// ---------------------------------------------------------------------------
// The assessment brief
// ---------------------------------------------------------------------------

// Deliberately omits createdAt/updatedAt/paymentStatus-style bookkeeping and never
// emits null-valued fields: everything returned here is something the agent can act on.
isolated function buildAssessment(Claim claim, Customer customer, Policy policy, Coverage coverage)
        returns map<json> {
    ClaimantHistory history = getHistory(claim.customerId);
    Blocker[] blockers = blockersFor(claim, coverage);

    map<json> assessment = {
        claimId: claim.claimId,
        claimType: claim.claimType,
        description: claim.description,
        status: claim.status,
        amountClaimed: claim.amount,
        claimant: {
            customerId: customer.customerId,
            name: customer.name,
            contact: customer.email
        },
        policy: {
            policyNo: policy.policyNo,
            product: policy.product,
            deductible: policy.deductible,
            coveredPerils: policy.coveredPerils,
            exclusions: policy.exclusions.'map(e => e.clause)
        },
        coverage: {
            covered: coverage.covered,
            basis: coverage.basis,
            estimatedPayable: coverage.estimatedPayable
        },
        claimantHistory: history,
        documents: {
            received: claim.documentsReceived,
            outstanding: claim.missingDocuments
        },
        limits: {
            yourAutoApprovalLimit: autoApprovalLimit,
            aboveYourLimit: coverage.estimatedPayable > autoApprovalLimit
        },
        blockers: blockers
    };

    if claim.decision !is () {
        assessment["decision"] = {outcome: claim.decision, rationale: claim.decisionReason};
    }
    return assessment;
}

// ---------------------------------------------------------------------------
// The customer profile
// ---------------------------------------------------------------------------

// A claim counts as open for this summary if it hasn't reached a terminal
// state yet - useful for spotting a claimant with several claims in flight
// at once, which getClaimAssessment (scoped to a single claim) cannot show.
isolated function isOpenClaim(Claim claim) returns boolean =>
    claim.status != "PAID" && claim.status != "ESCALATED";

isolated function toClaimSummary(Claim claim) returns CustomerClaimSummary => {
    claimId: claim.claimId,
    claimType: claim.claimType,
    amount: claim.amount,
    status: claim.status,
    isOpen: isOpenClaim(claim)
};

# Builds the customer profile: contact details plus a summary of every claim
# this customer has on file, newest concerns first (open claims before closed
# ones). Used by getCustomerProfile so the agent can see a claimant's full
# picture - not just the one claim it was asked to assess - before deciding
# or escalating.
#
# + customer - The claimant
# + allClaims - Every claim in the system, as returned by fetchAllClaims
# + return - The profile brief
isolated function buildCustomerProfile(Customer customer, Claim[] allClaims) returns map<json> {
    CustomerClaimSummary[] claims = from Claim claim in allClaims
        where claim.customerId == customer.customerId
        order by claim.status == "PAID" || claim.status == "ESCALATED" ascending
        select toClaimSummary(claim);

    CustomerClaimSummary[] openClaims = from CustomerClaimSummary summary in claims
        where summary.isOpen
        select summary;
    int openCount = openClaims.length();

    return {
        customerId: customer.customerId,
        name: customer.name,
        email: customer.email,
        phone: customer.phone,
        totalClaims: claims.length(),
        openClaims: openCount,
        claims: claims
    };
}
