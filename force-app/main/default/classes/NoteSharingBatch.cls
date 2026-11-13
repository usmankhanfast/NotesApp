public without sharing class NoteSharingBatch implements Database.Batchable<SObject>, Database.Stateful {
    private List<Note_Sharing_Rule__c> rules;
    String objectName;
    public static final String SHARES_WITH = 'Shares with';
    public static final String SHARE_BOTH_WAYS = 'Share Both Ways';

    private Map<Id, List<ShareRoute>> routesByAuthor = new Map<Id, List<ShareRoute>>();
    private Map<String, List<Note_Sharing_Rule__c>> remainingRules = new Map<String, List<Note_Sharing_Rule__c>>();
    private Map<Id, ContentDocumentLink> existingLinkMap = new Map<Id, ContentDocumentLink>();
    private Set<Id> authorIds = new Set<Id>();
    private Set<Id> recipientIds = new Set<Id>();
    
    private Integer sharedCount = 0;
    private Integer skippedCount = 0;
    private Integer failedCount = 0;
    private static final Set<String> SUPPORTED_OBJECTS = new Set<String> 
    {
        'Account',
        'Opportunity',
        'Contact',
        'Lead',
        'Case'
    };

    private class ShareRoute {
        Id recipientId;
        String objectName;
        ShareRoute(Id recipientId, String objectName) {
            this.recipientId = recipientId;
            this.objectName = objectName;
        }
    }

    public NoteSharingBatch(Map<String, List<Note_Sharing_Rule__c>> allRules, String objectName) {
        this.rules = allRules.get(objectName);
        this.objectName = objectName;
        for (String name : allRules.keySet()) {
            if (name != objectName) {
                remainingRules.put(name, allRules.get(name));
            }
        }
        buildSharingRoutes();
    }

    private void buildSharingRoutes() {
        for (Note_Sharing_Rule__c rule : this.rules) {
            if (rule.Sharing_Direction__c == SHARES_WITH) {
                addRoute(rule.Source_User__c, rule.Target_User__c, rule.Object_Name__c);
            } else if(rule.Sharing_Direction__c == SHARE_BOTH_WAYS) {
                addRoute(rule.Source_User__c, rule.Target_User__c, rule.Object_Name__c);
                addRoute(rule.Target_User__c, rule.Source_User__c, rule.Object_Name__c);
            }
        }
    }

    private void addRoute(Id sourceId, Id targetId, String objectName) {
        if (sourceId == null || targetId == null) {
            return;
        }
        authorIds.add(sourceId);
        recipientIds.add(targetId);
        if (!routesByAuthor.containsKey(sourceId)) {
            routesByAuthor.put(sourceId, new List<ShareRoute>());
        }
        routesByAuthor.get(sourceId).add(new ShareRoute(targetId, objectName));
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM '+ this.objectName);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id>linkedIds = new Set<Id>();
        for(SObject record: scope) {
            linkedIds.add((Id) record.get('Id'));
        }
        if (linkedIds.isEmpty()) {
        	return;
    	}
        Map<Id, ContentDocumentLink> notesInfo = getNotesInfo(linkedIds, this.authorIds);
        if (notesInfo.isEmpty()) {
        	return;
    	}
        Set<String> existingUserLinks = getExistingUserLinks();
        List<ContentDocumentLink> linksToInsert = getLinksToInsert(notesInfo, existingUserLinks);
        insertLinkRecords(linksToInsert);
    }

    private Map<Id, ContentDocumentLink> getNotesInfo(Set<Id> linkedIds, Set<Id> authorIds) {
        Map<Id, ContentDocumentLink> notesMap = new Map<Id, ContentDocumentLink>();
        Schema.SObjectType allowedObject = Schema.getGlobalDescribe().get(this.objectName);
        for(ContentDocumentLink cdl: [SELECT Id, ContentDocumentId, ContentDocument.Title, LinkedEntityId, ContentDocument.CreatedById            
            FROM ContentDocumentLink
            WHERE (ContentDocument.CreatedById IN :authorIds
            AND LinkedEntityId IN :linkedIds)
            OR LinkedEntityId=:recipientIds]) {
            if(cdl.LinkedEntityId.getSObjectType()==allowedObject) {
                notesMap.put(cdl.Id, cdl);
            } else {
                existingLinkMap .put(cdl.Id, cdl);
            }
        }
        return notesMap;
    }

    private String makeKey(Id noteId, Id userId) {
        return String.valueOf(noteId) + '|' + String.valueOf(userId);
    }

    private Set<String> getExistingUserLinks() {
        Set<String> existingUserLinks = new Set<String>();
        for (Id cdlRecId : existingLinkMap.keySet()) {
            ContentDocumentLink cdl = existingLinkMap.get(cdlRecId);
            existingUserLinks.add(makeKey(cdl.ContentDocumentId, cdl.LinkedEntityId));
        }
        return existingUserLinks;
    }

    private List<ContentDocumentLink> getLinksToInsert(Map<Id, ContentDocumentLink> notesInfo, Set<String> existingUserLinks) {
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (String title : notesInfo.keySet()) {
            ContentDocumentLink cdl = notesInfo.get(title);
            Id noteId = cdl.ContentDocumentId;
            Id noteCreatorId = cdl.ContentDocument.CreatedById;
            if (!routesByAuthor.containsKey(noteCreatorId)) {
                continue;
            }
            linksToInsert = validateAndGetLinks(noteCreatorId, noteId, existingUserLinks, linksToInsert);
        }
        return linksToInsert;
    }

    private List<ContentDocumentLink> validateAndGetLinks(Id noteCreatorId, Id noteId, Set<String> existingUserLinks, List<ContentDocumentLink> linksToInsert) {
        Set<String> pendingLinks = new Set<String>();
        for (ShareRoute route : routesByAuthor.get(noteCreatorId)) {
            String key = makeKey(noteId, route.recipientId);
            if (existingUserLinks.contains(key) || pendingLinks.contains(key)) {
                skippedCount++;
                continue;
            }
            linksToInsert.add(new ContentDocumentLink(
                ContentDocumentId = noteId,
                LinkedEntityId = route.recipientId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
            pendingLinks.add(key);
        }
        return linksToInsert;
    }

    private void insertLinkRecords(List<ContentDocumentLink> linksToInsert) {
        if (!linksToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(linksToInsert, false);
            for (Database.SaveResult result : results) {
                if (result.isSuccess()) {
                    sharedCount++;
                } else {
                    failedCount++;
                    for (Database.Error err : result.getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Note sharing failed: ' + err.getMessage());
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Note Sharing Batch Completed');
        System.debug('Successfully shared: ' + sharedCount);
        System.debug('Already shared/skipped: ' + skippedCount);
        System.debug('Failed: ' + failedCount);
        if (!remainingRules.isEmpty()) {
            String nextObject = new List<String>(remainingRules.keySet())[0];
            Database.executeBatch(new NoteSharingBatch(remainingRules, nextObject), 200);
        }
    }
}