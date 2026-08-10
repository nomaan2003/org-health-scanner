List<AggregateResult> batches = [
    SELECT Scan_Batch_Id__c, COUNT(Id) recordCount
    FROM Field_Usage_Signal__c
    GROUP BY Scan_Batch_Id__c
];
for (AggregateResult ar : batches) {
    System.debug(ar.get('Scan_Batch_Id__c') + ' -> ' + ar.get('recordCount') + ' records');
}