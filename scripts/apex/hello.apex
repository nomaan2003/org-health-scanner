FieldUsageAnalyzer.computeUsageVerdicts();

Integer likelyUnusedCount = [SELECT COUNT() FROM Field_Usage_Signal__c WHERE Is_Likely_Unused__c = true];
Integer likelyUsedCount = [SELECT COUNT() FROM Field_Usage_Signal__c WHERE Is_Likely_Unused__c = false];
System.debug('LIKELY UNUSED: ' + likelyUnusedCount);
System.debug('LIKELY USED: ' + likelyUsedCount);

List<Field_Usage_Signal__c> unusedSample = [
    SELECT Field_Key__c, Referenced_In__c, Is_Likely_Unused__c
    FROM Field_Usage_Signal__c
    WHERE Is_Likely_Unused__c = true
    LIMIT 5
];
for (Field_Usage_Signal__c s : unusedSample) {
    System.debug(s.Field_Key__c + ' -> UNUSED (referenced in: ' + s.Referenced_In__c + ')');
}