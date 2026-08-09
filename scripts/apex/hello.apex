HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Org_Health_Scanner/services/data/v61.0/tooling/query?q=' + EncodingUtil.urlEncode('SELECT Id FROM ApexClass LIMIT 1', 'UTF-8'));
req.setMethod('GET');
Http http = new Http();
HttpResponse res = http.send(req);
System.debug('STATUS: ' + res.getStatusCode());
System.debug('BODY: ' + res.getBody());