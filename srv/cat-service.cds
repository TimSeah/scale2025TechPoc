using maintenance as my from '../db/data-model';

// Main service for SkyLink Airlines Maintenance System
service MaintenanceService {
   
   //===========================================================================
   // Main Entities - Full CRUD operations for transactional capabilities
   //===========================================================================
   
   @cds.redirection.target
   entity Aircraft as projection on my.Aircraft;
   entity MaintenanceRecord as projection on my.MaintenanceRecord;
   entity WorkOrder as projection on my.WorkOrder;
   
   @cds.redirection.target
   entity Technician as projection on my.Technician;
   entity MaintenanceType as projection on my.MaintenanceType;
   
   @cds.redirection.target
   entity Part as projection on my.Part;
   entity PartUsage as projection on my.PartUsage;
   entity FlightSchedule as projection on my.FlightSchedule;
   
   @cds.redirection.target
   entity MaintenanceAlert as projection on my.MaintenanceAlert;
   
   //===========================================================================
   // Read-Only Views for Analytics and Dashboards
   //===========================================================================
   
   @readonly
   view MaintenanceDashboard as select from my.Aircraft {
      key tailNumber,
      model,
      status,
      flightHours,
      riskScore,
      maintenanceUrgency,
      nextCheck,
      location,
      case 
         when nextCheck < $now then 'Overdue'
         when nextCheck < $now + 30 then 'Due Soon'
         else 'OK'
      end as maintenanceStatus : String(10),
      
      // Count related records
      maintenanceRecords.status as recordCount,
      workOrders.status as workOrderCount
   };
   
   @readonly
   view TechnicianWorkload as select from my.Technician {
      key ID,
      employeeId,
      firstName,
      lastName,
      status,
      specializations,
      currentLocation,
      
      // Count assigned work
      assignedWork.status as workOrderCount
   };
   
   @readonly
   view AlertsSummary as select from my.MaintenanceAlert {
      key severity,
      key alertType,
      key status,
      count(*) as alertCount : Integer
   } group by severity, alertType, status;
   
   @readonly
   view PartsInventory as select from my.Part {
      key ID,
      partNumber,
      name,
      category,
      stockQuantity,
      minimumStock,
      status,
      case 
         when stockQuantity <= 0 then 'Out of Stock'
         when stockQuantity <= minimumStock then 'Low Stock'
         else 'In Stock'
      end as stockStatus : String(15)
   };
   
   //===========================================================================
   // Actions for Business Logic
   //===========================================================================
   
   // Schedule maintenance for an aircraft
   action scheduleMaintenanceCheck(
      aircraftTailNumber: String(10),
      maintenanceTypeID: UUID,
      scheduledDate: Date,
      technicianID: UUID
   ) returns String;
   
   // Complete a work order
   action completeWorkOrder(
      workOrderID: UUID,
      actualHours: Integer,
      findings: String(1000),
      cost: Decimal(10,2)
   ) returns String;
   
   // Calculate risk score for predictive maintenance
   action calculateRiskScore(aircraftTailNumber: String(10)) returns Decimal(3,2);
   
   // Generate maintenance alerts
   action generateMaintenanceAlerts() returns Integer;
   
   // Update aircraft status
   action updateAircraftStatus(
      aircraftTailNumber: String(10),
      newStatus: String(20)
   ) returns String;
   
   //===========================================================================
   // Functions for Calculations
   //===========================================================================
   
   // Get next maintenance due date
   function getNextMaintenanceDue(aircraftTailNumber: String(10)) returns Date;
   
   // Calculate maintenance cost for period
   function getMaintenanceCost(
      aircraftTailNumber: String(10),
      fromDate: Date,
      toDate: Date
   ) returns Decimal(10,2);
   
   // Get available technicians for maintenance type
   function getAvailableTechnicians(
      maintenanceTypeID: UUID,
      requiredDate: Date
   ) returns array of String;
}

//===========================================================================
// UI Annotations
//===========================================================================

// Aircraft List Page
annotate MaintenanceService.Aircraft with @(
   UI.HeaderInfo: {
      TypeName: 'Aircraft',
      TypeNamePlural: 'Aircraft Fleet',
      Title: { Value: tailNumber },
      Description: { Value: model }
   },
   UI.LineItem: [
      { Value: tailNumber, Label: 'Tail Number' },
      { Value: model, Label: 'Aircraft Model' },
      { Value: status, Label: 'Status', Criticality: 2 },
      { Value: flightHours, Label: 'Flight Hours' },
      { Value: riskScore, Label: 'Risk Score', Criticality: 1 },
      { Value: maintenanceUrgency, Label: 'Urgency', Criticality: 3 },
      { Value: nextCheck, Label: 'Next Check Due' },
      { Value: location, Label: 'Current Location' }
   ],
   UI.SelectionFields: [
      status,
      model,
      maintenanceUrgency,
      location
   ],
   UI.Facets: [
      {
         $Type: 'UI.ReferenceFacet',
         Label: 'Aircraft Details',
         Target: '@UI.FieldGroup#AircraftInfo'
      },
      {
         $Type: 'UI.ReferenceFacet',
         Label: 'Maintenance Records',
         Target: 'maintenanceRecords/@UI.LineItem'
      },
      {
         $Type: 'UI.ReferenceFacet',
         Label: 'Work Orders',
         Target: 'workOrders/@UI.LineItem'
      },
      {
         $Type: 'UI.ReferenceFacet',
         Label: 'Flight Schedule',
         Target: 'flightSchedule/@UI.LineItem'
      },
      {
         $Type: 'UI.ReferenceFacet',
         Label: 'Alerts',
         Target: 'alerts/@UI.LineItem'
      }
   ],
   UI.FieldGroup #AircraftInfo: {
      Data: [
         { Value: tailNumber, Label: 'Tail Number' },
         { Value: model, Label: 'Model' },
         { Value: manufacturer, Label: 'Manufacturer' },
         { Value: yearManufactured, Label: 'Year Manufactured' },
         { Value: status, Label: 'Status' },
         { Value: location, Label: 'Current Location' },
         { Value: flightHours, Label: 'Flight Hours' },
         { Value: cycleCount, Label: 'Cycle Count' },
         { Value: maxFlightHours, Label: 'Max Flight Hours' },
         { Value: maxCycles, Label: 'Max Cycles' },
         { Value: lastCheck, Label: 'Last Check' },
         { Value: nextCheck, Label: 'Next Check' },
         { Value: riskScore, Label: 'Risk Score' },
         { Value: maintenanceUrgency, Label: 'Maintenance Urgency' },
         { Value: predictedIssues, Label: 'Predicted Issues' }
      ]
   }
);

// Work Orders
annotate MaintenanceService.WorkOrder with @(
   UI.HeaderInfo: {
      TypeName: 'Work Order',
      TypeNamePlural: 'Work Orders',
      Title: { Value: orderNumber },
      Description: { Value: title }
   },
   UI.LineItem: [
      { Value: orderNumber, Label: 'Order Number' },
      { Value: title, Label: 'Title' },
      { Value: status, Label: 'Status', Criticality: 2 },
      { Value: priority, Label: 'Priority', Criticality: 1 },
      { Value: aircraft.tailNumber, Label: 'Aircraft' },
      { Value: assignedTechnician.firstName, Label: 'Assigned To' },
      { Value: scheduledStart, Label: 'Scheduled Start' },
      { Value: estimatedHours, Label: 'Est. Hours' }
   ]
);

// Maintenance Records
annotate MaintenanceService.MaintenanceRecord with @(
   UI.HeaderInfo: {
      TypeName: 'Maintenance Record',
      TypeNamePlural: 'Maintenance Records',
      Title: { Value: workOrderNumber }
   },
   UI.LineItem: [
      { Value: workOrderNumber, Label: 'Work Order' },
      { Value: aircraft.tailNumber, Label: 'Aircraft' },
      { Value: maintenanceType.name, Label: 'Maintenance Type' },
      { Value: status, Label: 'Status', Criticality: 2 },
      { Value: scheduledDate, Label: 'Scheduled Date' },
      { Value: assignedTechnician.firstName, Label: 'Technician' },
      { Value: cost, Label: 'Cost' }
   ]
);

// Technicians
annotate MaintenanceService.Technician with @(
   UI.HeaderInfo: {
      TypeName: 'Technician',
      TypeNamePlural: 'Technicians',
      Title: { Value: firstName },
      Description: { Value: lastName }
   },
   UI.LineItem: [
      { Value: employeeId, Label: 'Employee ID' },
      { Value: firstName, Label: 'First Name' },
      { Value: lastName, Label: 'Last Name' },
      { Value: status, Label: 'Status', Criticality: 2 },
      { Value: specializations, Label: 'Specializations' },
      { Value: experienceYears, Label: 'Experience (Years)' },
      { Value: currentLocation, Label: 'Location' }
   ]
);

// Maintenance Alerts
annotate MaintenanceService.MaintenanceAlert with @(
   UI.HeaderInfo: {
      TypeName: 'Alert',
      TypeNamePlural: 'Maintenance Alerts',
      Title: { Value: title }
   },
   UI.LineItem: [
      { Value: title, Label: 'Alert Title' },
      { Value: severity, Label: 'Severity', Criticality: 1 },
      { Value: alertType, Label: 'Type' },
      { Value: aircraft.tailNumber, Label: 'Aircraft' },
      { Value: status, Label: 'Status', Criticality: 2 },
      { Value: dueDate, Label: 'Due Date' },
      { Value: assignedTo.firstName, Label: 'Assigned To' }
   ]
);

// Flight Schedule
annotate MaintenanceService.FlightSchedule with @(
   UI.HeaderInfo: {
      TypeName: 'Flight Schedule',
      TypeNamePlural: 'Flight Schedules',
      Title: { Value: flightNumber }
   },
   UI.LineItem: [
      { Value: flightNumber, Label: 'Flight Number' },
      { Value: departure, Label: 'Departure' },
      { Value: arrival, Label: 'Arrival' },
      { Value: scheduledDeparture, Label: 'Scheduled Departure' },
      { Value: scheduledArrival, Label: 'Scheduled Arrival' },
      { Value: status, Label: 'Status', Criticality: 2 },
      { Value: estimatedFlightHours, Label: 'Flight Hours' },
      { Value: maintenanceImpact, Label: 'Maintenance Impact' }
   ]
);
