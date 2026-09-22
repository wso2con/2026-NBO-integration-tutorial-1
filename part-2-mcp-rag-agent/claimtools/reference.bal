// Underwriting reference data and the coverage rules that read it.
//
// In production these two lookups are calls to the policy administration system and
// the claims history store. They are in-code here so the demo has no extra schema to
// migrate - the shape of the tools does not change either way, which is the point.

// Every peril string is lower case; claim types are compared case-insensitively.
final readonly & map<Policy> policiesByCustomer = {
    "CUST-2001": {
        policyNo: "POL-HOME-2001",
        product: "Home Basic",
        deductible: 100.00,
        coveredPerils: ["water damage", "fire", "storm", "theft"],
        exclusions: []
    },
    "CUST-2002": {
        policyNo: "POL-HOME-2002",
        product: "Home Basic",
        deductible: 250.00,
        coveredPerils: ["water damage", "fire", "storm", "theft"],
        exclusions: []
    },
    "CUST-2003": {
        policyNo: "POL-CONTENTS-2003",
        product: "Home Contents",
        deductible: 150.00,
        coveredPerils: ["water damage", "fire", "theft"],
        exclusions: [
            {
                clause: "Clause 7.3: accidental damage to portable electronics " +
                        "(laptops, tablets, phones) is not covered under Home Contents.",
                appliesTo: ["Accidental damage"]
            }
        ]
    }
};

final readonly & map<ClaimantHistory> historyByCustomer = {
    "CUST-2001": {priorClaims12Months: 0, totalPaid12Months: 0.00, priorRejections: 0, riskFlags: []},
    "CUST-2002": {priorClaims12Months: 1, totalPaid12Months: 900.00, priorRejections: 0, riskFlags: []},
    "CUST-2003": {
        priorClaims12Months: 2,
        totalPaid12Months: 1250.00,
        priorRejections: 1,
        riskFlags: ["Two claims in the last 12 months"]
    }
};

# Returns the claimant's policy, or () if they have none on record.
#
# + customerId - The claimant
# + return - The policy, or () when the claimant has none
public isolated function getPolicy(string customerId) returns Policy? => policiesByCustomer[customerId];

# Returns the claimant's prior-claim summary, defaulting to a clean record.
#
# + customerId - The claimant
# + return - Prior claims, payouts and risk flags over the last 12 months
public isolated function getHistory(string customerId) returns ClaimantHistory =>
    historyByCustomer[customerId] ?: {
        priorClaims12Months: 0,
        totalPaid12Months: 0.00,
        priorRejections: 0,
        riskFlags: []
    };

# Decides whether a claim is covered, and for how much, against the claimant's policy.
# Exclusions are evaluated before the covered-peril list so a named exclusion always wins
# and can be quoted verbatim in the rejection.
#
# + policy - The claimant's policy
# + claim - The claim being assessed
# + return - Whether it is covered, the basis for that finding, and the payable amount
public isolated function determineCoverage(Policy policy, Claim claim) returns Coverage {
    foreach Exclusion exclusion in policy.exclusions {
        foreach string claimType in exclusion.appliesTo {
            if claimType.equalsIgnoreCaseAscii(claim.claimType) {
                return {
                    covered: false,
                    basis: exclusion.clause,
                    deductible: policy.deductible,
                    estimatedPayable: 0.00
                };
            }
        }
    }

    boolean isCoveredPeril = false;
    foreach string peril in policy.coveredPerils {
        if peril.equalsIgnoreCaseAscii(claim.claimType) {
            isCoveredPeril = true;
            break;
        }
    }

    if !isCoveredPeril {
        return {
            covered: false,
            basis: string `${claim.claimType} is not a covered peril under ${policy.product}. ` +
                    string `Covered perils are: ${string:'join(", ", ...policy.coveredPerils)}.`,
            deductible: policy.deductible,
            estimatedPayable: 0.00
        };
    }

    decimal payable = claim.amount - policy.deductible;
    return {
        covered: true,
        basis: string `${claim.claimType} is a covered peril under ${policy.product} ` +
                string `(policy ${policy.policyNo}), subject to a ${policy.deductible} deductible.`,
        deductible: policy.deductible,
        estimatedPayable: payable > 0d ? payable : 0.00
    };
}
