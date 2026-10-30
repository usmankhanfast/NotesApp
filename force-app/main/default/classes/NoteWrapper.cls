public class NoteWrapper {
    @AuraEnabled public Id Id { get; set; }
    @AuraEnabled public Id RelatedId { get; set; }
    @AuraEnabled public Id CreatedById { get; set; }
    @AuraEnabled public String Title { get; set; }
    @AuraEnabled public String TextPreview { get; set; }
    @AuraEnabled public String RelatedEntityName { get; set; }
    @AuraEnabled public String RelatedName { get; set; }
    @AuraEnabled public DateTime CreatedDate { get; set; }
    @AuraEnabled public String CreatedByName { get; set; }
}