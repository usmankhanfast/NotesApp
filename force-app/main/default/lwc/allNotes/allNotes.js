import { LightningElement } from 'lwc';
import getNotes from '@salesforce/apex/NotesController.getNotes';

export default class RecordTable extends LightningElement {

    notes = [];
    searchKey = '';
    isLoading = false;

    columns = [
        {
            label: 'Title',
            fieldName: 'recordUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'Title' },
                target: '_self'
            }
        },
        {
            label: 'Body',
            fieldName: 'TextPreview',
            type: 'text'
        },
        {
            label: 'Type',
            fieldName: 'RelatedEntityName',
            type: 'text'
        },
        {
            label: 'Name',
            fieldName: 'relatedUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'RelatedName' },
                target: '_self'
            }
        },
        {
            label: 'Created Date',
            fieldName: 'CreatedDate',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                hour12: true
            }
        },
        {
            label: 'Created By',
            fieldName: 'createdByUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'CreatedByName' },
                target: '_self'
            }
        }
    ];

    connectedCallback() {
        this.loadNotes();
    }

    handleRefresh() {
        this.loadNotes();
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
        this.loadNotes();
    }

    async loadNotes() {
        this.isLoading = true;

        try {
            const result = await getNotes({
                searchKey: this.searchKey
            });

            this.notes = result.map(note => ({
                ...note,
                recordUrl: '/' + note.Id,
                relatedUrl: '/' + note.RelatedId,
                createdByUrl: '/' + note.CreatedById
            }));
        } catch (error) {
            this.notes = [];
            console.error(
                'Error loading notes:',
                error
            );

        } finally {
            this.isLoading = false;
        }
    }

    get showNoRecords() {
        return !this.isLoading && this.notes.length === 0;
    }

    get cardTitle() {
        return `Notes (${this.notes.length})`;
    }
}