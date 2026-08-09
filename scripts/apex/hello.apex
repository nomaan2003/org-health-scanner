List<Object> fields = MetadataScanner.getCustomFields();
System.debug('CUSTOM FIELD COUNT: ' + fields.size());
if (!fields.isEmpty()) {
    System.debug('FIRST FIELD: ' + JSON.serialize(fields[0]));
}