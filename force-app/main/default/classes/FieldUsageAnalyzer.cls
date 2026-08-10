/**
 * @description Phase 2.2 - determines whether CustomFields are referenced on any page Layout.
 * Chains itself via Queueable since checking Metadata on ~300 layouts requires one callout
 * per layout (Layout.Metadata is a single-record-query-only field), which exceeds the
 * 100-callout-per-transaction limit if attempted synchronously.
 */
public with sharing class FieldUsageAnalyzer implements Queueable, Database.AllowsCallouts {

   private static final Integer BATCH_SIZE = 60; // 300 layouts / 5 max chained jobs (Dev Edition limit) = 60/batch, safely under the 100-callout governor limit per execution
private static final Integer MAX_CHAIN_DEPTH = 5; // Dev Edition / Trial orgs cap chained Queueable jobs at 5

   private List<Object> remainingLayouts;
private Set<String> fieldsFoundInLayouts; // "TableEnumOrId.FieldApiName" format
private String scanBatchId;
private Integer chainDepth;

public FieldUsageAnalyzer(List<Object> remainingLayouts, Set<String> fieldsFoundInLayouts, String scanBatchId, Integer chainDepth) {
    this.remainingLayouts = remainingLayouts;
    this.fieldsFoundInLayouts = fieldsFoundInLayouts;
    this.scanBatchId = scanBatchId;
    this.chainDepth = chainDepth;
}

    /**
     * @description Entry point to kick off the chain. Call this once with the full
     * list of layouts from MetadataScanner.getLayouts().
     */
    public static String startLayoutUsageScan(List<Object> allLayouts) {
    String scanBatchId = String.valueOf(Crypto.getRandomInteger()) + '-' + System.now().getTime();
    System.enqueueJob(new FieldUsageAnalyzer(allLayouts, new Set<String>(), scanBatchId, 1));
    return scanBatchId;
}

    public void execute(QueueableContext context) {
        Integer processCount = Math.min(BATCH_SIZE, remainingLayouts.size());
        List<Object> currentBatch = new List<Object>();
        for (Integer i = 0; i < processCount; i++) {
            currentBatch.add(remainingLayouts.remove(0));
        }

        for (Object layoutObj : currentBatch) {
            Map<String, Object> layout = (Map<String, Object>) layoutObj;
            String layoutId = (String) layout.get('Id');
            String tableEnumOrId = (String) layout.get('TableEnumOrId');

            try {
                Set<String> fieldsOnThisLayout = getFieldsFromLayoutMetadata(layoutId, tableEnumOrId);
                fieldsFoundInLayouts.addAll(fieldsOnThisLayout);
            } catch (Exception e) {
                System.debug('Failed to retrieve Metadata for Layout ' + layoutId + ': ' + e.getMessage());
            }
        }

        if (!remainingLayouts.isEmpty()) {
    if (chainDepth >= MAX_CHAIN_DEPTH) {
        // Persist whatever we've processed so far rather than losing it, and log loudly
        // so this is impossible to miss - it means BATCH_SIZE needs to increase, or the
        // org's layout count has grown enough that 5 chained jobs is no longer sufficient.
        persistResults();
        System.debug(LoggingLevel.ERROR,
            'FieldUsageAnalyzer scan ' + scanBatchId + ' STOPPED EARLY at chain depth ' + chainDepth
            + '. ' + remainingLayouts.size() + ' layouts were NOT processed. Increase BATCH_SIZE.');
        return;
    }
    System.enqueueJob(new FieldUsageAnalyzer(remainingLayouts, fieldsFoundInLayouts, scanBatchId, chainDepth + 1));
} else {
    persistResults();
}
    }

    /**
     * @description Single-record Tooling API query to pull Layout.Metadata, then parses
     * the field references out of it. Layout.Metadata's structure nests field references
     * inside layoutSections -> layoutColumns -> layoutItems -> field.
     */
    private Set<String> getFieldsFromLayoutMetadata(String layoutId, String tableEnumOrId) {
        Set<String> fieldNames = new Set<String>();

        String query = 'SELECT Metadata FROM Layout WHERE Id = \'' + layoutId + '\'';
        List<Object> results = MetadataScanner.queryToolingAPI(query);

        if (results.isEmpty()) {
            return fieldNames;
        }

        Map<String, Object> layoutRecord = (Map<String, Object>) results[0];
        Map<String, Object> metadata = (Map<String, Object>) layoutRecord.get('Metadata');
        if (metadata == null) {
            return fieldNames;
        }

        List<Object> layoutSections = (List<Object>) metadata.get('layoutSections');
        if (layoutSections == null) {
            return fieldNames;
        }

        for (Object sectionObj : layoutSections) {
            Map<String, Object> section = (Map<String, Object>) sectionObj;
            List<Object> layoutColumns = (List<Object>) section.get('layoutColumns');
            if (layoutColumns == null) continue;

            for (Object columnObj : layoutColumns) {
                Map<String, Object> column = (Map<String, Object>) columnObj;
                List<Object> layoutItems = (List<Object>) column.get('layoutItems');
                if (layoutItems == null) continue;

                for (Object itemObj : layoutItems) {
                    Map<String, Object> item = (Map<String, Object>) itemObj;
                    String fieldName = (String) item.get('field');
                    if (String.isNotBlank(fieldName)) {
                        fieldNames.add(tableEnumOrId + '.' + fieldName);
                    }
                }
            }
        }

        return fieldNames;
    }

    /**
     * @description Writes the accumulated results to Field_Usage_Signal__c once every
     * layout in this scan has been processed.
     */
    private void persistResults() {
        List<Field_Usage_Signal__c> recordsToInsert = new List<Field_Usage_Signal__c>();
        for (String key : fieldsFoundInLayouts) {
            List<String> parts = key.split('\\.', 2);
           Field_Usage_Signal__c signal = new Field_Usage_Signal__c(
    Field_Key__c = parts[0] + '.' + (parts.size() > 1 ? parts[1] : ''),
    Table_Enum_Or_Id__c = parts[0],
    Field_Developer_Name__c = parts.size() > 1 ? parts[1] : '',
    Referenced_In_Layout__c = true,
    Scan_Batch_Id__c = scanBatchId
);
recordsToInsert.add(signal);
        }

       if (!recordsToInsert.isEmpty()) {
    upsert recordsToInsert Field_Key__c;
}
        System.debug('FieldUsageAnalyzer scan ' + scanBatchId + ' complete. Fields found on layouts: ' + recordsToInsert.size());
    }
}