public type Claim record {|
    string claimId;
    string userId;
    string userName;
    decimal amount;
    string currency = "USD";
    string category;
    string description;
|};

public type ApprovalDecision record {|
    boolean approved;
    string comment;
|};
