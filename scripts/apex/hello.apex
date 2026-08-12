Id scanId = OrgScanOrchestrator.runScan();
System.debug('Scan Id: ' + scanId);

Org_Scan__c scan = [SELECT Health_Score__c, Total_Findings__c, Status__c FROM Org_Scan__c WHERE Id = :scanId];
System.debug('Status: ' + scan.Status__c + ', Total: ' + scan.Total_Findings__c + ', Score: ' + scan.Health_Score__c);

Integer securityCount = [SELECT COUNT() FROM Debt_Finding__c WHERE Org_Scan__c = :scanId AND Category__c = 'Security Gap'];
System.debug('Security Gap findings this scan: ' + securityCount);