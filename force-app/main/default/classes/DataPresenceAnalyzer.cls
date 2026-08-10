/**
 * @description Phase 2.2 - determines whether CustomFields actually contain data anywhere
 * in the org, via an existence check (SELECT Id ... WHERE Field != null LIMIT 1) rather than
 * a full COUNT(). LIMIT 1 stops at the first match, so this is inherently governor-limit-safe
 * on large objects without needing separate sampling logic.
 *
 * Chains itself via Queueable for the same reason FieldUsageAnalyzer does: 423 fields means
 * 423 queries, which exceeds what a single transaction (or a single Dev Edition chain link)
 * can safely handle. Dev Edition/Trial orgs cap chained Queueable jobs at 5 total, so
 * BATCH_SIZE is sized to fit 423 fields within that limit.
 */
public with sharing class DataPresenceAnalyzer implements Queueable {

    private static final Integer BATCH_SIZE = 90; // 423 fields / 5 max chained jobs (Dev Edition limit), rounded up with headroom
    private static final Integer MAX_CHAIN_DEPTH = 5;

    private List<Object> remainingFields;
    private String scanBatchId;
    private Integer chainDepth;

    public DataPresenceAnalyzer(List<Object> remainingFields, String scanBatchId, Integer chainDepth) {
        this.remainingFields = remainingFields;
        this.scanBatchId = scanBatchId;
        this.chainDepth = chainDepth;
    }

    /**
     * @description Entry point. Call this once with the full list of CustomField records
     * from MetadataScanner.getCustomFields().
     */
    public static String startDataPresenceScan(List<Object> allCustomFields) {
        String scanBatchId = String.valueOf(Crypto.getRandomInteger()) + '-' + System.now().getTime();
        System.enqueueJob(new DataPresenceAnalyzer(allCustomFields, scanBatchId, 1));
        return scanBatchId;
    }

    public void execute(QueueableContext context) {
        Integer processCount = Math.min(BATCH_SIZE, remainingFields.size());
        List<Object> currentBatch = new List<Object>();
        for (Integer i = 0; i < processCount; i++) {
            currentBatch.add(remainingFields.remove(0));
        }

        List<Field_Usage_Signal__c> resultsToInsert = new List<Field_Usage_Signal__c>();

        for (Object fieldObj : currentBatch) {
            Map<String, Object> fieldRecord = (Map<String, Object>) fieldObj;
            String developerName = (String) fieldRecord.get('DeveloperName');
            String tableEnumOrId = (String) fieldRecord.get('TableEnumOrId');
            String namespacePrefix = (String) fieldRecord.get('NamespacePrefix');

            if (String.isBlank(developerName) || String.isBlank(tableEnumOrId)) {
                continue; // defensive - skip malformed records rather than fail the whole batch
            }

            String fieldApiName = String.isNotBlank(namespacePrefix)
                ? namespacePrefix + '__' + developerName + '__c'
                : developerName + '__c';

            Boolean hasData = checkFieldHasData(tableEnumOrId, fieldApiName);

            resultsToInsert.add(new Field_Usage_Signal__c(
                Table_Enum_Or_Id__c = tableEnumOrId,
                Field_Developer_Name__c = fieldApiName,
                Has_Data__c = hasData,
                Scan_Batch_Id__c = scanBatchId
            ));
        }

        if (!resultsToInsert.isEmpty()) {
            insert resultsToInsert;
        }

        if (!remainingFields.isEmpty()) {
            if (chainDepth >= MAX_CHAIN_DEPTH) {
                System.debug(LoggingLevel.ERROR,
                    'DataPresenceAnalyzer scan ' + scanBatchId + ' STOPPED EARLY at chain depth ' + chainDepth
                    + '. ' + remainingFields.size() + ' fields were NOT processed. Increase BATCH_SIZE.');
                return;
            }
            System.enqueueJob(new DataPresenceAnalyzer(remainingFields, scanBatchId, chainDepth + 1));
        } else {
            System.debug('DataPresenceAnalyzer scan ' + scanBatchId + ' complete.');
        }
    }

    /**
     * @description Existence check via dynamic SOQL. Wrapped in try/catch since some
     * TableEnumOrId/field combinations may be invalid to query directly (e.g. certain
     * system or packaged objects the running user can't access), and one bad field
     * shouldn't fail the whole batch.
     */
    private Boolean checkFieldHasData(String objectName, String fieldApiName) {
        try {
            String query = 'SELECT Id FROM ' + objectName + ' WHERE ' + fieldApiName + ' != null LIMIT 1';
            List<SObject> results = Database.query(query);
            return !results.isEmpty();
        } catch (Exception e) {
            System.debug('checkFieldHasData failed for ' + objectName + '.' + fieldApiName + ': ' + e.getMessage());
            return false;
        }
    }
}