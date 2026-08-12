public with sharing class GitHubPRCreator {

    private static final String OWNER = 'nomaan2003';
    private static final String REPO = 'org-health-scanner';
    private static final String BASE_BRANCH = 'main';
    private static final String BASE_URL = 'https://api.github.com';

    private static String getToken() {
        GitHub_Config__mdt config = GitHub_Config__mdt.getInstance('Default');
        return config.Token__c;
    }

   private static HttpRequest buildRequest(String path, String method) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(BASE_URL + path);
    req.setMethod(method);
    String authHeader = 'Bearer ' + getToken();
    System.debug('AUTH HEADER LENGTH: ' + authHeader.length());
    System.debug('AUTH HEADER VALUE: [' + authHeader + ']');
    req.setHeader('Authorization', authHeader);
    req.setHeader('User-Agent', 'Salesforce-OrgHealthScanner');
    req.setHeader('Content-Type', 'application/json');
    return req;
}
    public static String createPRForRemediation(Remediation_Action__c action) {
        String baseSha = getBaseBranchSha();

        String branchName = 'remediation/' + action.Id;
        createBranch(branchName, baseSha);

        String filePath = 'remediations/' + action.Id + '.md';
        String fileContent = buildFileContent(action);
        createFile(branchName, filePath, fileContent);

        return openPullRequest(branchName, action);
    }

    private static String getBaseBranchSha() {
        HttpRequest req = buildRequest('/repos/' + OWNER + '/' + REPO + '/git/ref/heads/' + BASE_BRANCH, 'GET');
        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new GitHubPRException('Failed to get base branch ref: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> objectMap = (Map<String, Object>) body.get('object');
        return (String) objectMap.get('sha');
    }

    private static void createBranch(String branchName, String sha) {
        HttpRequest req = buildRequest('/repos/' + OWNER + '/' + REPO + '/git/refs', 'POST');

        Map<String, Object> payload = new Map<String, Object>{
            'ref' => 'refs/heads/' + branchName,
            'sha' => sha
        };
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 201) {
            throw new GitHubPRException('Failed to create branch: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }

    private static void createFile(String branchName, String filePath, String content) {
        HttpRequest req = buildRequest('/repos/' + OWNER + '/' + REPO + '/contents/' + filePath, 'PUT');

        Map<String, Object> payload = new Map<String, Object>{
            'message' => 'Add remediation proposal for ' + filePath,
            'content' => EncodingUtil.base64Encode(Blob.valueOf(content)),
            'branch' => branchName
        };
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 201) {
            throw new GitHubPRException('Failed to create file: ' + res.getStatusCode() + ' ' + res.getBody());
        }
    }

    private static String openPullRequest(String branchName, Remediation_Action__c action) {
        HttpRequest req = buildRequest('/repos/' + OWNER + '/' + REPO + '/pulls', 'POST');

        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'Remediation: ' + action.Action_Type__c + ' (' + action.Id + ')',
            'head' => branchName,
            'base' => BASE_BRANCH,
            'body' => action.Metadata_Diff__c
        };
        req.setBody(JSON.serialize(payload));

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 201) {
            throw new GitHubPRException('Failed to open PR: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) body.get('html_url');
    }

    private static String buildFileContent(Remediation_Action__c action) {
        return '# Remediation Proposal\n\n' +
               '**Action Type:** ' + action.Action_Type__c + '\n\n' +
               action.Metadata_Diff__c;
    }

    public class GitHubPRException extends Exception {}
}