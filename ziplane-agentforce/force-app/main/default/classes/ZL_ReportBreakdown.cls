/**
 * Agent action: report a breakdown on an Active ride. without sharing: see ZL_BookingService; all DML is
 * scoped to the single booking (and its scooter/rider) returned by the booking-number + email verification.
 */
public without sharing class ZL_ReportBreakdown {

    @TestVisible private static Boolean forceError = false;

    public class Request {
        @InvocableVariable(label='Booking Number' required=true description='Booking number of the ride, e.g. BK-1002.')
        public String bookingNumber;
        @InvocableVariable(label='Rider Email' required=true description='Email address on the rider\'s ZipLane account.')
        public String riderEmail;
        @InvocableVariable(label='Issue Type' required=true
            description='One of: Battery Dead, Flat Tyre, Brake Issue, App Lock Issue, Accident, Other.')
        public String issueType;
        @InvocableVariable(label='Location Description' required=true
            description='Where the rider and scooter are right now, in the rider\'s words.')
        public String locationDescription;
        @InvocableVariable(label='Is Rider Safe' required=true
            description='False if the rider is injured or in danger, true otherwise. Ask the rider if unknown.')
        public Boolean isRiderSafe;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when a case exists for this breakdown (new or already existing).')
        public Boolean success;
        @InvocableVariable(label='Case Number' description='Support case number, e.g. 00001026.')
        public String caseNumber;
        @InvocableVariable(label='Priority' description='High or Medium.')
        public String priority;
        @InvocableVariable(label='Ride Ended' description='True when the ride was ended and billing stopped by this report.')
        public Boolean rideEnded;
        @InvocableVariable(label='Message' description='Short message to relay to the rider.')
        public String message;
    }

    @InvocableMethod(label='Report Scooter Breakdown'
        description='Reports a breakdown on a ZipLane rider\'s ACTIVE ride. Creates a support case, stops billing, ends the ride and flags the scooter for maintenance. Requires booking number, account email, issue type, rider location, and whether the rider is safe.')
    public static List<Response> reportBreakdown(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            out.add(handle(req));
        }
        return out;
    }

    private static String mapIssueType(String raw) {
        if (String.isNotBlank(raw)) {
            for (String t : ZL_Constants.ISSUE_TYPES) {
                if (t.equalsIgnoreCase(raw.trim())) {
                    return t;
                }
            }
        }
        return 'Other';
    }

    private static Response handle(Request req) {
        Response r = new Response();
        r.success = false;
        r.rideEnded = false;
        Savepoint sp = Database.setSavepoint();
        try {
            if (forceError) {
                throw new IllegalArgumentException('forced error (tests only)');
            }
            if (req == null || String.isBlank(req.bookingNumber) || String.isBlank(req.riderEmail)
                || String.isBlank(req.locationDescription) || req.isRiderSafe == null) {
                r.message = 'To report a breakdown I need the booking number, the email on the account, '
                    + 'where you are right now, and whether you are safe.';
                return r;
            }
            Ride_Booking__c b = ZL_BookingService.findVerifiedBooking(req.bookingNumber, req.riderEmail);
            if (b == null) {
                r.message = ZL_Constants.GENERIC_NOT_FOUND;
                return r;
            }
            String issue = mapIssueType(req.issueType);
            Boolean urgent = req.isRiderSafe == false || issue == 'Accident';
            String prefix = urgent ? ZL_Constants.EMERGENCY_PREFIX + ' ' : '';
            String priority = urgent ? 'High' : 'Medium';

            if (b.Status__c == ZL_Constants.BOOKING_ACTIVE) {
                Case c = new Case(
                    Subject = 'Breakdown – ' + b.Name + ' – ' + issue,
                    Description = 'Breakdown reported via ZipLane virtual assistant.\nBooking: ' + b.Name
                        + '\nIssue: ' + issue + '\nRider location: ' + req.locationDescription
                        + '\nRider safe: ' + req.isRiderSafe,
                    Origin = ZL_Constants.CASE_ORIGIN,
                    Priority = priority,
                    Created_By_Agent__c = true,
                    Ride_Booking__c = b.Id,
                    Scooter__c = b.Scooter__c,
                    ContactId = b.Rider__c,
                    Issue_Type__c = issue,
                    Rider_Location__c = req.locationDescription.left(255),
                    Rider_Safe__c = req.isRiderSafe
                );
                insert c;

                update new Ride_Booking__c(
                    Id = b.Id,
                    Status__c = ZL_Constants.BOOKING_ENDED_BREAKDOWN,
                    End_Time__c = System.now(),
                    Payment_Status__c = ZL_Constants.PAY_PAID
                );
                if (b.Scooter__c != null) {
                    update new Scooter__c(Id = b.Scooter__c, Status__c = ZL_Constants.SCOOTER_MAINTENANCE);
                }

                r.success = true;
                r.rideEnded = true;
                r.priority = priority;
                r.caseNumber = [SELECT CaseNumber FROM Case WHERE Id = :c.Id].CaseNumber;
                r.message = prefix + 'I\'ve reported the breakdown (case ' + r.caseNumber + '). Billing has stopped and your ride '
                    + 'has ended with a fare of ' + ZL_BookingService.formatMoney(b.Fare_INR__c) + '. A field team member will '
                    + 'collect the scooter, and you can unlock a different scooter nearby to continue your trip.';
                return r;
            }

            if (b.Status__c == ZL_Constants.BOOKING_ENDED_BREAKDOWN) {
                List<Case> existing = [
                    SELECT CaseNumber, Priority FROM Case
                    WHERE Ride_Booking__c = :b.Id AND Created_By_Agent__c = true
                    ORDER BY CreatedDate ASC LIMIT 1
                ];
                if (!existing.isEmpty()) {
                    r.success = true;
                    r.caseNumber = existing[0].CaseNumber;
                    r.priority = existing[0].Priority;
                    r.message = prefix + 'A breakdown was already reported for ' + b.Name + ' (case ' + r.caseNumber
                        + '). Billing has already stopped, so no new case was created.';
                    return r;
                }
            }

            r.message = prefix + 'Breakdown reporting is only for rides that are currently active, and ' + b.Name
                + ' is ' + b.Status__c + '. If you were charged for a past ride that had a problem, I can submit a refund request instead.';
            return r;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'ZL_ReportBreakdown: ' + e.getMessage());
            r = new Response();
            r.success = false;
            r.rideEnded = false;
            r.message = ZL_Constants.GENERIC_ERROR;
            return r;
        }
    }
}