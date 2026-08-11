/**
 * @description Phase 2.5 - ties together the 4 Phase 2 analyzers into one scan run,
 * writing results into Debt_Finding__c under a single Org_Scan__c record.
 *
 * SCOPING NOTE: FieldUsageAnalyzer's Layout-usage and Data-presence signals are gathered
 * via async Queueable chains (Phase 2.2) and can't be synchronously awaited from here.
 * This orchestrator runs the 3 fully-synchronous pieces (Code-usage, Flow health, Apex
 * health) plus computeUsageVerdicts() - which reads whatever Layout/Data-presence signals
 * are already sitting in Field_Usage_Signal__c from the most recent run of those scans.
 * A future refinement could have the last chained Queueable job in each of those scans
 * kick off the rest of the orchestration automatically.
 */
public with sharing class OrgScanOrchestrator {

    /**
     * @description Entry point. Creates an Org_Scan__c record, runs all synchronous
     * analyzers, writes findings, and finalizes the scan record.
     * @return The Id of the created Org_Scan__c record.
     */
   public static Id runScan() {
    List<Debt_Finding__c> allFindings = new List<Debt_Finding__c>();

    try {
        // Callout-only analyzers first, in any order among themselves
        List<FlowHealthAnalyzer.FlowFinding> flowFindings = FlowHealthAnalyzer.runFlowHealthScan();
        List<ApexHealthAnalyzer.ApexFinding> apexFindings = ApexHealthAnalyzer.runApexHealthScan();

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

        if (!allFindings.isEmpty()) {
            insert allFindings;
        }

        scan.Status__c = 'Completed';
        scan.Total_Findings__c = allFindings.size();
        scan.Health_Score__c = calculateHealthScore(allFindings.size());
        update scan;

        return scan.Id;

    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'OrgScanOrchestrator failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
        throw e;
    }
}

    /**
     * @description Converts Field_Usage_Signal__c rows flagged Is_Likely_Unused__c into
     * Debt_Finding__c records.
     */
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

    /**
     * @description Converts FlowHealthAnalyzer.FlowFinding results into Debt_Finding__c.
     */
    private static List<Debt_Finding__c> buildFlowFindings(Id scanId, List<FlowHealthAnalyzer.FlowFinding> flowFindings) {
        List<Debt_Finding__c> findings = new List<Debt_Finding__c>();

        for (FlowHealthAnalyzer.FlowFinding f : flowFindings) {
            String severity = f.findingType == 'Overlapping Trigger' ? 'High'
                : f.findingType == 'Missing Fault Path' ? 'Medium'
                : 'Low'; // Safe To Delete

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

    /**
     * @description Converts ApexHealthAnalyzer.ApexFinding results into Debt_Finding__c.
     */
    private static List<Debt_Finding__c> buildApexFindings(Id scanId, List<ApexHealthAnalyzer.ApexFinding> apexFindings) {
        List<Debt_Finding__c> findings = new List<Debt_Finding__c>();

        for (ApexHealthAnalyzer.ApexFinding f : apexFindings) {
            String category = f.findingType == 'Low Coverage' ? 'Low Test Coverage'
                : f.findingType == 'Hardcoded Id' ? 'Hardcoded Id'
                : 'Security Gap'; // SOQL In Loop - closest available category, approximation

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
     * @description Simple health score: starts at 100, deducts 1 point per finding,
     * floored at 0. A placeholder formula - Phase 3's HealthScoreCalculator will likely
     * replace this with something that weights severity.
     */
    private static Decimal calculateHealthScore(Integer findingCount) {
        Decimal score = 100 - findingCount;
        return score < 0 ? 0 : score;
    }
}