Integer totalCount = [SELECT COUNT() FROM Field_Usage_Signal__c];
System.debug('TOTAL SIGNAL RECORDS: ' + totalCount);

List<Field_Usage_Signal__c> sample = [
    SELECT Table_Enum_Or_Id__c, Field_Developer_Name__c, Referenced_In_Layout__c
    FROM Field_Usage_Signal__c
    ORDER BY Table_Enum_Or_Id__c
    LIMIT 10
];
for (Field_Usage_Signal__c s : sample) {
    System.debug(s.Table_Enum_Or_Id__c + '.' + s.Field_Developer_Name__c + ' -> ' + s.Referenced_In_Layout__c);
}