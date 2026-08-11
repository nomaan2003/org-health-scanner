/**
 * @description Phase 2.4 - Apex code health checks: coverage below 75%, hardcoded
 * Salesforce Ids, and SOQL queries inside loops. Runs synchronously - ApexClass.Body
 * and ApexCodeCoverageAggregate are both bulk-queryable, no chaining needed.
 */
public with sharing class ApexHealthAnalyzer {

    private static final Decimal COVERAGE_THRESHOLD = 75.0;

    public class ApexFinding {
        public String classId;
        public String className;
        public String findingType; // 'Low Coverage', 'Hardcoded Id', 'SOQL In Loop'
        public String description;

        public ApexFinding(String classId, String className, String findingType, String description) {
            this.classId = classId;
            this.className = className;
            this.findingType = findingType;
            this.description = description;
        }
    }

    /**
     * @description Entry point. Runs all 3 checks and returns the combined findings.
     */
    public static List<ApexFinding> runApexHealthScan() {
        List<ApexFinding> findings = new List<ApexFinding>();

        findings.addAll(checkCoverage());
        findings.addAll(checkHardcodedIdsAndSoqlInLoops());

        return findings;
    }

    /**
     * @description Flags classes with less than 75% code coverage. Joins ApexClass
     * (for names) with ApexCodeCoverageAggregate (for line counts) by Id.
     */
    private static List<ApexFinding> checkCoverage() {
        List<ApexFinding> findings = new List<ApexFinding>();

        Map<String, String> classNameById = new Map<String, String>();
        List<Object> apexClasses = MetadataScanner.getApexClasses();
        for (Object classObj : apexClasses) {
            Map<String, Object> cls = (Map<String, Object>) classObj;
            classNameById.put((String) cls.get('Id'), (String) cls.get('Name'));
        }

        List<Object> coverageRecords = MetadataScanner.getApexCodeCoverage();
        for (Object covObj : coverageRecords) {
            Map<String, Object> cov = (Map<String, Object>) covObj;
            String classId = (String) cov.get('ApexClassOrTriggerId');
            Integer covered = cov.get('NumLinesCovered') != null ? (Integer) cov.get('NumLinesCovered') : 0;
            Integer uncovered = cov.get('NumLinesUncovered') != null ? (Integer) cov.get('NumLinesUncovered') : 0;
            Integer totalLines = covered + uncovered;

            if (totalLines == 0) {
                continue; // no executable lines to measure - skip rather than divide by zero
            }

            Decimal percentage = (Decimal.valueOf(covered) / Decimal.valueOf(totalLines)) * 100;
            percentage = percentage.setScale(1);

            if (percentage < COVERAGE_THRESHOLD) {
                String className = classNameById.containsKey(classId) ? classNameById.get(classId) : classId;
                findings.add(new ApexFinding(
                    classId,
                    className,
                    'Low Coverage',
                    'Coverage is ' + percentage + '% (below ' + COVERAGE_THRESHOLD + '% threshold)'
                ));
            }
        }

        return findings;
    }

    /**
     * @description Text-scans every class body for hardcoded Salesforce Ids (15 or 18
     * character quoted string literals) and SOQL queries that appear inside a loop's
     * braces (a classic governor-limit anti-pattern).
     */
    private static List<ApexFinding> checkHardcodedIdsAndSoqlInLoops() {
        List<ApexFinding> findings = new List<ApexFinding>();

        Pattern hardcodedIdPattern = Pattern.compile('\'[a-zA-Z0-9]{15}\'|\'[a-zA-Z0-9]{18}\'');

        List<Object> classBodies = MetadataScanner.getApexClassBodies();
        for (Object classObj : classBodies) {
            Map<String, Object> cls = (Map<String, Object>) classObj;
            String classId = (String) cls.get('Id');
            String className = (String) cls.get('Name');
            String body = (String) cls.get('Body');

            if (String.isBlank(body)) {
                continue;
            }

            // Hardcoded Id check
            Matcher idMatcher = hardcodedIdPattern.matcher(body);
            Integer hardcodedIdCount = 0;
            while (idMatcher.find()) {
                hardcodedIdCount++;
            }
            if (hardcodedIdCount > 0) {
                findings.add(new ApexFinding(
                    classId,
                    className,
                    'Hardcoded Id',
                    hardcodedIdCount + ' hardcoded Id literal(s) found in class body'
                ));
            }

            // SOQL-in-loop check - line-by-line brace tracking
            List<String> soqlInLoopLines = findSoqlInLoops(body);
            for (String lineInfo : soqlInLoopLines) {
                findings.add(new ApexFinding(
                    classId,
                    className,
                    'SOQL In Loop',
                    'SOQL query found inside a loop: ' + lineInfo
                ));
            }
        }

        return findings;
    }

    /**
     * @description Scans a class body line by line, tracking brace depth to determine
     * whether each line sits inside an open for/while loop. Returns a description of
     * each line where a SOQL query ([SELECT) appears while inside a loop's braces.
     * Heuristic, not a full parser - matches on textual patterns, so edge cases (e.g.
     * SOQL split across multiple lines, loops without braces) may be missed or
     * over-flagged, but catches the common case the guide describes.
     */
    private static List<String> findSoqlInLoops(String body) {
        List<String> results = new List<String>();
        List<String> lines = body.split('\n');

        Integer depth = 0;
        List<Integer> loopStartDepths = new List<Integer>();
        Pattern loopPattern = Pattern.compile('(?i)\\b(for|while)\\s*\\(');

        for (Integer lineNum = 0; lineNum < lines.size(); lineNum++) {
            String line = lines[lineNum];
            Boolean lineStartsLoop = loopPattern.matcher(line).find();
            Boolean markedThisLine = false;

            for (Integer i = 0; i < line.length(); i++) {
                String ch = line.substring(i, i + 1);
                if (ch == '{') {
                    depth++;
                    if (lineStartsLoop && !markedThisLine) {
                        loopStartDepths.add(depth);
                        markedThisLine = true;
                    }
                } else if (ch == '}') {
                    if (!loopStartDepths.isEmpty() && loopStartDepths[loopStartDepths.size() - 1] == depth) {
                        loopStartDepths.remove(loopStartDepths.size() - 1);
                    }
                    depth--;
                }
            }

            if (!loopStartDepths.isEmpty() && line.toUpperCase().contains('[SELECT')) {
                results.add('line ' + (lineNum + 1) + ': ' + line.trim());
            }
        }

        return results;
    }
}