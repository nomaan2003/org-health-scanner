List<FlowHealthAnalyzer.FlowFinding> findings = FlowHealthAnalyzer.runFlowHealthScan();
System.debug('TOTAL FINDINGS: ' + findings.size());

Integer byType = 0;
Map<String, Integer> countByType = new Map<String, Integer>();
for (FlowHealthAnalyzer.FlowFinding f : findings) {
    Integer current = countByType.containsKey(f.findingType) ? countByType.get(f.findingType) : 0;
    countByType.put(f.findingType, current + 1);
}
for (String type : countByType.keySet()) {
    System.debug(type + ': ' + countByType.get(type));
}