namespace maintenance;

// Aircraft entity with enhanced fields for SkyLink Airlines
entity Aircraft {
    key tailNumber          : String(10);
        model               : String(50);
        manufacturer        : String(50);
        yearManufactured    : Integer;
        lastCheck           : Date;
        nextCheck           : Date;
        flightHours         : Integer;
        cycleCount          : Integer;  // Landing/takeoff cycles
        status              : String(20); // Active, Maintenance, Grounded, OutOfService
        location            : String(100); // Current airport/hangar
        maxFlightHours      : Integer;  // Maximum flight hours before maintenance
        maxCycles           : Integer;  // Maximum cycles before maintenance
        // Predictive maintenance fields
        riskScore           : Decimal(3,2); // Risk score 0.00-1.00
        predictedIssues     : String(500);
        maintenanceUrgency  : String(10); // Low, Medium, High, Critical
        
        // Navigation to related entities
        maintenanceRecords  : Composition of many MaintenanceRecord on maintenanceRecords.aircraft = $self;
        workOrders         : Composition of many WorkOrder on workOrders.aircraft = $self;
        flightSchedule     : Composition of many FlightSchedule on flightSchedule.aircraft = $self;
        alerts             : Composition of many MaintenanceAlert on alerts.aircraft = $self;
}

// Maintenance types (A-Check, B-Check, C-Check, D-Check, etc.)
entity MaintenanceType {
    key ID              : UUID;
        name                : String(50);
        description         : String(500);
        intervalHours       : Integer;  // Hours between maintenance
        intervalDays        : Integer;  // Days between maintenance
        intervalCycles      : Integer;  // Cycles between maintenance
        estimatedDuration   : Integer;  // Duration in hours
        requiredTechnicians : Integer;
        cost                : Decimal(10,2);
        priority            : Integer; // 1-5, with 1 being highest priority
        
        maintenanceRecords  : Composition of many MaintenanceRecord on maintenanceRecords.maintenanceType = $self;
}

// Individual maintenance records
entity MaintenanceRecord {
    key ID              : UUID;
        aircraft            : Association to Aircraft;
        maintenanceType     : Association to MaintenanceType;
        scheduledDate       : Date;
        actualStartDate     : DateTime;
        actualEndDate       : DateTime;
        status              : String(20); // Scheduled, InProgress, Completed, Cancelled, Overdue
        assignedTechnician  : Association to Technician;
        workOrderNumber     : String(20);
        findings            : String(1000);
        actionsTaken        : String(1000);
        nextDueDate         : Date;
        cost                : Decimal(10,2);
        downtime            : Integer; // Hours of aircraft downtime
        createdAt           : DateTime;
        createdBy           : String(50);
        modifiedAt          : DateTime;
        modifiedBy          : String(50);
        
        workOrders          : Composition of many WorkOrder on workOrders.maintenanceRecord = $self;
}

// Work orders for specific maintenance tasks
entity WorkOrder {
    key ID              : UUID;
        orderNumber         : String(20);
        aircraft            : Association to Aircraft;
        maintenanceRecord   : Association to MaintenanceRecord;
        title               : String(100);
        description         : String(1000);
        priority            : String(10); // Low, Medium, High, Critical
        status              : String(20); // Open, Assigned, InProgress, Completed, Cancelled
        assignedTechnician  : Association to Technician;
        estimatedHours      : Integer;
        actualHours         : Integer;
        scheduledStart      : DateTime;
        actualStart         : DateTime;
        scheduledEnd        : DateTime;
        actualEnd           : DateTime;
        cost                : Decimal(10,2);
        createdAt           : DateTime;
        createdBy           : String(50);
        modifiedAt          : DateTime;
        modifiedBy          : String(50);
        
        parts               : Composition of many PartUsage on parts.workOrder = $self;
}

// Technicians and their specializations
entity Technician {
    key ID              : UUID;
        employeeId          : String(10);
        firstName           : String(50);
        lastName            : String(50);
        email               : String(100);
        phone               : String(20);
        specializations     : String(200); // Comma-separated specializations
        certifications      : String(500);
        experienceYears     : Integer;
        status              : String(20); // Available, Busy, OnLeave, Unavailable
        currentLocation     : String(100);
        hourlyRate          : Decimal(8,2);
        
        assignedWork        : Composition of many WorkOrder on assignedWork.assignedTechnician = $self;
        maintenanceRecords  : Composition of many MaintenanceRecord on maintenanceRecords.assignedTechnician = $self;
}

// Parts inventory and usage tracking
entity Part {
    key ID              : UUID;
        partNumber          : String(50);
        name                : String(100);
        description         : String(500);
        manufacturer        : String(50);
        category            : String(50);
        unitPrice           : Decimal(10,2);
        stockQuantity       : Integer;
        minimumStock        : Integer;
        location            : String(100);
        status              : String(20); // Available, LowStock, OutOfStock, Discontinued
        
        usage               : Composition of many PartUsage on usage.part = $self;
}

// Track parts used in work orders
entity PartUsage {
    key ID              : UUID;
        workOrder           : Association to WorkOrder;
        part                : Association to Part;
        quantityUsed        : Integer;
        unitCost            : Decimal(10,2);
        totalCost           : Decimal(10,2);
        usageDate           : DateTime;
}

// Flight schedule integration for maintenance planning
entity FlightSchedule {
    key ID              : UUID;
        aircraft            : Association to Aircraft;
        flightNumber        : String(10);
        departure           : String(10); // Airport code
        arrival             : String(10); // Airport code
        scheduledDeparture  : DateTime;
        scheduledArrival    : DateTime;
        actualDeparture     : DateTime;
        actualArrival       : DateTime;
        status              : String(20); // Scheduled, Delayed, InFlight, Completed, Cancelled
        estimatedFlightHours: Decimal(4,2);
        
        // For maintenance impact assessment
        maintenanceImpact   : Boolean; // Does this flight affect maintenance schedule
        notes               : String(500);
}

// Maintenance alerts and notifications
entity MaintenanceAlert {
    key ID              : UUID;
        aircraft            : Association to Aircraft;
        alertType           : String(30); // DueMaintenance, OverdueMaintenance, PredictiveAlert, PartFailure, SafetyConcern
        severity            : String(10); // Low, Medium, High, Critical
        title               : String(100);
        description         : String(1000);
        dueDate             : Date;
        status              : String(20); // Open, Acknowledged, InProgress, Resolved, Dismissed
        assignedTo          : Association to Technician;
        resolvedDate        : DateTime;
        resolution          : String(1000);
        createdAt           : DateTime;
        createdBy           : String(50);
        modifiedAt          : DateTime;
        modifiedBy          : String(50);
}
