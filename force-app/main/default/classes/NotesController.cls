public class NotesController {
    @AuraEnabled(cacheable=true)
    public static List<NoteWrapper> getNotes(String searchKey) {
        String searchTerm = '%' +
            (searchKey == null ? '' : searchKey.trim()) +
            '%';
        List<ContentNote> notesRec = [
            SELECT Id, Title, TextPreview, CreatedDate, CreatedById, CreatedBy.Name
            FROM ContentNote
            WHERE Title LIKE :searchTerm
            WITH USER_MODE
            ORDER BY Title
            LIMIT 50
        ];
        return getRelatedObject(notesRec);
    }

    public static List<NoteWrapper> getRelatedObject(List<ContentNote> allNotes) {
        Map<Id, ContentNote> noteMap = new Map<Id, ContentNote>();
		Map<Id, ContentDocumentLink> cdNoteMap = new Map<Id, ContentDocumentLink>();
        for(ContentNote cn: allNotes) {
            noteMap.put(cn.Id, cn);
        }
        for(ContentDocumentLink cdl: [SELECT Id, ContentDocumentId, LinkedEntityId, LinkedEntity.Name FROM ContentDocumentLink WHERE ContentDocumentId IN :noteMap.keySet()]) {
            String LinkedEntity = cdl.LinkedEntityId;
            if(!LinkedEntity.startsWith('005')) {
                cdNoteMap.put(cdl.ContentDocumentId, cdl);
            }
        }
        return getNoteRecords(noteMap, cdNoteMap);
    }

    public static List<NoteWrapper> getNoteRecords(Map<Id, ContentNote> noteMap, Map<Id, ContentDocumentLink> cdNoteMap) {
        Map<Id, NoteWrapper> notesMap = new Map<Id, NoteWrapper>();
		Map<Id, Id> linkMap = new Map<Id, Id>();
        Map<Id, String> typeMap = new Map<Id, String>();
        List<NoteWrapper> allNotes = new List<NoteWrapper>(); 
        for(Id noteId: noteMap.keySet()) {
            allNotes.add(getWrappedNotes(noteId, noteMap.get(noteId), cdNoteMap.get(noteId)));
        }
        return allNotes;
    }

    public static String getRelEntityName(Id recId) {
        return String.ValueOf(recId.getSObjectType());
    }

    public static NoteWrapper getWrappedNotes(Id noteId, ContentNote cnRec, ContentDocumentLink cdl) {
        NoteWrapper wrap = new NoteWrapper();
        wrap.Id = noteId;
        wrap.Title = cnRec.Title;
        wrap.TextPreview = cnRec.TextPreview;
        wrap.RelatedId = cdl.LinkedEntityId;
        wrap.RelatedEntityName = getRelEntityName(cdl.LinkedEntityId);
        wrap.RelatedName = cdl.LinkedEntity.Name;
        wrap.createdDate = cnRec.CreatedDate;
        wrap.CreatedByName = cnRec.CreatedBy.Name;
        wrap.CreatedById = cnRec.CreatedById;
        return wrap;
    }
}