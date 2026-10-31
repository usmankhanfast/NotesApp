public with sharing class NoteSharingConfigController {
    private static void checkAdminPermission() {
        if (!FeatureManagement.checkPermission('Manage_Note_Sharing')) {
            throw new AuraHandledException(
                'You do not have permission to manage note sharing.'
            );
        }
    }

    public class RuleRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id sourceUserId { get; set; }
        @AuraEnabled public Id targetUserId { get; set; }
        @AuraEnabled public String sharingDirection { get; set; }
        @AuraEnabled public String objectName { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<User> getActiveUsers() {
        //checkAdminPermission();
        return [
            SELECT Id, Name, Username
            FROM User
            WHERE IsActive = true
            WITH USER_MODE
            ORDER BY Name
            LIMIT 2000
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<RuleRow> getRules() {
        //checkAdminPermission();
        List<RuleRow> result = new List<RuleRow>();
        for (Note_Sharing_Rule__c record : [
            SELECT Id, Source_User__c, Target_User__c,
                   Sharing_Direction__c, Object_Name__c,
                   Is_Active__c
            FROM Note_Sharing_Rule__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            RuleRow row = new RuleRow();
            row.id = record.Id;
            row.sourceUserId = record.Source_User__c;
            row.targetUserId = record.Target_User__c;
            row.sharingDirection = record.Sharing_Direction__c;
            row.objectName = record.Object_Name__c;
            row.isActive = record.Is_Active__c;

            result.add(row);
        }
        return result;
    }

    @AuraEnabled
    public static void saveRules(List<RuleRow> rows) {
        //checkAdminPermission();
        if (rows == null || rows.isEmpty()) {
            throw new AuraHandledException(
                'Add at least one configuration before saving.'
            );
        }
        Set<Id> userIds = new Set<Id>();
        for (RuleRow row : rows) {
            if (row == null ||
                row.sourceUserId == null ||
                row.targetUserId == null ||
                String.isBlank(row.sharingDirection) ||
                String.isBlank(row.objectName)) {

                throw new AuraHandledException(
                    'Complete all fields before saving.'
                );
            }
            if (row.sourceUserId == row.targetUserId) {
                throw new AuraHandledException(
                    'Source User and Target User must be different.'
                );
            }

            if (!new Set<String>{
                'Both', 'Source to Target', 'Target to Source'
            }.contains(row.sharingDirection)) {
                throw new AuraHandledException(
                    'Invalid sharing direction.'
                );
            }

            if (!new Set<String>{
                'All Supported Objects', 'Account', 'Opportunity',
                'Contact', 'Lead', 'Case'
            }.contains(row.objectName)) {
                throw new AuraHandledException(
                    'Invalid object selection.'
                );
            }

            userIds.add(row.sourceUserId);
            userIds.add(row.targetUserId);
        }

        Map<Id, User> activeUsers = new Map<Id, User>([
            SELECT Id
            FROM User
            WHERE Id IN :userIds
            AND IsActive = true
            WITH USER_MODE
        ]);

        if (activeUsers.size() != userIds.size()) {
            throw new AuraHandledException(
                'Both users must exist and be active.'
            );
        }
        List<Note_Sharing_Rule__c> recordsToSave =
            new List<Note_Sharing_Rule__c>();
        Set<Id> existingRuleIds = new Set<Id>();
        for (RuleRow row : rows) {
            Note_Sharing_Rule__c record = new Note_Sharing_Rule__c();
            if (row.id != null) {
                existingRuleIds.add(row.id);
                record.Id = row.id;
            }
            record.Source_User__c = row.sourceUserId;
            record.Target_User__c = row.targetUserId;
            record.Sharing_Direction__c = row.sharingDirection;
            record.Object_Name__c = row.objectName;
            record.Is_Active__c = row.isActive == null ? true : row.isActive;

            recordsToSave.add(record);
        }

        if (!existingRuleIds.isEmpty()) {
            Set<Id> accessibleRuleIds = new Set<Id>();
            for (Note_Sharing_Rule__c existing : [
                SELECT Id
                FROM Note_Sharing_Rule__c
                WHERE Id IN :existingRuleIds
                WITH USER_MODE
            ]) {
                accessibleRuleIds.add(existing.Id);
            }

            if (accessibleRuleIds.size() != existingRuleIds.size()) {
                throw new AuraHandledException(
                    'One or more rules cannot be edited.'
                );
            }
        }
        try {
            upsert as user recordsToSave;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to save note sharing configurations. ' +
                'Check your object permissions and field access.'
            );
        }
    }
}