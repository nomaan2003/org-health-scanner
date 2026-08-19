/**
 * @description Phase 3 - computes a 0-100 org health score from Debt_Finding__c severities,
 * replacing the placeholder "100 minus finding count" formula from OrgScanOrchestrator.
 * Uses severity-weighted, diminishing-returns scoring so large finding counts don't all
 * collapse to the same score - a org with 500 low-severity findings scores meaningfully
 * higher than one with 50 critical findings.
 */
public with sharing class HealthScoreCalculator {

    private static final Map<String, Decimal> SEVERITY_WEIGHTS = new Map<String, Decimal>{
        'Critical' => 10,
        'High' => 5,
        'Medium' => 2,
        'Low' => 1
    };

    /**
     * @description Computes the health score for a given Org_Scan__c by summing severity
     * weights across its Debt_Finding__c records, then applying a diminishing-returns
     * formula: score = 100 * (100 / (100 + totalWeight)). Zero findings scores 100;
     * score approaches 0 asymptotically as totalWeight grows, never clipping hard.
     * @param scanId The Org_Scan__c Id whose findings should be scored.
     * @return A score between 0 and 100, rounded to 1 decimal place.
     */
    public static Decimal calculateScore(Id scanId) {
        List<Debt_Finding__c> findings = [
            SELECT Severity__c
            FROM Debt_Finding__c
            WHERE Org_Scan__c = :scanId
        ];

        return calculateScoreFromSeverities(findings);
    }

    /**
     * @description Same calculation, but takes an in-memory list directly - useful when
     * called from OrgScanOrchestrator before the findings are queried back from the
     * database (e.g. right after insert, in the same transaction).
     */
    public static Decimal calculateScoreFromSeverities(List<Debt_Finding__c> findings) {
        Decimal totalWeight = 0;

        for (Debt_Finding__c finding : findings) {
            Decimal weight = SEVERITY_WEIGHTS.containsKey(finding.Severity__c)
                ? SEVERITY_WEIGHTS.get(finding.Severity__c)
                : 1; // unknown severity - treat as Low rather than ignore
            totalWeight += weight;
        }

        Decimal score = 100 * (100 / (100 + totalWeight));
        return score.setScale(1);
    }
        /**
     * @description Computes per-category sub-scores (for the radar chart) using the same
     * severity weights and diminishing-returns formula as the overall score, but scoped to
     * each of the four dashboard categories: Automation, Data Model, Code, Security.
     * @param findings Full list of Debt_Finding__c for the scan (with Severity__c and Category__c).
     * @return A SubScoreResult wrapper with one Decimal per dashboard category.
     */
    public class SubScoreResult {
        public Decimal automationHealth;
        public Decimal dataModelHealth;
        public Decimal codeHealth;
        public Decimal securityHealth;
    }

    private static final Map<String, Set<String>> CATEGORY_GROUPS = new Map<String, Set<String>>{
        'automation' => new Set<String>{ 'Orphaned Flow' },
        'dataModel'  => new Set<String>{ 'Unused Field', 'Naming Convention' },
        'code'       => new Set<String>{ 'Low Test Coverage', 'Hardcoded Id' },
        'security'   => new Set<String>{ 'Security Gap' }
    };

    public static SubScoreResult calculateSubScores(List<Debt_Finding__c> findings) {
        SubScoreResult result = new SubScoreResult();
        result.automationHealth = scoreForGroup(findings, CATEGORY_GROUPS.get('automation'));
        result.dataModelHealth  = scoreForGroup(findings, CATEGORY_GROUPS.get('dataModel'));
        result.codeHealth       = scoreForGroup(findings, CATEGORY_GROUPS.get('code'));
        result.securityHealth   = scoreForGroup(findings, CATEGORY_GROUPS.get('security'));
        return result;
    }

    private static Decimal scoreForGroup(List<Debt_Finding__c> findings, Set<String> categories) {
        List<Debt_Finding__c> subset = new List<Debt_Finding__c>();
        for (Debt_Finding__c f : findings) {
            if (categories.contains(f.Category__c)) {
                subset.add(f);
            }
        }
        return calculateScoreFromSeverities(subset);
    }
}