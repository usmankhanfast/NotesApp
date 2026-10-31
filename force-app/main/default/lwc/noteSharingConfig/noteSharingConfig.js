import { LightningElement } from 'lwc';
import getActiveUsers from '@salesforce/apex/NoteSharingConfigController.getActiveUsers';
import getRules from '@salesforce/apex/NoteSharingConfigController.getRules';
import saveRules from '@salesforce/apex/NoteSharingConfigController.saveRules';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class NoteSharingConfig extends LightningElement {
    rows = [];
    userOptions = [];
    isLoading = false;

    rowCounter = 0;

    sharingOptions = [
        { label: 'Both ways', value: 'Both' },
        { label: 'Source → Target', value: 'Source to Target' },
        { label: 'Target → Source', value: 'Target to Source' }
    ];
    objectOptions = [
        { label: 'All Supported Objects', value: 'All Supported Objects' },
        { label: 'Account', value: 'Account' },
        { label: 'Opportunity', value: 'Opportunity' },
        { label: 'Contact', value: 'Contact' },
        { label: 'Lead', value: 'Lead' },
        { label: 'Case', value: 'Case' }
    ];

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            const [users, savedRules] = await Promise.all([
                getActiveUsers(),
                getRules()
            ]);

            this.userOptions = users.map(user => ({
                label: user.Name,
                value: user.Id
            }));

            this.rows = savedRules.map(rule => ({
                ...rule,
                rowKey: this.createRowKey(),
                isActive: rule.isActive ?? true
            }));

            if (this.rows.length === 0) {
                this.rows = [this.createEmptyRow()];
            }

        } catch (error) {
            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    createRowKey() {
        this.rowCounter += 1;
        return `row-${this.rowCounter}`;
    }

    createEmptyRow() {
        return {
            rowKey: this.createRowKey(),
            id: null,
            sourceUserId: '',
            targetUserId: '',
            sharingDirection: 'Source to Target',
            objectName: 'All Supported Objects',
            isActive: true
        };
    }

    handleAddRow() {
        this.rows = [
            ...this.rows,
            this.createEmptyRow()
        ];
    }

    handleRemoveRow(event) {
        const rowKey = event.currentTarget.dataset.rowkey;
        this.rows = this.rows.filter(
            row => row.rowKey !== rowKey
        );
        if (this.rows.length === 0) {
            this.rows = [this.createEmptyRow()];
        }
    }

    handleFieldChange(event) {
        const rowKey = event.currentTarget.dataset.rowkey;
        const field = event.currentTarget.dataset.field;

        const value = field === 'isActive'
            ? event.target.checked
            : event.detail.value;

        this.rows = this.rows.map(row => {
            if (row.rowKey === rowKey) {
                return {
                    ...row,
                    [field]: value
                };
            }
            return row;
        });
    }

    async handleSave() {
        const inputs = [
            ...this.template.querySelectorAll(
                'lightning-combobox'
            )
        ];

        const allValid = inputs.reduce((valid, input) => {
            input.reportValidity();
            return valid && input.checkValidity();
        }, true);

        if (!allValid) {
            this.showToast(
                'Missing Information',
                'Complete all dropdown fields before saving.',
                'warning'
            );
            return;
        }

        const hasInvalidRow = this.rows.some(row =>
            !row.sourceUserId ||
            !row.targetUserId ||
            row.sourceUserId === row.targetUserId
        );

        if (hasInvalidRow) {
            this.showToast(
                'Invalid Configuration',
                'Select different Source and Target users for every row.',
                'error'
            );
            return;
        }

        this.isLoading = true;

        try {
            // Send only fields that Apex needs.
            const payload = this.rows.map(row => ({
                id: row.id || null,
                sourceUserId: row.sourceUserId,
                targetUserId: row.targetUserId,
                sharingDirection: row.sharingDirection,
                objectName: row.objectName,
                isActive: row.isActive
            }));

            await saveRules({ rows: payload });

            this.showToast(
                'Success',
                'Note sharing configurations saved successfully.',
                'success'
            );

            await this.loadData();

        } catch (error) {
            this.showToast(
                'Save Failed',
                this.getErrorMessage(error),
                'error'
            );
        } finally {
            this.isLoading = false;
        }
    }

    getErrorMessage(error) {
        return error?.body?.message ||
            error?.message ||
            'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}