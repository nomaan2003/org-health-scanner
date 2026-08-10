List<Field_Usage_Signal__c> multiSignal = [
    SELECT Field_Key__c, Referenced_In_Layout__c, Has_Data__c, Referenced_In_Code__c
    FROM Field_Usage_Signal__c
    WHERE Referenced_In_Layout__c = true AND Referenced_In_Code__c = true
    LIMIT 5
];
System.debug('FIELDS WITH BOTH LAYOUT AND CODE SIGNALS: ' + multiSignal.size());
for (Field_Usage_Signal__c s : multiSignal) {
    System.debug(s.Field_Key__c + ' | Layout: ' + s.Referenced_In_Layout__c + ' | Data: ' + s.Has_Data__c + ' | Code: ' + s.Referenced_In_Code__c);
}