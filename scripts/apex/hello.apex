List<ApexHealthAnalyzer.ApexFinding> findings = ApexHealthAnalyzer.runApexHealthScan();
System.debug('TOTAL FINDINGS: ' + findings.size());

Map<String, Integer> countByType = new Map<String, Integer>();
for (ApexHealthAnalyzer.ApexFinding f : findings) {
    Integer current = countByType.containsKey(f.findingType) ? countByType.get(f.findingType) : 0;
    countByType.put(f.findingType, current + 1);
}
for (String type : countByType.keySet()) {
    System.debug(type + ': ' + countByType.get(type));
}

// Sample a few of each type
Integer shown = 0;
for (ApexHealthAnalyzer.ApexFinding f : findings) {
    if (shown >= 8) break;
    System.debug(f.findingType + ' | ' + f.className + ' | ' + f.description);
    shown++;
}