// Types for the claims-handling toolset.
//
// Two things here are load-bearing for the demo:
//
//   1. `Decision` and `EscalationReason` are Ballerina enums, so ballerina/mcp's
//      schema generator emits them as {"type":"string","enum":[...]} in the tool's
//      input schema. The model cannot invent a third decision value.
//   2. `ToolResponse` is the single envelope every tool returns - including when it
//      refuses. See the note in main.bal on why a refusal must not be an `error`.

# The only two decisions this agent may record itself. Anything else is an escalation.
public enum Decision {
    APPROVED,
    REJECTED
}

# Why a claim is being handed to a human adjuster.
public enum EscalationReason {
    EXCEEDS_AUTHORITY,
    COVERAGE_AMBIGUOUS,
    SUSPECTED_FRAUD,
    CLAIMANT_DISPUTE
}

// ---------------------------------------------------------------------------
// The uniform tool envelope
// ---------------------------------------------------------------------------

// Naming the exact tool and arguments that would unblock the caller is what turns a
// refusal into a one-turn recovery instead of three turns of guessing.
public type Remedy record {|
    string tool;
    map<json> arguments;
|};

public type Blocker record {|
    string code;
    string detail;
|};

public type ToolResponse record {|
    // "OK" or "REFUSED".
    string status;
    string code;
    string message;
    Blocker[] blockers?;
    Remedy remedy?;
    json claim?;
    json assessment?;
|};

// ---------------------------------------------------------------------------
// Claims backend projections
// ---------------------------------------------------------------------------

// Mirrors claimapi's Claim record so responses data-bind directly.
public type Claim record {|
    string claimId;
    string customerId;
    string claimType;
    string description;
    decimal amount;
    string status;
    string[] documentsReceived;
    string[] missingDocuments;
    string? decision;
    string? decisionReason;
    string paymentStatus;
    string createdAt;
    string updatedAt;
|};

public type Customer record {|
    string customerId;
    string name;
    string email;
    string phone;
|};

// ---------------------------------------------------------------------------
// Customer profile (see getCustomerProfile in main.bal)
// ---------------------------------------------------------------------------

# A short summary of one of the customer's claims, for the customer profile view.
# Deliberately smaller than the full Claim record - just enough to spot patterns
# like several simultaneously open claims.
public type CustomerClaimSummary record {|
    string claimId;
    string claimType;
    decimal amount;
    string status;
    boolean isOpen;
|};

// ---------------------------------------------------------------------------
// Underwriting reference data (see reference.bal)
// ---------------------------------------------------------------------------

public type Exclusion record {|
    // Prose the agent can quote back to the claimant, clause number included.
    string clause;
    // Claim types this exclusion bites on.
    string[] appliesTo;
|};

public type Policy record {|
    string policyNo;
    string product;
    decimal deductible;
    string[] coveredPerils;
    Exclusion[] exclusions;
|};

public type ClaimantHistory record {|
    int priorClaims12Months;
    decimal totalPaid12Months;
    int priorRejections;
    string[] riskFlags;
|};

public type Coverage record {|
    boolean covered;
    // Always populated: the agent is expected to quote this in its rationale.
    string basis;
    decimal deductible;
    decimal estimatedPayable;
|};
