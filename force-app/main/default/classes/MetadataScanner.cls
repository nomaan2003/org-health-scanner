/**
 * @description Core scanning engine for the Org Health & Tech Debt Scanner.
 * Provides a reusable, paginated Tooling API query method used by all
 * downstream analyzer classes (FieldUsageAnalyzer, FlowHealthAnalyzer, etc).
 */
public with sharing class MetadataScanner {

    // Base endpoint for Tooling API queries via our Named Credential
    private static final String NAMED_CREDENTIAL = 'callout:Org_Health_Scanner';
    private static final String API_VERSION = 'v61.0';

    /**
     * @description Executes a Tooling API SOQL query and automatically pages
     * through results using nextRecordsUrl until all records are retrieved.
     * @param soqlQuery A valid Tooling API SOQL string (e.g. against CustomField, Flow, ApexClass).
     * @return List of untyped Tooling API record objects (each a Map<String,Object> when cast).
     */
    public static List<Object> queryToolingAPI(String soqlQuery) {
        List<Object> allRecords = new List<Object>();

        String endpoint = NAMED_CREDENTIAL + '/services/data/' + API_VERSION
            + '/tooling/query?q=' + EncodingUtil.urlEncode(soqlQuery, 'UTF-8');

        Boolean done = false;
        Integer safetyCounter = 0; // prevents runaway loops if "done" is ever malformed

        while (!done && safetyCounter < 50) {
            safetyCounter++;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(60000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200) {
                throw new MetadataScannerException(
                    'Tooling API query failed. Status: ' + res.getStatusCode()
                    + '. Body: ' + res.getBody()
                );
            }

            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            List<Object> records = (List<Object>) parsed.get('records');
            if (records != null) {
                allRecords.addAll(records);
            }

            done = (Boolean) parsed.get('done');

            if (!done) {
                String nextRecordsUrl = (String) parsed.get('nextRecordsUrl');
                if (String.isBlank(nextRecordsUrl)) {
                    done = true;
                } else {
                    endpoint = NAMED_CREDENTIAL + nextRecordsUrl;
                }
            }
        }

        return allRecords;
    }

    /**
     * @description Retrieves inventory of all custom fields in the org via Tooling API,
     * including which object they belong to and their audit dates. Does not determine
     * usage — that cross-referencing happens in FieldUsageAnalyzer (Phase 2.2).
     *
     * NOTE: Field-history-tracking status ("trackHistory") is intentionally NOT pulled here.
     * It lives inside CustomField's nested Metadata sub-object, which the Tooling API only
     * allows querying when the result set is a single record — it cannot be bulk-queried
     * across many fields at once. If needed later, fetch it individually per-field only for
     * the small subset of fields flagged as candidates (e.g. in FieldUsageAnalyzer), not here.
     * @return List of Map<String,Object> representing raw CustomField Tooling API records.
     */
    public static List<Object> getCustomFields() {
        String query = 'SELECT Id, DeveloperName, TableEnumOrId, NamespacePrefix, ' +
            'ManageableState, CreatedDate, LastModifiedDate ' +
            'FROM CustomField ' +
            'ORDER BY TableEnumOrId, DeveloperName';

        return queryToolingAPI(query);
    }

    /**
     * @description Custom exception thrown when a Tooling API callout fails
     * (non-200 status) during a scan operation.
     */
    public class MetadataScannerException extends Exception {}
}