public with sharing class RemediationGenerator {

    public static List<Remediation_Action__c> generateForUnusedFields(List<Debt_Finding__c> findings) {
        List<Remediation_Action__c> actions = new List<Remediation_Action__c>();
        List<Debt_Finding__c> findingsToUpdate = new List<Debt_Finding__c>();

        for (Debt_Finding__c f : findings) {
            if (f.Category__c != 'Unused Field') {
                continue; // guard: only handle the category this method knows about
            }

            Remediation_Action__c action = new Remediation_Action__c(
                Debt_Finding__c = f.Id,
                Action_Type__c = 'Deactivate Field',
                Metadata_Diff__c = buildDeactivateFieldDiff(f)
            );
            actions.add(action);

            f.Status__c = 'Fix Proposed';
            findingsToUpdate.add(f);
        }

        if (!actions.isEmpty()) {
            insert actions;
        }
        if (!findingsToUpdate.isEmpty()) {
            update findingsToUpdate;
        }

        return actions;
    }
    public static List<Remediation_Action__c> generateForOrphanedFlows(List<Debt_Finding__c> findings) {
    List<Remediation_Action__c> actions = new List<Remediation_Action__c>();
    List<Debt_Finding__c> findingsToUpdate = new List<Debt_Finding__c>();

    for (Debt_Finding__c f : findings) {
        if (f.Category__c != 'Orphaned Flow') {
            continue;
        }

        Remediation_Action__c action = new Remediation_Action__c(
            Debt_Finding__c = f.Id,
            Action_Type__c = 'Delete Flow Version',
            Metadata_Diff__c = buildDeleteFlowVersionDiff(f)
        );
        actions.add(action);

        f.Status__c = 'Fix Proposed';
        findingsToUpdate.add(f);
    }

    if (!actions.isEmpty()) {
        insert actions;
    }
    if (!findingsToUpdate.isEmpty()) {
        update findingsToUpdate;
    }

    return actions;
}
public static List<Remediation_Action__c> generateForHardcodedIds(List<Debt_Finding__c> findings) {
    List<Remediation_Action__c> actions = new List<Remediation_Action__c>();
    List<Debt_Finding__c> findingsToUpdate = new List<Debt_Finding__c>();

    for (Debt_Finding__c f : findings) {
        if (f.Category__c != 'Hardcoded Id') {
            continue;
        }

        Remediation_Action__c action = new Remediation_Action__c(
            Debt_Finding__c = f.Id,
            Action_Type__c = 'Replace Hardcoded Id',
            Metadata_Diff__c = buildReplaceHardcodedIdDiff(f)
        );
        actions.add(action);

        f.Status__c = 'Fix Proposed';
        findingsToUpdate.add(f);
    }

    if (!actions.isEmpty()) {
        insert actions;
    }
    if (!findingsToUpdate.isEmpty()) {
        update findingsToUpdate;
    }

    return actions;
}

private static String buildReplaceHardcodedIdDiff(Debt_Finding__c f) {
    String componentName = f.Component_Name__c;

    return '# Proposed fix: Replace hardcoded Salesforce Id\n' +
           '# Location: ' + componentName + '\n' +
           '# Action: This Apex class contains a hardcoded 15/18-char Salesforce Id literal,\n' +
           '#  which breaks across orgs/sandboxes since Ids are org-specific.\n' +
           '# Suggested next step: replace the literal with a Custom Label or Custom Metadata Type\n' +
           '#  lookup (e.g. by developer name / unique key) so the value is environment-configurable.';
}

private static String buildAddFaultPathDiff(Debt_Finding__c f) {
    String componentName = f.Component_Name__c;

    return '# Proposed fix: Add fault connector\n' +
           '# Flow: ' + componentName + '\n' +
           '# Action: One or more elements in this Flow lack a fault path, so unhandled errors\n' +
           '#  (e.g. DML failures, callout errors) will surface ungracefully to the end user.\n' +
           '# Suggested next step: open the Flow in Flow Builder, add a Fault path from each\n' +
           '#  DML/Action/Callout element to a screen or error-logging subflow.';
}

private static String buildDeleteFlowVersionDiff(Debt_Finding__c f) {
    String componentName = f.Component_Name__c; // whatever format FlowHealthAnalyzer stored - flow name, or name+version

    return '# Proposed fix: Delete inactive Flow version\n' +
           '# Flow: ' + componentName + '\n' +
           '# Action: This version is inactive and not referenced elsewhere -\n' +
           '#  safe to delete via Setup > Flows > Version History, or Metadata API destructiveChanges.\n' +
           '# Suggested next step: confirm no scheduled paths reference this version before deleting.';
}

    private static String buildDeactivateFieldDiff(Debt_Finding__c f) {
        // Component_Name__c / Component_Type__c were confirmed on Debt_Finding__c in Phase 2.5
        // Expect Component_Name__c to hold something like "Account.Legacy_Notes__c"
        String componentName = f.Component_Name__c;

        return '# Proposed fix: Deactivate unused field\n' +
               '# Field: ' + componentName + '\n' +
               '# Action: Set field to inactive / hidden via Field-Level Security on all profiles\n' +
               '# (Salesforce fields cannot be metadata-deactivated directly like Flows - \n' +
               '#  the safe remediation is FLS removal, not permanent deletion)\n' +
               '# Suggested next step: remove field from all Field-Level Security profile assignments,\n' +
               '# monitor for 30+ days, then delete if still unused.';
    }
}
    