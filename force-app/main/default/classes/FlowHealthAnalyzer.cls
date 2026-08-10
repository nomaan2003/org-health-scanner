/**
 * @description Phase 2.3 - analyzes Flow health: overlapping triggers on the same object,
 * missing fault paths, and inactive versions safe to delete. Runs synchronously - only
 * ~11 Flow versions exist, so pulling each one's Metadata individually (single-record
 * query, like Layout) stays well under the 100-callout-per-transaction limit.
 */
public with sharing class FlowHealthAnalyzer {

    /**
     * @description One finding about a Flow's health.
     */
    public class FlowFinding {
        public String flowId;
        public String flowName;
        public String findingType; // 'Overlapping Trigger', 'Missing Fault Path', 'Safe To Delete'
        public String description;

        public FlowFinding(String flowId, String flowName, String findingType, String description) {
            this.flowId = flowId;
            this.flowName = flowName;
            this.findingType = findingType;
            this.description = description;
        }
    }

    /**
     * @description Entry point. Pulls all Flow versions and their Metadata, then runs
     * all three health checks.
     * @return List of FlowFinding, one per issue detected.
     */
    public static List<FlowFinding> runFlowHealthScan() {
        List<FlowFinding> findings = new List<FlowFinding>();

        List<Object> flows = MetadataScanner.getFlows();
        List<Object> flowDefinitions = MetadataScanner.getFlowDefinitions();

        // Build a lookup: DefinitionId -> ActiveVersionId, so we know which version is live
        Map<String, String> activeVersionByDefinition = new Map<String, String>();
        for (Object defObj : flowDefinitions) {
            Map<String, Object> def = (Map<String, Object>) defObj;
            String defId = (String) def.get('Id');
            String activeVersionId = (String) def.get('ActiveVersionId');
            if (String.isNotBlank(defId)) {
                activeVersionByDefinition.put(defId, activeVersionId);
            }
        }

        // Pull each Flow's Metadata (single-record query per Flow)
        Map<String, Map<String, Object>> metadataByFlowId = new Map<String, Map<String, Object>>();
        for (Object flowObj : flows) {
            Map<String, Object> flow = (Map<String, Object>) flowObj;
            String flowId = (String) flow.get('Id');
            try {
                String query = 'SELECT Metadata FROM Flow WHERE Id = \'' + flowId + '\'';
                List<Object> results = MetadataScanner.queryToolingAPI(query);
                if (!results.isEmpty()) {
                    Map<String, Object> flowFull = (Map<String, Object>) results[0];
                    Object metadata = flowFull.get('Metadata');
                    if (metadata != null) {
                        metadataByFlowId.put(flowId, (Map<String, Object>) metadata);
                    }
                }
            } catch (Exception e) {
                System.debug('Failed to retrieve Metadata for Flow ' + flowId + ': ' + e.getMessage());
            }
        }

        findings.addAll(checkOverlappingTriggers(flows, flowDefinitions, metadataByFlowId, activeVersionByDefinition));
        findings.addAll(checkMissingFaultPaths(flows, metadataByFlowId));
        findings.addAll(checkSafeToDelete(flows, activeVersionByDefinition));

        return findings;
    }

    /**
     * @description Flags when 2+ ACTIVE flows share the same trigger object and
     * record-trigger type (e.g. two Account record-triggered flows both firing on update).
     */
    private static List<FlowFinding> checkOverlappingTriggers(
        List<Object> flows,
        List<Object> flowDefinitions,
        Map<String, Map<String, Object>> metadataByFlowId,
        Map<String, String> activeVersionByDefinition
    ) {
        List<FlowFinding> findings = new List<FlowFinding>();
        Map<String, List<String>> flowsByTriggerKey = new Map<String, List<String>>(); // "Object.TriggerType" -> [flowName, ...]
        Map<String, String> flowNameById = new Map<String, String>();

        for (Object flowObj : flows) {
            Map<String, Object> flow = (Map<String, Object>) flowObj;
            String flowId = (String) flow.get('Id');
            String masterLabel = (String) flow.get('MasterLabel');
            flowNameById.put(flowId, masterLabel);

            // Only consider the ACTIVE version of each flow, to avoid flagging old drafts
            Boolean isActiveVersion = activeVersionByDefinition.values().contains(flowId);
            if (!isActiveVersion) {
                continue;
            }

            Map<String, Object> metadata = metadataByFlowId.get(flowId);
            if (metadata == null) {
                continue;
            }

            Map<String, Object> start = (Map<String, Object>) metadata.get('start');
            if (start == null) {
                continue; // not a record-triggered flow (e.g. screen flow) - nothing to check here
            }

            String triggerObject = (String) start.get('object');
            String recordTriggerType = (String) start.get('recordTriggerType');
            if (String.isBlank(triggerObject) || String.isBlank(recordTriggerType)) {
                continue;
            }

            String triggerKey = triggerObject + '.' + recordTriggerType;
            if (!flowsByTriggerKey.containsKey(triggerKey)) {
                flowsByTriggerKey.put(triggerKey, new List<String>());
            }
            flowsByTriggerKey.get(triggerKey).add(flowId);
        }

        for (String triggerKey : flowsByTriggerKey.keySet()) {
            List<String> flowIds = flowsByTriggerKey.get(triggerKey);
            if (flowIds.size() > 1) {
                List<String> names = new List<String>();
                for (String fId : flowIds) {
                    names.add(flowNameById.get(fId));
                }
                for (String fId : flowIds) {
                    findings.add(new FlowFinding(
                        fId,
                        flowNameById.get(fId),
                        'Overlapping Trigger',
                        'Shares trigger (' + triggerKey + ') with: ' + String.join(names, ', ')
                    ));
                }
            }
        }

        return findings;
    }

    /**
     * @description Flags elements (record creates/updates/lookups, action calls) that have
     * no faultConnector configured - meaning an error there has nowhere defined to go.
     */
    private static List<FlowFinding> checkMissingFaultPaths(List<Object> flows, Map<String, Map<String, Object>> metadataByFlowId) {
        List<FlowFinding> findings = new List<FlowFinding>();
        List<String> elementTypesToCheck = new List<String>{
            'recordCreates', 'recordUpdates', 'recordLookups', 'recordDeletes', 'actionCalls'
        };

        for (Object flowObj : flows) {
            Map<String, Object> flow = (Map<String, Object>) flowObj;
            String flowId = (String) flow.get('Id');
            String masterLabel = (String) flow.get('MasterLabel');

            Map<String, Object> metadata = metadataByFlowId.get(flowId);
            if (metadata == null) {
                continue;
            }

            for (String elementType : elementTypesToCheck) {
                Object elementsRaw = metadata.get(elementType);
                if (elementsRaw == null) {
                    continue;
                }

                // Flow metadata returns either a single Map or a List<Object> depending on count
                List<Object> elements = elementsRaw instanceof List<Object>
                    ? (List<Object>) elementsRaw
                    : new List<Object>{ elementsRaw };

                for (Object elementObj : elements) {
                    Map<String, Object> element = (Map<String, Object>) elementObj;
                    String elementName = (String) element.get('name');
                   if (!element.containsKey('faultConnector') || element.get('faultConnector') == null) {
                        findings.add(new FlowFinding(
                            flowId,
                            masterLabel,
                            'Missing Fault Path',
                            elementType + ' element "' + elementName + '" has no fault connector configured'
                        ));
                    }
                }
            }
        }

        return findings;
    }

    /**
     * @description Flags inactive Flow versions that are not the currently active version -
     * candidates for safe deletion (further checks like "referenced elsewhere" are a future
     * refinement; for now this flags anything superseded).
     */
    private static List<FlowFinding> checkSafeToDelete(List<Object> flows, Map<String, String> activeVersionByDefinition) {
        List<FlowFinding> findings = new List<FlowFinding>();
        Set<String> activeVersionIds = new Set<String>(activeVersionByDefinition.values());

        for (Object flowObj : flows) {
            Map<String, Object> flow = (Map<String, Object>) flowObj;
            String flowId = (String) flow.get('Id');
            String masterLabel = (String) flow.get('MasterLabel');
            String status = (String) flow.get('Status');

            Boolean isActiveVersion = activeVersionIds.contains(flowId);
            if (!isActiveVersion && status != 'Active') {
                findings.add(new FlowFinding(
                    flowId,
                    masterLabel,
                    'Safe To Delete',
                    'Inactive version (Status: ' + status + '), not the active version for this flow'
                ));
            }
        }

        return findings;
    }
}