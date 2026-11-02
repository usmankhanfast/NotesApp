import { LightningElement, wire } from 'lwc';
import getActiveUsers from '@salesforce/apex/NoteSharingConfigController.getActiveUsers';
import deleteRule from '@salesforce/apex/NoteSharingConfigController.deleteRule';
import getRules from '@salesforce/apex/NoteSharingConfigController.getRules';
import saveRules from '@salesforce/apex/NoteSharingConfigController.saveRules';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import NOTE_SHARING_RULE_OBJECT from '@salesforce/schema/Note_Sharing_Rule__c';
import SHARING_DIRECTION_FIELD from '@salesforce/schema/Note_Sharing_Rule__c.Sharing_Direction__c';
import OBJECT_NAME_FIELD from '@salesforce/schema/Note_Sharing_Rule__c.Object_Name__c';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import LightningConfirm from 'lightning/confirm';

export default class NoteSharingConfig extends LightningElement {
    rows = [];
    userOptions = [];
    sharingOptions = [];
    objectOptions = [];
    isLoading = false;

    rowCounter = 0;
    recordTypeId;

    @wire(getObjectInfo, { objectApiName: NOTE_SHARING_RULE_OBJECT })
    wiredObjectInfo({ data, error }) {
        if (data) {
            this.recordTypeId = data.defaultRecordTypeId;
        } else if (error) {
            console.error('Object Info Error:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: SHARING_DIRECTION_FIELD
    })
    wiredSharingValues({ data, error }) {
        if (data) {
            this.sharingOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error loading sharing options:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: OBJECT_NAME_FIELD
    })
    wiredObjectValues({ data, error }) {
        if (data) {
            this.objectOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error loading object options:', error);
        }
    }

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
            objectName: '',
            isActive: true
        };
    }

    handleAddRow() {
        this.rows = [
            ...this.rows,
            this.createEmptyRow()
        ];
    }

    async handleRemoveRow(event) {
        const rowKey = event.currentTarget.dataset.rowkey;
        const row = this.rows.find(item => item.rowKey === rowKey);
        if (!row) {
            console.log('Row not found:', rowKey);
            return;
        }

        try {
            if (row.id) {
                const confirmed = await this.confirmDelete();
                if (!confirmed) {
                    return;
                }
                await deleteRule({ ruleId: row.id });
            }
            this.rows = this.rows.filter(item => item.rowKey !== rowKey);
            this.showToast(
                'Success',
                'Sharing rule deleted successfully.',
                'success'
            );
        } catch (error) {
            this.showToast(
                'Error',
                error.body?.message || 'Unable to delete sharing rule.',
                'error'
            );
        }
    }

    async confirmDelete() {
        return await LightningConfirm.open({
            message: 'Are you sure you want to delete this sharing rule?',
            variant: 'headerless',
            label: 'Confirm Deletion'
        });
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
        const inputs = [...this.template.querySelectorAll('lightning-combobox')];
        if (!this.validateRows()) {
            return;
        }
        if (!this.validateDuplicateRows()) {
            return;
        }
        this.isLoading = true;

        try {
            const payload = this.rows.map(row => ({
                id: row.id || null,
                sourceUserId: row.sourceUserId,
                targetUserId: row.targetUserId,
                sharingDirection: row.sharingDirection,
                objectName: row.objectName,
                isActive: row.isActive
            }));

            await saveRules({ rows: payload });
            await this.loadData();
            this.showToast(
                'Success',
                'Note sharing configurations saved successfully.',
                'success'
            );
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

    validateRows() {
        const emptySource = this.rows.some(row => !row.sourceUserId);
        const emptyTarget = this.rows.some(row => !row.targetUserId);
        const emptyObject = this.rows.some(row => !row.objectName);

        const sameUsers = this.rows.some(row =>
            row.sourceUserId &&
            row.targetUserId &&
            row.sourceUserId === row.targetUserId
        );

        if (emptySource) {
            this.showToast('Error', 'Please fill in the Source User field.', 'error');
            return false;
        }

        if (emptyTarget) {
            this.showToast('Error', 'Please fill in the Target User field.', 'error');
            return false;
        }

        if (emptyObject) {
            this.showToast('Error', 'Please select an Object.', 'error');
            return false;
        }

        if (sameUsers) {
            this.showToast('Error', 'Source User and Target User cannot be the same.', 'error');
            return false;
        }
        return true;
    }

    validateDuplicateRows() {
        const seen = new Set();
        for (const row of this.rows) {
            const key = [
                row.sourceUserId,
                row.targetUserId,
                row.sharingDirection,
                row.objectName
            ].join('|');

            if (seen.has(key)) {
                this.showToast(
                    'Duplicate Rule',
                    'This sharing rule already exists. Please remove the duplicate on '+row.rowKey,
                    'error'
                );
                return false;
            }
            seen.add(key);
        }
        return true;
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