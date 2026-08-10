Integer totalRecords = [SELECT COUNT() FROM Field_Usage_Signal__c];
System.debug('TOTAL RECORDS: ' + totalRecords);

Integer referencedTrue = [SELECT COUNT() FROM Field_Usage_Signal__c WHERE Referenced_In_Code__c = true];
Integer referencedFalse = [SELECT COUNT() FROM Field_Usage_Signal__c WHERE Referenced_In_Code__c = false];
System.debug('REFERENCED IN CODE = TRUE: ' + referencedTrue);
System.debug('REFERENCED IN CODE = FALSE: ' + referencedFalse);

List<Field_Usage_Signal__c> sample = [
    SELECT Table_Enum_Or_Id__c, Field_Developer_Name__c, Referenced_In_Code__c
    FROM Field_Usage_Signal__c
    WHERE Referenced_In_Code__c = true
    LIMIT 10
];
for (Field_Usage_Signal__c s : sample) {
    System.debug(s.Table_Enum_Or_Id__c + '.' + s.Field_Developer_Name__c + ' -> referencedInCode: true');
}