const cds = require('@sap/cds');

module.exports = cds.service.impl(async function() {
    
    const { Aircraft, MaintenanceRecord, WorkOrder, MaintenanceAlert, Technician, Part } = this.entities;
    
    //===========================================================================
    // Event Handlers - Before/After CRUD Operations
    //===========================================================================
    
    // Before creating a new maintenance record, auto-calculate next due date
    this.before('CREATE', 'MaintenanceRecord', async (req) => {
        const { aircraft, maintenanceType } = req.data;
        
        if (aircraft && maintenanceType) {
            // Fetch maintenance type details
            const mtType = await SELECT.one.from('maintenance.MaintenanceType')
                .where({ ID: maintenanceType.ID || maintenanceType });
            
            if (mtType && req.data.scheduledDate) {
                const scheduledDate = new Date(req.data.scheduledDate);
                const nextDue = new Date(scheduledDate);
                nextDue.setDate(nextDue.getDate() + (mtType.intervalDays || 365));
                req.data.nextDueDate = nextDue.toISOString().split('T')[0];
            }
        }
        
        // Auto-generate work order number if not provided
        if (!req.data.workOrderNumber) {
            const year = new Date().getFullYear();
            const count = await SELECT.one`count(*) as count`.from('maintenance.MaintenanceRecord')
                .where`createdAt >= ${year}-01-01`;
            req.data.workOrderNumber = `WO-${year}-${String(count.count + 1).padStart(3, '0')}`;
        }
    });
    
    // After creating a work order, update aircraft status if needed
    this.after('CREATE', 'WorkOrder', async (req) => {
        const workOrder = req.data;
        if (workOrder.priority === 'Critical' || workOrder.priority === 'High') {
            await UPDATE('maintenance.Aircraft')
                .set({ status: 'Maintenance' })
                .where({ tailNumber: workOrder.aircraft_tailNumber });
        }
    });
    
    // Before updating aircraft, validate status transitions
    this.before('UPDATE', 'Aircraft', async (req) => {
        if (req.data.status) {
            const current = await SELECT.one.from('maintenance.Aircraft')
                .where({ tailNumber: req.data.tailNumber });
            
            // Business rule: Can't set to Active if there are critical alerts
            if (req.data.status === 'Active' && current.status !== 'Active') {
                const criticalAlerts = await SELECT.from('maintenance.MaintenanceAlert')
                    .where({ 
                        aircraft_tailNumber: current.tailNumber,
                        severity: 'Critical',
                        status: { in: ['Open', 'Acknowledged'] }
                    });
                
                if (criticalAlerts.length > 0) {
                    req.error(400, 'Cannot set aircraft to Active status while critical alerts are open');
                }
            }
        }
    });
    
    //===========================================================================
    // Custom Actions Implementation
    //===========================================================================
    
    // Schedule maintenance for an aircraft
    this.on('scheduleMaintenanceCheck', async (req) => {
        const { aircraftTailNumber, maintenanceTypeID, scheduledDate, technicianID } = req.data;
        
        try {
            // Validate aircraft exists and is available
            const aircraft = await SELECT.one.from('maintenance.Aircraft')
                .where({ tailNumber: aircraftTailNumber });
            
            if (!aircraft) {
                return req.error(404, `Aircraft ${aircraftTailNumber} not found`);
            }
            
            // Check if technician is available
            const technician = await SELECT.one.from('maintenance.Technician')
                .where({ ID: technicianID });
            
            if (!technician || technician.status !== 'Available') {
                return req.error(400, 'Selected technician is not available');
            }
            
            // Create maintenance record
            const newRecord = {
                ID: cds.utils.uuid(),
                aircraft_tailNumber: aircraftTailNumber,
                maintenanceType_ID: maintenanceTypeID,
                scheduledDate: scheduledDate,
                status: 'Scheduled',
                assignedTechnician_ID: technicianID,
                createdAt: new Date().toISOString(),
                createdBy: req.user.id || 'system'
            };
            
            await INSERT.into('maintenance.MaintenanceRecord').entries(newRecord);
            
            // Update aircraft status
            await UPDATE('maintenance.Aircraft')
                .set({ status: 'Maintenance' })
                .where({ tailNumber: aircraftTailNumber });
            
            // Update technician status
            await UPDATE('maintenance.Technician')
                .set({ status: 'Busy' })
                .where({ ID: technicianID });
            
            return `Maintenance scheduled successfully for aircraft ${aircraftTailNumber}`;
            
        } catch (error) {
            console.error('Error scheduling maintenance:', error);
            return req.error(500, 'Failed to schedule maintenance check');
        }
    });
    
    // Complete a work order
    this.on('completeWorkOrder', async (req) => {
        const { workOrderID, actualHours, findings, cost } = req.data;
        
        try {
            const workOrder = await SELECT.one.from('maintenance.WorkOrder')
                .where({ ID: workOrderID });
            
            if (!workOrder) {
                return req.error(404, 'Work order not found');
            }
            
            // Update work order
            await UPDATE('maintenance.WorkOrder')
                .set({
                    status: 'Completed',
                    actualHours: actualHours,
                    actualEnd: new Date().toISOString(),
                    cost: cost,
                    modifiedAt: new Date().toISOString(),
                    modifiedBy: req.user.id || 'system'
                })
                .where({ ID: workOrderID });
            
            // Update related maintenance record
            if (workOrder.maintenanceRecord_ID) {
                await UPDATE('maintenance.MaintenanceRecord')
                    .set({
                        findings: findings,
                        actualEndDate: new Date().toISOString(),
                        status: 'Completed',
                        cost: cost,
                        downtime: actualHours
                    })
                    .where({ ID: workOrder.maintenanceRecord_ID });
            }
            
            // Check if aircraft can return to service
            const openWorkOrders = await SELECT.from('maintenance.WorkOrder')
                .where({
                    aircraft_tailNumber: workOrder.aircraft_tailNumber,
                    status: { in: ['Open', 'Assigned', 'InProgress'] }
                });
            
            if (openWorkOrders.length === 0) {
                await UPDATE('maintenance.Aircraft')
                    .set({ status: 'Active' })
                    .where({ tailNumber: workOrder.aircraft_tailNumber });
            }
            
            // Free up technician
            if (workOrder.assignedTechnician_ID) {
                await UPDATE('maintenance.Technician')
                    .set({ status: 'Available' })
                    .where({ ID: workOrder.assignedTechnician_ID });
            }
            
            return `Work order ${workOrder.orderNumber} completed successfully`;
            
        } catch (error) {
            console.error('Error completing work order:', error);
            return req.error(500, 'Failed to complete work order');
        }
    });
    
    // Calculate risk score for predictive maintenance
    this.on('calculateRiskScore', async (req) => {
        const { aircraftTailNumber } = req.data;
        
        try {
            const aircraft = await SELECT.one.from('maintenance.Aircraft')
                .where({ tailNumber: aircraftTailNumber });
            
            if (!aircraft) {
                return req.error(404, `Aircraft ${aircraftTailNumber} not found`);
            }
            
            let riskScore = 0.0;
            
            // Factor 1: Flight hours vs maximum (40% weight)
            if (aircraft.maxFlightHours && aircraft.flightHours) {
                const hoursRatio = aircraft.flightHours / aircraft.maxFlightHours;
                riskScore += hoursRatio * 0.4;
            }
            
            // Factor 2: Cycle count vs maximum (30% weight)
            if (aircraft.maxCycles && aircraft.cycleCount) {
                const cyclesRatio = aircraft.cycleCount / aircraft.maxCycles;
                riskScore += cyclesRatio * 0.3;
            }
            
            // Factor 3: Time since last check (20% weight)
            if (aircraft.lastCheck) {
                const daysSinceCheck = (new Date() - new Date(aircraft.lastCheck)) / (1000 * 60 * 60 * 24);
                const checkRatio = Math.min(daysSinceCheck / 365, 1); // Cap at 1 year
                riskScore += checkRatio * 0.2;
            }
            
            // Factor 4: Open maintenance alerts (10% weight)
            const alerts = await SELECT.from('maintenance.MaintenanceAlert')
                .where({
                    aircraft_tailNumber: aircraftTailNumber,
                    status: { in: ['Open', 'Acknowledged'] }
                });
            
            const alertRisk = Math.min(alerts.length / 10, 1); // Cap at 10 alerts
            riskScore += alertRisk * 0.1;
            
            // Cap the risk score at 1.0
            riskScore = Math.min(riskScore, 1.0);
            
            // Update aircraft with calculated risk score
            await UPDATE('maintenance.Aircraft')
                .set({ riskScore: riskScore })
                .where({ tailNumber: aircraftTailNumber });
            
            return riskScore;
            
        } catch (error) {
            console.error('Error calculating risk score:', error);
            return req.error(500, 'Failed to calculate risk score');
        }
    });
    
    // Generate maintenance alerts based on current data
    this.on('generateMaintenanceAlerts', async (req) => {
        try {
            let alertsGenerated = 0;
            
            // Get all active aircraft
            const aircraft = await SELECT.from('maintenance.Aircraft')
                .where({ status: { in: ['Active', 'Maintenance'] } });
            
            for (const ac of aircraft) {
                const alerts = [];
                
                // Check for overdue maintenance
                if (ac.nextCheck && new Date(ac.nextCheck) < new Date()) {
                    alerts.push({
                        ID: cds.utils.uuid(),
                        aircraft_tailNumber: ac.tailNumber,
                        alertType: 'OverdueMaintenance',
                        severity: 'High',
                        title: 'Scheduled Maintenance Overdue',
                        description: `Aircraft ${ac.tailNumber} has overdue scheduled maintenance. Next check was due ${ac.nextCheck}.`,
                        dueDate: ac.nextCheck,
                        status: 'Open',
                        createdAt: new Date().toISOString(),
                        createdBy: 'alert_system'
                    });
                }
                
                // Check for approaching maintenance
                if (ac.nextCheck) {
                    const daysUntilDue = (new Date(ac.nextCheck) - new Date()) / (1000 * 60 * 60 * 24);
                    if (daysUntilDue > 0 && daysUntilDue <= 30) {
                        alerts.push({
                            ID: cds.utils.uuid(),
                            aircraft_tailNumber: ac.tailNumber,
                            alertType: 'DueMaintenance',
                            severity: daysUntilDue <= 7 ? 'High' : 'Medium',
                            title: 'Scheduled Maintenance Due Soon',
                            description: `Aircraft ${ac.tailNumber} has scheduled maintenance due in ${Math.ceil(daysUntilDue)} days.`,
                            dueDate: ac.nextCheck,
                            status: 'Open',
                            createdAt: new Date().toISOString(),
                            createdBy: 'alert_system'
                        });
                    }
                }
                
                // Check for high risk score
                if (ac.riskScore && ac.riskScore >= 0.7) {
                    alerts.push({
                        ID: cds.utils.uuid(),
                        aircraft_tailNumber: ac.tailNumber,
                        alertType: 'PredictiveAlert',
                        severity: 'Critical',
                        title: 'High Risk Score Detected',
                        description: `Aircraft ${ac.tailNumber} has a high predictive maintenance risk score of ${ac.riskScore.toFixed(2)}. Immediate inspection recommended.`,
                        dueDate: new Date().toISOString().split('T')[0],
                        status: 'Open',
                        createdAt: new Date().toISOString(),
                        createdBy: 'predictive_system'
                    });
                }
                
                // Insert alerts (avoiding duplicates)
                for (const alert of alerts) {
                    const existing = await SELECT.one.from('maintenance.MaintenanceAlert')
                        .where({
                            aircraft_tailNumber: alert.aircraft_tailNumber,
                            alertType: alert.alertType,
                            status: { in: ['Open', 'Acknowledged'] }
                        });
                    
                    if (!existing) {
                        await INSERT.into('maintenance.MaintenanceAlert').entries(alert);
                        alertsGenerated++;
                    }
                }
            }
            
            return alertsGenerated;
            
        } catch (error) {
            console.error('Error generating alerts:', error);
            return req.error(500, 'Failed to generate maintenance alerts');
        }
    });
    
    // Update aircraft status with validation
    this.on('updateAircraftStatus', async (req) => {
        const { aircraftTailNumber, newStatus } = req.data;
        
        try {
            const aircraft = await SELECT.one.from('maintenance.Aircraft')
                .where({ tailNumber: aircraftTailNumber });
            
            if (!aircraft) {
                return req.error(404, `Aircraft ${aircraftTailNumber} not found`);
            }
            
            // Validate status transition
            const validStatuses = ['Active', 'Maintenance', 'Grounded', 'OutOfService'];
            if (!validStatuses.includes(newStatus)) {
                return req.error(400, 'Invalid status value');
            }
            
            await UPDATE('maintenance.Aircraft')
                .set({ status: newStatus })
                .where({ tailNumber: aircraftTailNumber });
            
            return `Aircraft ${aircraftTailNumber} status updated to ${newStatus}`;
            
        } catch (error) {
            console.error('Error updating aircraft status:', error);
            return req.error(500, 'Failed to update aircraft status');
        }
    });
    
    //===========================================================================
    // Custom Functions Implementation
    //===========================================================================
    
    // Get next maintenance due date for an aircraft
    this.on('getNextMaintenanceDue', async (req) => {
        const { aircraftTailNumber } = req.data;
        
        const aircraft = await SELECT.one.from('maintenance.Aircraft')
            .where({ tailNumber: aircraftTailNumber });
        
        return aircraft ? aircraft.nextCheck : null;
    });
    
    // Calculate maintenance cost for a period
    this.on('getMaintenanceCost', async (req) => {
        const { aircraftTailNumber, fromDate, toDate } = req.data;
        
        const records = await SELECT.from('maintenance.MaintenanceRecord')
            .where({
                aircraft_tailNumber: aircraftTailNumber,
                actualStartDate: { '>=': fromDate },
                actualEndDate: { '<=': toDate }
            });
        
        const totalCost = records.reduce((sum, record) => sum + (record.cost || 0), 0);
        return totalCost;
    });
    
    // Get available technicians for maintenance type
    this.on('getAvailableTechnicians', async (req) => {
        const { maintenanceTypeID, requiredDate } = req.data;
        
        const technicians = await SELECT.from('maintenance.Technician')
            .where({ status: 'Available' });
        
        return technicians.map(t => `${t.firstName} ${t.lastName} (${t.employeeId})`);
    });
    
});
