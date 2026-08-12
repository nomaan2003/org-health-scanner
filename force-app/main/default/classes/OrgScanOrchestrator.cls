public with sharing class OrgScanOrchestrator {

   public static Id runScan() {
    List<Debt_Finding__c> allFindings = new List<Debt_Finding__c>();

    try {
        // Callout-only analyzers first, in any order among themselves
        List<FlowHealthAnalyzer.FlowFinding> flowFindings = FlowHealthAnalyzer.runFlowHealthScan();
        List<ApexHealthAnalyzer.ApexFinding> apexFindings = ApexHealthAnalyzer.runApexHealthScan();

        // SecurityAnalyzer's checks: check1 and check3 are pure SOQL (no callouts),
        // but check2 (API/IP restriction check) makes Tooling API callouts - so the
        // whole SecurityAnalyzer batch runs here, in the callout phase.
        List<SecurityAnalyzer.SecurityFinding> overPrivilegedFindings = SecurityAnalyzer.checkOverPrivilegedUsers();
        List<SecurityAnalyzer.SecurityFinding> apiIpFindings = SecurityAnalyzer.checkApiAccessWithoutIpRestrictions();
        List<SecurityAnalyzer.SecurityFinding> dormantFindings = SecurityAnalyzer.checkDormantHighPrivilegeAccounts();

        // CodeUsageAnalyzer runs LAST among callout-based work, since it ends with its
        // own upsert - nothing after this point in the callout chain can make callouts.
        CodeUsageAnalyzer.runCodeUsageScan();

        // DML-only from here on - safe after all callouts are done
        FieldUsageAnalyzer.computeUsageVerdicts();

        Org_Scan__c scan = new Org_Scan__c(
            Status__c = 'Running',
            Scan_Date__c = Datetime.now(),
            Triggered_By__c = 'Manual'
        );
        insert scan;

        allFindings.addAll(buildFieldUsageFindings(scan.Id));
        allFindings.addAll(buildFlowFindings(scan.Id, flowFindings));
        allFindings.addAll(buildApexFindings(scan.Id, apexFindings));
        allFindings.addAll(buildSecurityFindings(scan.Id, overPrivilegedFindings));
        allFindings.addAll(buildSecurityFindings(scan.Id, apiIpFindings));
        allFindings.addAll(buildSecurityFindings(scan.Id, dormantFindings));

        if (!allFindings.isEmpty()) {
            insert allFindings;
        }

        scan.Status__c = 'Completed';
        scan.Total_Findings__c = allFindings.size();
        scan.Health_Score__c = HealthScoreCalculator.calculateScoreFromSeverities(allFindings);
        update scan;

        return scan.Id;

    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'OrgScanOrchestrator failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
        throw e;
    }
}

    private static List<Debt_Finding__c> buildFieldUsageFindings(Id scanId) {
        List<Debt_Finding__c> findings = new List<Debt_Finding__c>();

        List<Field_Usage_Signal__c> unusedFields = [
            SELECT Table_Enum_Or_Id__c, Field_Developer_Name__c, Referenced_In__c
            FROM Field_Usage_Signal__c
            WHERE Is_Likely_Unused__c = true
        ];

        for (Field_Usage_Signal__c signal : unusedFields) {
            findings.add(new Debt_Finding__c(
                Org_Scan__c = scanId,
                Category__c = 'Unused Field',
                Severity__c = 'Low',
                Component_Type__c = 'CustomField',
                Component_Name__c = signal.Table_Enum_Or_Id__c + '.' + signal.Field_Developer_Name__c,
                Description__c = 'Field appears unused: not referenced on any layout, holds no data, and not referenced in Apex or Flow code.',
                Status__c = 'Open',
                AutoFixable__c = false
            ));
        }

        return findings;
    }

    private static List<Debt_Finding__c> buildFlowFindings(Id scanId, List<FlowHealthAnalyzer.FlowFinding> flowFindings) {
        List<Debt_Finding__c> findings = new List<Debt_Finding__c>();

        for (FlowHealthAnalyzer.FlowFinding f : flowFindings) {
            String severity = f.findingType == 'Overlapping Trigger' ? 'High'
                : f.findingType == 'Missing Fault Path' ? 'Medium'
                : 'Low';

            findings.add(new Debt_Finding__c(
                Org_Scan__c = scanId,
                Category__c = 'Orphaned Flow',
                Severity__c = severity,
                Component_Type__c = 'Flow',
                Component_Name__c = f.flowName,
                Description__c = '[' + f.findingType + '] ' + f.description,
                Status__c = 'Open',
                AutoFixable__c = false
            ));
        }

        return findings;
    }

    private static List<Debt_Finding__c> buildApexFindings(Id scanId, List<ApexHealthAnalyzer.ApexFinding> apexFindings) {
        List<Debt_Finding__c> findings = new List<Debt_Finding__c>();

        for (ApexHealthAnalyzer.ApexFinding f : apexFindings) {
            String category = f.findingType == 'Low Coverage' ? 'Low Test Coverage'
                : f.findingType == 'Hardcoded Id' ? 'Hardcoded Id'
                : 'Security Gap';

            String severity = f.findingType == 'Low Coverage' ? 'Medium' : 'High';

            findings.add(new Debt_Finding__c(
                Org_Scan__c = scanId,
                Category__c = category,
                Severity__c = severity,
                Component_Type__c = 'ApexClass',
                Component_Name__c = f.className,
                Description__c = '[' + f.findingType + '] ' + f.description,
                Status__c = 'Open',
                AutoFixable__c = false
            ));
        }

        return findings;
    }

    /**
     * @description Converts SecurityAnalyzer.SecurityFinding results into Debt_Finding__c
     * under Category__c = 'Security Gap'. Shared by all 3 SecurityAnalyzer checks.
     */
    private static List<Debt_Finding__c> buildSecurityFindings(Id scanId, List<SecurityAnalyzer.SecurityFinding> securityFindings) {
        List<Debt_Finding__c> findings = new List<Debt_Finding__c>();

        for (SecurityAnalyzer.SecurityFinding f : securityFindings) {
            findings.add(new Debt_Finding__c(
                Org_Scan__c = scanId,
                Category__c = 'Security Gap',
                Severity__c = f.severity,
                Component_Type__c = 'User',
                Component_Name__c = f.userName != null ? f.userName : f.permissionSetOrProfileName,
                Description__c = '[' + f.riskType + '] ' + f.description,
                Status__c = 'Open',
                AutoFixable__c = false
            ));
        }

        return findings;
    }
}