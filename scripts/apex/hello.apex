List<Object> connectedApps = MetadataScanner.getConnectedApps();
System.debug('CONNECTED APP COUNT: ' + connectedApps.size());
if (!connectedApps.isEmpty()) {
    System.debug('FIRST CONNECTED APP: ' + JSON.serialize(connectedApps[0]));
}

List<Object> layouts = MetadataScanner.getLayouts();
System.debug('LAYOUT COUNT: ' + layouts.size());
if (!layouts.isEmpty()) {
    System.debug('FIRST LAYOUT: ' + JSON.serialize(layouts[0]));
}