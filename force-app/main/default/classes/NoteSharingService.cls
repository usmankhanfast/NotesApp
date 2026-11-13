public with sharing class NoteSharingService {
    @AuraEnabled
    public static String shareActiveNotes() {
        if (!FeatureManagement.checkPermission('Manage_Note_Sharing')) {
            //throw new AuraHandledException('You do not have permission to run note sharing.');
        }
        Map<String, List<Note_Sharing_Rule__c>> rulesMap = new Map<String, List<Note_Sharing_Rule__c>>();
        for(Note_Sharing_Rule__c rule: [
            SELECT Id,
                   Source_User__c,
                   Target_User__c,
                   Sharing_Direction__c,
                   Object_Name__c,
                   Is_Active__c
            FROM Note_Sharing_Rule__c
            WHERE Is_Active__c = true
            WITH USER_MODE]) {
            if (!rulesMap.containsKey(rule.Object_Name__c)) {
                rulesMap.put(rule.Object_Name__c, new List<Note_Sharing_Rule__c>());
            }
            rulesMap.get(rule.Object_Name__c).add(rule);
        }
        if (rulesMap.isEmpty()) {
            throw new AuraHandledException('No active note sharing rules were found.');
        }
        List<String> objectNames = new List<String>(rulesMap.keySet());
        if (!objectNames.isEmpty()) {
            Database.executeBatch(new NoteSharingBatch(rulesMap, objectNames[0]), 200);
        }
        return 'Queued';
    }
}