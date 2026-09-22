// In-memory data store for the Claims backend.
//
// Replaces the previous MySQL-backed persistence (ballerinax/mysql + ballerina/sql)
// with hardcoded in-memory tables holding the same three demo claims, their
// customers, and journey steps. Function signatures are unchanged so callers
// (main.bal) did not need to change.

import ballerina/time;

// ---------------------------------------------------------------------------
// In-memory "tables"
// ---------------------------------------------------------------------------

isolated map<Claim> claimsTable = {
    "CLM-1041": {
        claimId: "CLM-1041",
        customerId: "CUST-2001",
        claimType: "Water damage",
        description: "Minor water damage to kitchen ceiling following a burst pipe.",
        amount: 450.00,
        status: "READY",
        documentsReceived: ["incident_report.pdf", "photos.zip"],
        missingDocuments: [],
        decision: (),
        decisionReason: (),
        paymentStatus: "NOT_STARTED",
        createdAt: "2026-01-05T09:00:00Z",
        updatedAt: "2026-01-05T09:00:00Z"
    },
    "CLM-1042": {
        claimId: "CLM-1042",
        customerId: "CUST-2002",
        claimType: "Water damage",
        description: "Water damage to living room flooring and furniture after storm flooding.",
        amount: 2500.00,
        status: "MISSING_DOCUMENTS",
        documentsReceived: ["incident_report.pdf"],
        missingDocuments: ["proof_of_ownership.pdf", "repair_estimate.pdf"],
        decision: (),
        decisionReason: (),
        paymentStatus: "NOT_STARTED",
        createdAt: "2026-01-06T10:30:00Z",
        updatedAt: "2026-01-06T10:30:00Z"
    },
    "CLM-1043": {
        claimId: "CLM-1043",
        customerId: "CUST-2003",
        claimType: "Accidental damage",
        description: "Accidental damage to a laptop dropped during a house move.",
        amount: 800.00,
        status: "READY",
        documentsReceived: ["incident_report.pdf", "purchase_receipt.pdf"],
        missingDocuments: [],
        decision: (),
        decisionReason: (),
        paymentStatus: "NOT_STARTED",
        createdAt: "2026-01-07T14:15:00Z",
        updatedAt: "2026-01-07T14:15:00Z"
    }
};

isolated map<Customer> customersTable = {
    "CUST-2001": {
        customerId: "CUST-2001",
        name: "Amara Okafor",
        email: "amara.okafor@example.com",
        phone: "+27-11-555-0101"
    },
    "CUST-2002": {
        customerId: "CUST-2002",
        name: "Thabo Nkosi",
        email: "thabo.nkosi@example.com",
        phone: "+27-11-555-0102"
    },
    "CUST-2003": {
        customerId: "CUST-2003",
        name: "Lindiwe Dlamini",
        email: "lindiwe.dlamini@example.com",
        phone: "+27-11-555-0103"
    }
};

// Journey steps and the next id counter are kept together behind a single
// isolated variable so both can be updated atomically within one lock.
type JourneyStepsState record {|
    int nextId;
    JourneyStep[] steps;
|};

isolated JourneyStepsState journeyStepsState = {nextId: 1, steps: []};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

isolated function currentTimestamp() returns string {
    time:Utc now = time:utcNow();
    return time:utcToString(now);
}

// Fixed seed values used to restore a demo claim to its original state.
// Only the three deterministic sample claims (README.md section 3) can be reset.
type SeedClaim record {|
    string claimType;
    string description;
    decimal amount;
    string status;
    string[] documentsReceived;
    string[] missingDocuments;
|};

final readonly & map<SeedClaim> seedClaims = {
    "CLM-1041": {
        claimType: "Water damage",
        description: "Minor water damage to kitchen ceiling following a burst pipe.",
        amount: 450.00,
        status: "READY",
        documentsReceived: ["incident_report.pdf", "photos.zip"],
        missingDocuments: []
    },
    "CLM-1042": {
        claimType: "Water damage",
        description: "Water damage to living room flooring and furniture after storm flooding.",
        amount: 2500.00,
        status: "MISSING_DOCUMENTS",
        documentsReceived: ["incident_report.pdf"],
        missingDocuments: ["proof_of_ownership.pdf", "repair_estimate.pdf"]
    },
    "CLM-1043": {
        claimType: "Accidental damage",
        description: "Accidental damage to a laptop dropped during a house move.",
        amount: 800.00,
        status: "READY",
        documentsReceived: ["incident_report.pdf", "purchase_receipt.pdf"],
        missingDocuments: []
    }
};

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

public isolated function getAllClaims() returns Claim[]|error {
    lock {
        string[] claimIds = claimsTable.keys().clone();
        claimIds = claimIds.sort();
        Claim[] claims = [];
        foreach string claimId in claimIds {
            Claim claim = claimsTable.get(claimId);
            claims.push(claim);
        }
        return claims.clone();
    }
}

public isolated function getClaim(string claimId) returns Claim|error? {
    lock {
        Claim? claim = claimsTable[claimId];
        if claim is () {
            return ();
        }
        return claim.clone();
    }
}

public isolated function getCustomer(string customerId) returns Customer|error? {
    lock {
        Customer? customer = customersTable[customerId];
        if customer is () {
            return ();
        }
        return customer.clone();
    }
}

public isolated function getJourneySteps(string claimId) returns JourneyStep[]|error {
    lock {
        JourneyStep[] steps = [];
        foreach JourneyStep step in journeyStepsState.steps {
            if step.claimId == claimId {
                steps.push(step.clone());
            }
        }
        JourneyStep[] sorted = from JourneyStep step in steps
            order by step.id ascending
            select step;
        return sorted.clone();
    }
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

public isolated function addJourneyStep(string claimId, string stepName, string status, string? detail = ())
        returns error? {
    string occurredAt = currentTimestamp();
    lock {
        int stepId = journeyStepsState.nextId;
        journeyStepsState.nextId += 1;
        journeyStepsState.steps.push({
            id: stepId,
            claimId: claimId,
            stepName: stepName,
            status: status,
            detail: detail,
            occurredAt: occurredAt
        });
    }
}

public isolated function requestDocuments(string claimId, string[] missingDocuments) returns error? {
    string[] missingDocumentsCopy = missingDocuments.clone();
    string updatedAt = currentTimestamp();
    lock {
        Claim? claim = claimsTable[claimId];
        if claim is () {
            return error(string `Claim ${claimId} not found`);
        }
        claim.status = "MISSING_DOCUMENTS";
        claim.missingDocuments = missingDocumentsCopy.clone();
        claim.updatedAt = updatedAt;
        claimsTable[claimId] = claim;
    }
    check addJourneyStep(claimId, "Documents requested", "DONE", "Notification sent to customer (mock)");
    check addJourneyStep(claimId, "Waiting for customer", "ACTIVE");
}

public isolated function documentsReceived(string claimId, string[] documents) returns error? {
    string[] & readonly documentsCopy = documents.cloneReadOnly();
    string updatedAt = currentTimestamp();
    lock {
        Claim? claim = claimsTable[claimId];
        if claim is () {
            return error(string `Claim ${claimId} not found`);
        }
        string[] merged = claim.documentsReceived.clone();
        foreach string doc in documentsCopy {
            if merged.indexOf(doc) is () {
                merged.push(doc);
            }
        }
        claim.documentsReceived = merged;
        claim.missingDocuments = [];
        claim.status = "READY";
        claim.updatedAt = updatedAt;
        claimsTable[claimId] = claim;
    }
    // Close out the ACTIVE "Waiting for customer" step opened by requestDocuments,
    // otherwise the portal timeline shows the claim as still waiting long after
    // it has been decided and paid.
    lock {
        JourneyStep[] steps = journeyStepsState.steps;
        foreach int i in 0 ..< steps.length() {
            JourneyStep step = steps[i];
            if step.claimId == claimId && step.stepName == "Waiting for customer" && step.status == "ACTIVE" {
                step.status = "DONE";
                steps[i] = step;
            }
        }
    }
    check addJourneyStep(claimId, "Documents received", "DONE", "Customer submitted the requested documents");
}

public isolated function submitDecision(string claimId, string decision, string? reason = ()) returns error? {
    string updatedAt = currentTimestamp();
    lock {
        Claim? claim = claimsTable[claimId];
        if claim is () {
            return error(string `Claim ${claimId} not found`);
        }
        claim.decision = decision;
        claim.decisionReason = reason;
        claim.status = "DECIDED";
        claim.updatedAt = updatedAt;
        claimsTable[claimId] = claim;
    }
    check addJourneyStep(claimId, "Claim decision recorded", "DONE",
        reason is () ? "Decision: " + decision : string `Decision: ${decision} - ${reason}`);
}

// Hands the claim to a human adjuster. Terminal as far as the automated flow is
// concerned: nothing downstream reads ESCALATED, it simply stops the agent.
public isolated function escalateClaim(string claimId, string reason, string summary) returns error? {
    string updatedAt = currentTimestamp();
    lock {
        Claim? claim = claimsTable[claimId];
        if claim is () {
            return error(string `Claim ${claimId} not found`);
        }
        claim.status = "ESCALATED";
        claim.decisionReason = summary;
        claim.updatedAt = updatedAt;
        claimsTable[claimId] = claim;
    }
    check addJourneyStep(claimId, "Escalated to adjuster", "DONE", string `${reason}: ${summary}`);
    check addJourneyStep(claimId, "Awaiting adjuster review", "ACTIVE");
}

public isolated function processPayment(string claimId) returns error? {
    string updatedAt = currentTimestamp();
    lock {
        Claim? claim = claimsTable[claimId];
        if claim is () {
            return error(string `Claim ${claimId} not found`);
        }
        claim.paymentStatus = "PAID";
        claim.status = "PAID";
        claim.updatedAt = updatedAt;
        claimsTable[claimId] = claim;
    }
    check addJourneyStep(claimId, "Payment processed", "DONE");
    check addJourneyStep(claimId, "Customer notified", "DONE", "Notification sent to customer (mock)");
}

public isolated function resetClaim(string claimId) returns error? {
    SeedClaim? seed = seedClaims[claimId];
    if seed is () {
        return error(string `Reset is only supported for the sample claims: ${seedClaims.keys().toBalString()}`);
    }
    string resetAt = currentTimestamp();
    lock {
        Claim? claim = claimsTable[claimId];
        if claim is () {
            return error(string `Claim ${claimId} not found`);
        }
        claim.claimType = seed.claimType;
        claim.description = seed.description;
        claim.amount = seed.amount;
        claim.status = seed.status;
        claim.documentsReceived = seed.documentsReceived.clone();
        claim.missingDocuments = seed.missingDocuments.clone();
        claim.decision = ();
        claim.decisionReason = ();
        claim.paymentStatus = "NOT_STARTED";
        claim.updatedAt = resetAt;
        claimsTable[claimId] = claim;
    }
    lock {
        journeyStepsState.steps = from JourneyStep step in journeyStepsState.steps
            where step.claimId != claimId
            select step;
    }
    check addJourneyStep(claimId, "Claim received", "DONE", "Claim submitted by customer");
    check addJourneyStep(claimId, "Claim validated", "DONE", "All required fields present");
    if seed.missingDocuments.length() > 0 {
        check addJourneyStep(claimId, "Claim data retrieved", "DONE", "Claim and customer data loaded");
        check addJourneyStep(claimId, "Missing documents identified", "DONE",
            string:'join(", ", ...seed.missingDocuments) + " missing");
        check addJourneyStep(claimId, "Documents requested", "DONE", "Notification sent to customer (mock)");
    }
}
