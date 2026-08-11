Org_Scan__c scan = [SELECT Status__c, Total_Findings__c, Health_Score__c FROM Org_Scan__c ORDER BY CreatedDate DESC LIMIT 1];
System.debug('SCAN STATUS: ' + scan.Status__c + ' | TOTAL: ' + scan.Total_Findings__c + ' | HEALTH SCORE: ' + scan.Health_Score__c);

List<AggregateResult> byCategory = [
    SELECT Category__c, COUNT(Id) cnt
    FROM Debt_Finding__c
    GROUP BY Category__c
];
for (AggregateResult ar : byCategory) {
    System.debug(ar.get('Category__c') + ': ' + ar.get('cnt'));
}