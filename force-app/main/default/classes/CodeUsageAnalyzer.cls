/**
 * @description Phase 2.2 - determines whether CustomFields are referenced anywhere in
 * Apex class bodies or Flow definitions, via text-search. Unlike FieldUsageAnalyzer
 * (Layout) and DataPresenceAnalyzer, this runs synchronously in one transaction:
 * ApexClass.Body can be bulk-queried (no single-record restriction), and this org only
 * has ~11 Flow versions, so pulling each Flow's Metadata individually stays well under
 * the 100-callout-per-transaction limit without needing Queueable chaining.
 */
public with sharing class CodeUsageAnalyzer {

    /**
     * @description Entry point. Pulls Apex bodies and Flow metadata, builds a combined
     * search corpus, then checks every CustomField's API name against it.
     * @return The scanBatchId used for this run's Field_Usage_Signal__c records.
     */
    public static String runCodeUsageScan() {
        String scanBatchId = String.valueOf(Crypto.getRandomInteger()) + '-' + System.now().getTime();

        String corpus = buildSearchCorpus();
        List<Object> allCustomFields = MetadataScanner.getCustomFields();

        List<Field_Usage_Signal__c> resultsToInsert = new List<Field_Usage_Signal__c>();

        for (Object fieldObj : allCustomFields) {
            Map<String, Object> fieldRecord = (Map<String, Object>) fieldObj;
            String developerName = (String) fieldRecord.get('DeveloperName');
            String tableEnumOrId = (String) fieldRecord.get('TableEnumOrId');
            String namespacePrefix = (String) fieldRecord.get('NamespacePrefix');

            if (String.isBlank(developerName) || String.isBlank(tableEnumOrId)) {
                continue;
            }

            String fieldApiName = String.isNotBlank(namespacePrefix)
                ? namespacePrefix + '__' + developerName + '__c'
                : developerName + '__c';

            Boolean referencedInCode = corpus.contains(fieldApiName);

            resultsToInsert.add(new Field_Usage_Signal__c(
                Table_Enum_Or_Id__c = tableEnumOrId,
                Field_Developer_Name__c = fieldApiName,
                Referenced_In_Code__c = referencedInCode,
                Scan_Batch_Id__c = scanBatchId
            ));
        }

        if (!resultsToInsert.isEmpty()) {
            insert resultsToInsert;
        }

        System.debug('CodeUsageAnalyzer scan ' + scanBatchId + ' complete. Fields checked: ' + resultsToInsert.size());
        return scanBatchId;
    }

    /**
     * @description Builds one combined text corpus from all Apex class bodies and all
     * Flow Metadata (JSON-serialized), used as the haystack for field-reference checks.
     */
    private static String buildSearchCorpus() {
        String corpus = '';

        // Apex bodies - safe to bulk query
        List<Object> apexClasses = MetadataScanner.getApexClassBodies();
        for (Object classObj : apexClasses) {
            Map<String, Object> classRecord = (Map<String, Object>) classObj;
            String body = (String) classRecord.get('Body');
            if (String.isNotBlank(body)) {
                corpus += body + '\n';
            }
        }

        // Flow metadata - one single-record callout per flow (only ~11, safe without chaining)
        List<Object> flows = MetadataScanner.getFlows();
        for (Object flowObj : flows) {
            Map<String, Object> flowRecord = (Map<String, Object>) flowObj;
            String flowId = (String) flowRecord.get('Id');

            try {
                String query = 'SELECT Metadata FROM Flow WHERE Id = \'' + flowId + '\'';
                List<Object> results = MetadataScanner.queryToolingAPI(query);
                if (!results.isEmpty()) {
                    Map<String, Object> flowFull = (Map<String, Object>) results[0];
                    Object metadata = flowFull.get('Metadata');
                    if (metadata != null) {
                        corpus += JSON.serialize(metadata) + '\n';
                    }
                }
            } catch (Exception e) {
                System.debug('Failed to retrieve Metadata for Flow ' + flowId + ': ' + e.getMessage());
            }
        }

        return corpus;
    }
}