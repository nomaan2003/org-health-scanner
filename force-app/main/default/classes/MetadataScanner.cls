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
                    // Defensive: if Salesforce says not done but gives no next URL, stop instead of looping forever
                    done = true;
                } else {
                    // nextRecordsUrl comes back as an absolute org path like
                    // /services/data/v61.0/tooling/query/01gXX-2000
                    // We need to re-prefix it with our Named Credential.
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
     * @description Retrieves all Flow versions (active and inactive) in the org via Tooling API.
     * Each record represents one specific version of a flow. Use getFlowDefinitions() alongside
     * this to know which version is currently active per flow (DefinitionId links the two).
     * @return List of Map<String,Object> representing raw Flow Tooling API records.
     */
    public static List<Object> getFlows() {
        String query = 'SELECT Id, MasterLabel, DefinitionId, VersionNumber, Status, ' +
            'ProcessType, ManageableState, Description ' +
            'FROM Flow ' +
            'ORDER BY DefinitionId, VersionNumber';

        return queryToolingAPI(query);
    }

    /**
     * @description Retrieves the "parent" record for each distinct flow (one per unique flow
     * API name), including which version is currently active vs. merely the latest saved
     * version. This is what lets FlowHealthAnalyzer (Phase 2.3) tell an active flow apart
     * from an old draft or superseded version of the same flow.
     * @return List of Map<String,Object> representing raw FlowDefinition Tooling API records.
     */
    public static List<Object> getFlowDefinitions() {
        String query = 'SELECT Id, DeveloperName, MasterLabel, ActiveVersionId, ' +
            'LatestVersionId, ManageableState, NamespacePrefix ' +
            'FROM FlowDefinition ' +
            'ORDER BY DeveloperName';

        return queryToolingAPI(query);
    }

    /**
     * @description Retrieves inventory of all Apex classes in the org via Tooling API,
     * including compile status, length, and audit dates. Does not include coverage
     * percentages — use getApexCodeCoverage() alongside this and join in Apex by Id,
     * since coverage lives on a separate Tooling object (ApexCodeCoverageAggregate).
     * @return List of Map<String,Object> representing raw ApexClass Tooling API records.
     */
    public static List<Object> getApexClasses() {
        String query = 'SELECT Id, Name, ApiVersion, LengthWithoutComments, Status, ' +
            'IsValid, NamespacePrefix, CreatedDate, LastModifiedDate ' +
            'FROM ApexClass ' +
            'ORDER BY Name';

        return queryToolingAPI(query);
    }

    /**
     * @description Retrieves org-wide aggregate code coverage per Apex class/trigger via
     * Tooling API. This is the summarized coverage (used for "below 75%" checks in
     * ApexHealthAnalyzer, Phase 2.4) — not the same as ApexCodeCoverage, which is granular
     * per-test-run detail and not what we want for a health score.
     * @return List of Map<String,Object> representing raw ApexCodeCoverageAggregate records.
     */
    public static List<Object> getApexCodeCoverage() {
        String query = 'SELECT ApexClassOrTriggerId, ApexClassOrTrigger.Name, ' +
            'NumLinesCovered, NumLinesUncovered ' +
            'FROM ApexCodeCoverageAggregate ' +
            'ORDER BY ApexClassOrTrigger.Name';

        return queryToolingAPI(query);
    }

    /**
     * @description Retrieves connected apps via the Tooling API's ConnectedApplication object.
     * NOTE: ConnectedApplication is officially documented by Salesforce as "For internal use
     * only" — it has no published field reference the way CustomField, Flow, or ApexClass do.
     * We deliberately query only Id and Name (the two fields virtually certain to exist on any
     * queryable object) and wrap the call in a try/catch so a future Salesforce change to this
     * undocumented object degrades gracefully instead of breaking the whole metadata scan.
     * OAuth scope data (needed for Phase 5's Security Readiness Module) is intentionally NOT
     * pulled here — that will be sourced from a properly documented API when we get to Phase 5.
     * @return List of Map<String,Object> representing raw ConnectedApplication records, or an
     * empty list if the query fails.
     */
    public static List<Object> getConnectedApps() {
        try {
            String query = 'SELECT Id, Name FROM ConnectedApplication';
            return queryToolingAPI(query);
        } catch (Exception e) {
            System.debug('getConnectedApps() failed - ConnectedApplication may be unavailable: ' + e.getMessage());
            return new List<Object>();
        }
    }

    /**
     * @description Retrieves inventory of all page layouts in the org via Tooling API,
     * including which object each layout belongs to (TableEnumOrId is the join key back
     * to CustomField.TableEnumOrId). This is the first data source FieldUsageAnalyzer
     * (Phase 2.2) will use to determine whether a field appears on any layout.
     *
     * NOTE: Layout's Metadata field (the actual field placements) and FullName are
     * intentionally NOT pulled here. The Tooling API only allows querying those fields
     * when the result set is a single record — they cannot be bulk-queried across many
     * layouts at once. Per-layout Metadata retrieval happens later, inside
     * FieldUsageAnalyzer, one layout at a time.
     * @return List of Map<String,Object> representing raw Layout Tooling API records.
     */
    public static List<Object> getLayouts() {
        String query = 'SELECT Id, Name, TableEnumOrId ' +
            'FROM Layout ' +
            'ORDER BY TableEnumOrId, Name';

        return queryToolingAPI(query);
    }

    /**
     * @description Custom exception thrown when a Tooling API callout fails
     * (non-200 status) during a scan operation.
     */
    public class MetadataScannerException extends Exception {}
}