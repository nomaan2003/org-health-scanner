public with sharing class OrgScanDashboardController {

    @AuraEnabled(cacheable=true)
    public static Org_Scan__c getLatestScan() {
        List<Org_Scan__c> scans = [
            SELECT Id, Health_Score__c, Total_Findings__c, Scan_Date__c, Status__c
            FROM Org_Scan__c
            WHERE Status__c = 'Completed'
            ORDER BY Scan_Date__c DESC
            LIMIT 1
        ];
        return scans.isEmpty() ? null : scans[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<Debt_Finding__c> getFindings(Id scanId) {
        List<Debt_Finding__c> allFindings = [
            SELECT Category__c, Severity__c, Component_Type__c, Component_Name__c,
                   Description__c, Status__c
            FROM Debt_Finding__c
            WHERE Org_Scan__c = :scanId
        ];

        Map<String, Integer> severityOrder = new Map<String, Integer>{
            'Critical' => 1, 'High' => 2, 'Medium' => 3, 'Low' => 4
        };

        List<Debt_Finding__c> sorted = new List<Debt_Finding__c>(allFindings);
        sorted.sort(new SeverityComparator(severityOrder));
        return sorted;
    }

    private class SeverityComparator implements Comparator<Debt_Finding__c> {
        private Map<String, Integer> severityOrder;
        public SeverityComparator(Map<String, Integer> severityOrder) {
            this.severityOrder = severityOrder;
        }
        public Integer compare(Debt_Finding__c a, Debt_Finding__c b) {
            Integer orderA = severityOrder.containsKey(a.Severity__c) ? severityOrder.get(a.Severity__c) : 5;
            Integer orderB = severityOrder.containsKey(b.Severity__c) ? severityOrder.get(b.Severity__c) : 5;
            return orderA - orderB;
        }
    }
}