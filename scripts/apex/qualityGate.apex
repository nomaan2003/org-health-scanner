Id scanId = OrgScanOrchestrator.runScan();
Org_Scan__c scan = [SELECT Health_Score__c, Total_Findings__c, Status__c FROM Org_Scan__c WHERE Id = :scanId];
System.debug('QUALITY_GATE_RESULT: ' + JSON.serialize(new Map<String, Object>{
    'scanId' => scanId,
    'healthScore' => scan.Health_Score__c,
    'totalFindings' => scan.Total_Findings__c,
    'status' => scan.Status__c
}));