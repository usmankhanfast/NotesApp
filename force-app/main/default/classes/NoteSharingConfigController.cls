public with sharing class NoteSharingConfigController {
    public static final String SHARES_WITH = 'Shares with';
    public static final String SHARE_BOTH_WAYS = 'Share Both Ways';
    private static void checkAdminPermission() {
        if (!FeatureManagement.checkPermission('Manage_Note_Sharing')) {
            throw new AuraHandledException('You do not have permission to manage note sharing.');
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

    @AuraEnabled
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
            throw new AuraHandledException('Add at least one configuration before saving.');
        }
        Set<Id> userIds = new Set<Id>();
        for (RuleRow row : rows) {
            if (row == null ||
                row.sourceUserId == null ||
                row.targetUserId == null ||
                String.isBlank(row.sharingDirection) ||
                String.isBlank(row.objectName)) {
                throw new AuraHandledException('Complete all fields before saving.');
            }
            if (row.sourceUserId == row.targetUserId) {
                throw new AuraHandledException('Source User and Target User must be different.');
            }
            if (!new Set<String>{SHARES_WITH, SHARE_BOTH_WAYS}.contains(row.sharingDirection)) {
                throw new AuraHandledException('Invalid sharing direction.');
            }
            if (!new Set<String>{'Account', 'Opportunity','Contact', 'Lead', 'Case'}.contains(row.objectName)) {
                throw new AuraHandledException('Invalid object selection.');
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
            throw new AuraHandledException('Both users must exist and be active.');
        }
        List<Note_Sharing_Rule__c> recordsToSave = new List<Note_Sharing_Rule__c>();
        validateNoDuplicateRules(rows);
        for (RuleRow row : rows) {
            Note_Sharing_Rule__c record = new Note_Sharing_Rule__c();
            record.Source_User__c = row.sourceUserId;
            record.Target_User__c = row.targetUserId;
            record.Sharing_Direction__c = row.sharingDirection;
            record.Object_Name__c = row.objectName;
            record.Is_Active__c = row.isActive == null ? true : row.isActive;
            if (row.id != null) {
                record.Id = row.id;
            }
            recordsToSave.add(record);
        }
        try {
            upsert as user recordsToSave;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to save note sharing configurations. ' + 'Check your object permissions and field access.');
        }
    }

    @AuraEnabled
    public static void deleteRule(Id ruleId) {
        //checkAdminPermission();
        if (ruleId == null) {
            throw new AuraHandledException('Invalid sharing rule ID.');
        }
        try {
            List<Note_Sharing_Rule__c> rules = [
                SELECT Id
                FROM Note_Sharing_Rule__c
                WHERE Id = :ruleId
                WITH USER_MODE
                LIMIT 1
            ];
            if (rules.isEmpty()) {
                throw new AuraHandledException('Sharing rule not found or you do not have access to it.');
            }
            Database.delete(rules[0], AccessLevel.USER_MODE);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to delete sharing rule. Please check your permissions.');
        }
    }

    private static void validateNoDuplicateRules(List<RuleRow> rows) {
        Set<Id> sourceIds = new Set<Id>();
        Set<Id> targetIds = new Set<Id>();
        Set<String> objectNames = new Set<String>();
        Map<String, Id> incomingKeys = new Map<String, Id>();

        for (RuleRow row : rows) {
            String key = String.valueOf(row.sourceUserId) + '|' +
                String.valueOf(row.targetUserId) + '|' +
                row.sharingDirection + '|' +
                row.objectName;
            if (incomingKeys.containsKey(key)) {
                if (incomingKeys.get(key) != row.id) {
                    throw new AuraHandledException('Duplicate sharing rule found in your configuration.');
                }
            }
            incomingKeys.put(key, row.id);
            sourceIds.add(row.sourceUserId);
            targetIds.add(row.targetUserId);
            objectNames.add(row.objectName);
        }

        List<Note_Sharing_Rule__c> existingRules = [
            SELECT Id, Source_User__c, Target_User__c,
            Sharing_Direction__c, Object_Name__c
            FROM Note_Sharing_Rule__c
            WHERE Source_User__c IN :sourceIds
            AND Target_User__c IN :targetIds
            AND Object_Name__c IN :objectNames
            WITH USER_MODE
        ];

        for (RuleRow row : rows) {
            for (Note_Sharing_Rule__c existing : existingRules) {
                if (existing.Id == row.id) {
                    continue;
                }
                if (
                    existing.Source_User__c == row.sourceUserId &&
                    existing.Target_User__c == row.targetUserId &&
                    existing.Sharing_Direction__c == row.sharingDirection &&
                    existing.Object_Name__c == row.objectName
                ) {
                    throw new AuraHandledException('This sharing rule already exists. Duplicate rules are not allowed.');
                }
            }
        }
    }
}