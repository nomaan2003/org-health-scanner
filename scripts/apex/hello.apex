List<Object> flows = MetadataScanner.getFlows();
System.debug('FLOW VERSION COUNT: ' + flows.size());
if (!flows.isEmpty()) {
    System.debug('FIRST FLOW: ' + JSON.serialize(flows[0]));
}

List<Object> flowDefs = MetadataScanner.getFlowDefinitions();
System.debug('FLOW DEFINITION COUNT: ' + flowDefs.size());
if (!flowDefs.isEmpty()) {
    System.debug('FIRST FLOW DEF: ' + JSON.serialize(flowDefs[0]));
}