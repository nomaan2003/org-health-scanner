import { LightningElement, wire } from 'lwc';
import getLatestScan from '@salesforce/apex/OrgScanDashboardController.getLatestScan';
import getFindings from '@salesforce/apex/OrgScanDashboardController.getFindings';

const COLUMNS = [
    { label: 'Severity', fieldName: 'Severity__c', type: 'text' },
    { label: 'Category', fieldName: 'Category__c', type: 'text' },
    { label: 'Component Type', fieldName: 'Component_Type__c', type: 'text' },
    { label: 'Component Name', fieldName: 'Component_Name__c', type: 'text' },
    { label: 'Description', fieldName: 'Description__c', type: 'text', wrapText: true },
    { label: 'Status', fieldName: 'Status__c', type: 'text' }
];

export default class OrgScanDashboard extends LightningElement {
    scan;
    allFindings = [];
    columns = COLUMNS;
    severityFilter = 'All';

    severityOptions = [
        { label: 'All', value: 'All' },
        { label: 'Critical', value: 'Critical' },
        { label: 'High', value: 'High' },
        { label: 'Medium', value: 'Medium' },
        { label: 'Low', value: 'Low' }
    ];

    @wire(getLatestScan)
    wiredScan({ data, error }) {
        if (data) {
            this.scan = data;
            this.loadFindings(data.Id);
        } else if (error) {
            console.error('Error loading scan:', error);
        }
    }

    loadFindings(scanId) {
        getFindings({ scanId })
            .then((result) => {
                this.allFindings = result;
            })
            .catch((error) => {
                console.error('Error loading findings:', error);
            });
    }

    handleSeverityChange(event) {
        this.severityFilter = event.detail.value;
    }

    get filteredFindings() {
        if (this.severityFilter === 'All') {
            return this.allFindings;
        }
        return this.allFindings.filter((f) => f.Severity__c === this.severityFilter);
    }

    get scoreStyle() {
        const score = this.scan ? this.scan.Health_Score__c : 0;
        let color = '#c23934'; // red
        if (score >= 70) color = '#04844b'; // green
        else if (score >= 40) color = '#fe9339'; // orange
        return `color: ${color};`;
    }
}