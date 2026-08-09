List<Object> classes = MetadataScanner.getApexClasses();
System.debug('APEX CLASS COUNT: ' + classes.size());
if (!classes.isEmpty()) {
    System.debug('FIRST CLASS: ' + JSON.serialize(classes[0]));
}

List<Object> coverage = MetadataScanner.getApexCodeCoverage();
System.debug('COVERAGE RECORD COUNT: ' + coverage.size());
if (!coverage.isEmpty()) {
    System.debug('FIRST COVERAGE: ' + JSON.serialize(coverage[0]));
}