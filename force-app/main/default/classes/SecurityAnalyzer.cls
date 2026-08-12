public with sharing class SecurityAnalyzer {

    public class SecurityFinding {
        public String userId;
        public String userName;
        public String permissionSetOrProfileName;
        public String riskType;
        public String severity;
        public String description;
    }

    public static List<SecurityFinding> checkOverPrivilegedUsers() {
        List<SecurityFinding> findings = new List<SecurityFinding>();

        // Source 1: Permission Set-based grants
        List<PermissionSetAssignment> psAssignments = [
            SELECT AssigneeId, Assignee.Name, PermissionSet.Name,
                   PermissionSet.PermissionsModifyAllData, PermissionSet.PermissionsViewAllData
            FROM PermissionSetAssignment
            WHERE (PermissionSet.PermissionsModifyAllData = true
                   OR PermissionSet.PermissionsViewAllData = true)
            AND Assignee.IsActive = true
        ];

        for (PermissionSetAssignment psa : psAssignments) {
            findings.add(buildFinding(
                psa.AssigneeId,
                psa.Assignee.Name,
                psa.PermissionSet.Name,
                psa.PermissionSet.PermissionsModifyAllData
            ));
        }

        // Source 2: Profile-level grants
        List<User> usersWithRiskyProfiles = [
            SELECT Id, Name, Profile.Name, Profile.PermissionsModifyAllData, Profile.PermissionsViewAllData
            FROM User
            WHERE IsActive = true
            AND (Profile.PermissionsModifyAllData = true OR Profile.PermissionsViewAllData = true)
        ];

        for (User u : usersWithRiskyProfiles) {
            findings.add(buildFinding(
                u.Id,
                u.Name,
                u.Profile.Name,
                u.Profile.PermissionsModifyAllData
            ));
        }

        return findings;
    }
    public static List<SecurityFinding> checkApiAccessWithoutIpRestrictions() {
    List<SecurityFinding> findings = new List<SecurityFinding>();

    List<Profile> apiEnabledProfiles = [
        SELECT Id, Name, PermissionsApiEnabled
        FROM Profile
        WHERE PermissionsApiEnabled = true
    ];

    for (Profile p : apiEnabledProfiles) {
        String query = 'SELECT Metadata FROM Profile WHERE Id = \'' + p.Id + '\'';
        String endpoint = Url.getOrgDomainUrl().toExternalForm()
            + '/services/data/v61.0/tooling/query/?q=' + EncodingUtil.urlEncode(query, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            System.debug('Tooling API query failed for profile ' + p.Name + ': ' + res.getStatusCode() + ' ' + res.getBody());
            continue; // skip this profile rather than fail the whole scan
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) body.get('records');
        if (records.isEmpty()) {
            continue;
        }

        Map<String, Object> record = (Map<String, Object>) records[0];
        Map<String, Object> metadata = (Map<String, Object>) record.get('Metadata');
        List<Object> loginIpRanges = metadata != null ? (List<Object>) metadata.get('loginIpRanges') : null;

        Boolean hasIpRestrictions = loginIpRanges != null && !loginIpRanges.isEmpty();

        if (!hasIpRestrictions) {
            SecurityFinding f = new SecurityFinding();
            f.permissionSetOrProfileName = p.Name;
            f.riskType = 'API Access Without IP Restriction';
            f.severity = 'High';
            f.description = 'Profile "' + p.Name + '" has API access enabled with no login IP range restrictions';
            findings.add(f);
        }
    }

    return findings;
}
public static List<SecurityFinding> checkDormantHighPrivilegeAccounts() {
    List<SecurityFinding> findings = new List<SecurityFinding>();
    DateTime cutoff = DateTime.now().addDays(-90);

    // Profile-level over-privileged + dormant
    List<User> dormantProfileUsers = [
        SELECT Id, Name, LastLoginDate, Profile.Name,
               Profile.PermissionsModifyAllData, Profile.PermissionsViewAllData
        FROM User
        WHERE IsActive = true
        AND (Profile.PermissionsModifyAllData = true OR Profile.PermissionsViewAllData = true)
        AND (LastLoginDate = null OR LastLoginDate < :cutoff)
    ];

    for (User u : dormantProfileUsers) {
        findings.add(buildDormantFinding(u.Id, u.Name, u.Profile.Name, u.Profile.PermissionsModifyAllData, u.LastLoginDate));
    }

    // Permission Set-based over-privileged + dormant
    List<PermissionSetAssignment> dormantPsUsers = [
        SELECT AssigneeId, Assignee.Name, Assignee.LastLoginDate, PermissionSet.Name,
               PermissionSet.PermissionsModifyAllData, PermissionSet.PermissionsViewAllData
        FROM PermissionSetAssignment
        WHERE Assignee.IsActive = true
        AND (PermissionSet.PermissionsModifyAllData = true OR PermissionSet.PermissionsViewAllData = true)
        AND (Assignee.LastLoginDate = null OR Assignee.LastLoginDate < :cutoff)
    ];

    for (PermissionSetAssignment psa : dormantPsUsers) {
        findings.add(buildDormantFinding(psa.AssigneeId, psa.Assignee.Name, psa.PermissionSet.Name, psa.PermissionSet.PermissionsModifyAllData, psa.Assignee.LastLoginDate));
    }

    return findings;
}

private static SecurityFinding buildDormantFinding(String userId, String userName, String sourceName, Boolean isModifyAll, DateTime lastLogin) {
    SecurityFinding f = new SecurityFinding();
    f.userId = userId;
    f.userName = userName;
    f.permissionSetOrProfileName = sourceName;
    f.riskType = 'Dormant High-Privilege Account';
    f.severity = 'Critical';
    String loginText = lastLogin != null ? String.valueOf(lastLogin.date()) : 'never logged in';
    f.description = userName + ' has ' + (isModifyAll ? 'Modify All Data' : 'View All Data')
        + ' via "' + sourceName + '" but last login was ' + loginText;
    return f;
}

    private static SecurityFinding buildFinding(String userId, String userName, String sourceName, Boolean isModifyAll) {
        SecurityFinding f = new SecurityFinding();
        f.userId = userId;
        f.userName = userName;
        f.permissionSetOrProfileName = sourceName;
        f.riskType = isModifyAll ? 'Modify All Data' : 'View All Data';
        f.severity = isModifyAll ? 'Critical' : 'High';
        f.description = userName + ' has ' + f.riskType + ' via "' + sourceName + '"';
        return f;
    }
}