Org_Scan__c scan = [SELECT Status__c, Total_Findings__c, Health_Score__c FROM Org_Scan__c ORDER BY CreatedDate DESC LIMIT 1];
System.debug('SCAN STATUS: ' + scan.Status__c + ' | TOTAL: ' + scan.Total_Findings__c + ' | HEALTH SCORE: ' + scan.Health_Score__c);

List<AggregateResult> bySeverity = [
    SELECT Severity__c, COUNT(Id) cnt
    FROM Debt_Finding__c
    GROUP BY Severity__c
];
for (AggregateResult ar : bySeverity) {
    System.debug(ar.get('Severity__c') + ': ' + ar.get('cnt'));
}