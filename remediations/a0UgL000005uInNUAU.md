# Remediation Proposal

**Action Type:** Deactivate Field

# Proposed fix: Deactivate unused field
# Field: 01IgL000004PPLtUAO.about__c
# Action: Set field to inactive / hidden via Field-Level Security on all profiles
# (Salesforce fields cannot be metadata-deactivated directly like Flows -
#  the safe remediation is FLS removal, not permanent deletion)
# Suggested next step: remove field from all Field-Level Security profile assignments,
# monitor for 30+ days, then delete if still unused.