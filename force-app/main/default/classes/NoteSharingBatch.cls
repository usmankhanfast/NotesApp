public without sharing class NoteSharingBatch implements Database.Batchable<SObject>, Database.Stateful {
    private List<Note_Sharing_Rule__c> rules;
    String objectName;
    private Map<Id, List<ShareRoute>> routesByAuthor = new Map<Id, List<ShareRoute>>();
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

    public NoteSharingBatch(List<Note_Sharing_Rule__c> rules, String objectName) {
        this.rules = rules;
        this.objectName = objectName; 
        buildSharingRoutes();
    }

    private void buildSharingRoutes() {
        for (Note_Sharing_Rule__c rule : this.rules) {
            if (rule.Sharing_Direction__c == 'Shares with') {
                addRoute(rule.Source_User__c, rule.Target_User__c, rule.Object_Name__c);
            } else if(rule.Sharing_Direction__c == 'Share Vice Versa') {
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
        
        List<ContentDocumentLink> notesInfo = getNotesInfo(linkedIds, this.authorIds);
        if (notesInfo.isEmpty()) {
        	return;
    	}

        Set<String> existingUserLinks = getExistingUserLinks(notesInfo);
        List<ContentDocumentLink> linksToInsert = getLinksToInsert(notesInfo, existingUserLinks);
        insertLinkRecords(linksToInsert);
    }

    private List<ContentDocumentLink> getNotesInfo(Set<Id> linkedIds, Set<Id> authorIds) {
        List<ContentDocumentLink> contentDocLinks = new List<ContentDocumentLink>();
        for(ContentDocumentLink cdl: [SELECT Id, ContentDocumentId, LinkedEntityId, ContentDocument.CreatedById
            FROM ContentDocumentLink
            WHERE ContentDocument.CreatedById IN :authorIds
            AND (LinkedEntityId IN :linkedIds OR LinkedEntityId IN :recipientIds) 
        ]) {
            if (cdl.LinkedEntityId.getSObjectType() == User.SObjectType) {
                contentDocLinks.add(cdl);
            }
        }
        return contentDocLinks;
    }

    private String makeKey(Id noteId, Id userId) {
        return String.valueOf(noteId) + '|' +
               String.valueOf(userId);
    }

    private Set<String> getExistingUserLinks(List<ContentDocumentLink> notesInfo) {
        Set<String> existingUserLinks = new Set<String>();
        for (ContentDocumentLink cdl : notesInfo) {
            if (cdl.LinkedEntityId.getSObjectType() == User.SObjectType) {
                existingUserLinks.add(makeKey(cdl.ContentDocumentId, cdl.LinkedEntityId));
            }
        }
        return existingUserLinks;
    }

    private List<ContentDocumentLink> getLinksToInsert(List<ContentDocumentLink> notesInfo, Set<String> existingUserLinks) {
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (ContentDocumentLink noteInfo : notesInfo) {
            Id noteId = noteInfo.ContentDocumentId;
            Id noteCreatorId = noteInfo.ContentDocument.CreatedById;
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
    }
}