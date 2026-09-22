
// Amani Insurance backend REST APIs (README.md sections 3 and 25).
//
// Two independent services on two listeners/ports within this package:
//   /claims    on claimsListener (servicePort, default 8080) - claim lifecycle
//   /customers on customersListener (customersServicePort, default 8081) -
//              claimant/policyholder lookups
//
// Split so each can be demoed, scaled, and reasoned about as a distinct
// backend even though they currently share one in-memory data store (db.bal).

import ballerina/http;
import ballerina/log;

configurable int servicePort = 8080;
configurable int customersServicePort = 8081;

listener http:Listener claimsListener = new (servicePort);
listener http:Listener customersListener = new (customersServicePort);

@http:ServiceConfig {
    cors: {
        allowMethods: ["GET", "POST"],
        allowOrigins: ["*"]
    }
}
service /claims on claimsListener {

    resource function get .() returns Claim[]|http:InternalServerError {
        Claim[]|error claims = getAllClaims();
        if claims is error {
            log:printError("failed to load claims", claims);
            return <http:InternalServerError>{body: {message: "failed to load claims"}};
        }
        return claims;
    }

    resource function get [string claimId]() returns Claim|http:NotFound|http:InternalServerError {
        Claim?|error claim = getClaim(claimId);
        if claim is error {
            log:printError("failed to load claim", claim, claimId = claimId);
            return <http:InternalServerError>{body: {message: "failed to load claim"}};
        }
        if claim is () {
            return <http:NotFound>{body: {message: string `claim ${claimId} not found`}};
        }
        return claim;
    }

    resource function get [string claimId]/journey() returns JourneyStep[]|http:InternalServerError {
        JourneyStep[]|error steps = getJourneySteps(claimId);
        if steps is error {
            log:printError("failed to load journey", steps, claimId = claimId);
            return <http:InternalServerError>{body: {message: "failed to load claim journey"}};
        }
        return steps;
    }

    resource function post [string claimId]/request\-documents(@http:Payload RequestDocumentsRequest payload)
            returns Claim|http:NotFound|http:InternalServerError {
        error? result = requestDocuments(claimId, payload.missingDocuments);
        if result is error {
            log:printError("failed to request documents", result, claimId = claimId);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        return check reloadClaim(claimId);
    }

    resource function post [string claimId]/documents\-received(@http:Payload DocumentsReceivedRequest payload)
            returns Claim|http:NotFound|http:InternalServerError {
        error? result = documentsReceived(claimId, payload.documents);
        if result is error {
            log:printError("failed to record documents received", result, claimId = claimId);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        return check reloadClaim(claimId);
    }

    resource function post [string claimId]/decision(@http:Payload DecisionRequest payload)
            returns Claim|http:NotFound|http:InternalServerError {
        error? result = submitDecision(claimId, payload.decision, payload.reason);
        if result is error {
            log:printError("failed to submit decision", result, claimId = claimId);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        return check reloadClaim(claimId);
    }

    resource function post [string claimId]/escalate(@http:Payload EscalateRequest payload)
            returns Claim|http:NotFound|http:InternalServerError {
        error? result = escalateClaim(claimId, payload.reason, payload.summary);
        if result is error {
            log:printError("failed to escalate claim", result, claimId = claimId);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        return check reloadClaim(claimId);
    }

    resource function post [string claimId]/payment() returns Claim|http:NotFound|http:InternalServerError {
        error? result = processPayment(claimId);
        if result is error {
            log:printError("failed to process payment", result, claimId = claimId);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        return check reloadClaim(claimId);
    }

    resource function post [string claimId]/reset() returns Claim|http:NotFound|http:InternalServerError {
        error? result = resetClaim(claimId);
        if result is error {
            log:printError("failed to reset claim", result, claimId = claimId);
            return <http:InternalServerError>{body: {message: result.message()}};
        }
        return check reloadClaim(claimId);
    }

    resource function get health() returns json {
        return {status: "UP"};
    }
}

service /customers on customersListener {

    resource function get [string customerId]() returns Customer|http:NotFound|http:InternalServerError {
        Customer?|error customer = getCustomer(customerId);
        if customer is error {
            log:printError("failed to load customer", customer, customerId = customerId);
            return <http:InternalServerError>{body: {message: "failed to load customer"}};
        }
        if customer is () {
            return <http:NotFound>{body: {message: string `customer ${customerId} not found`}};
        }
        return customer;
    }

    resource function get health() returns json {
        return {status: "UP"};
    }
}

function reloadClaim(string claimId) returns Claim|http:NotFound|http:InternalServerError {
    Claim?|error claim = getClaim(claimId);
    if claim is error {
        return <http:InternalServerError>{body: {message: "failed to reload claim after update"}};
    }
    if claim is () {
        return <http:NotFound>{body: {message: string `claim ${claimId} not found`}};
    }
    return claim;
}

