import { LightningElement } from 'lwc';
import getAccounts from '@salesforce/apex/NotesController.getNotes';

export default class RecordTable extends LightningElement {

    accounts = [];
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
            type: 'Date',
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
            fieldName: 'CreatedByName',
            type: 'text'
        }
    ];

    connectedCallback() {
        this.loadAccounts();
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
        this.loadAccounts();
    }

    async loadAccounts() {
        this.isLoading = true;

        try {
            const result = await getAccounts({
                searchKey: this.searchKey
            });

            this.accounts = result.map(note => ({
                ...note,
                recordUrl: '/' + note.Id,
                relatedUrl: '/' + note.RelatedId
            }));
        } catch (error) {
            this.accounts = [];
            console.error(
                'Error loading accounts:',
                error
            );

        } finally {
            this.isLoading = false;
        }
    }

    get showNoRecords() {
        return !this.isLoading && this.accounts.length === 0;
    }
}