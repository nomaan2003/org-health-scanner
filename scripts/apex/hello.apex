Id scanId = OrgScanOrchestrator.runScan();
List<Remediation_Action__c> actions = RemediationGenerator.generateAllRemediations(scanId);
System.debug('Actions generated: ' + actions.size());
for (Remediation_Action__c a : actions) {
    System.debug(a.Action_Type__c + ' -> ' + a.Debt_Finding__c);
}