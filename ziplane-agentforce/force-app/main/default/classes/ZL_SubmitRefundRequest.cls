/**
 * Agent action: submit a refund request for human review. without sharing: see ZL_BookingService; the only DML
 * is creating one Refund_Request__c (always 'Pending Review') for the verified booking. It never approves anything.
 */
public without sharing class ZL_SubmitRefundRequest {

    @TestVisible private static Boolean forceError = false;

    public class Request {
        @InvocableVariable(label='Booking Number' required=true description='Booking number of the ride to refund, e.g. BK-1003.')
        public String bookingNumber;
        @InvocableVariable(label='Rider Email' required=true description='Email address on the rider\'s ZipLane account.')
        public String riderEmail;
        @InvocableVariable(label='Reason' required=true
            description='One of: Breakdown During Ride, Overcharged, Cancellation Fee, Other.')
        public String reason;
        @InvocableVariable(label='Details' required=false description='The rider\'s explanation in their own words.')
        public String details;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the request was processed against a verified booking, even if it was not eligible.')
        public Boolean success;
        @InvocableVariable(label='Request Created' description='True only if a new refund request was created for human review.')
        public Boolean requestCreated;
        @InvocableVariable(label='Request Number' description='Refund request number, e.g. RR-0001 (new or existing).')
        public String requestNumber;
        @InvocableVariable(label='Eligibility' description='NOT_VERIFIED, RIDE_NOT_FINISHED, ALREADY_REFUNDED, DUPLICATE, NOT_ELIGIBLE, ELIGIBLE_PENDING_REVIEW or MANUAL_REVIEW.')
        public String eligibility;
        @InvocableVariable(label='Amount Requested' description='Amount requested in rupees, e.g. ₹32.50. Empty if no request was created.')
        public String amountRequested;
        @InvocableVariable(label='Message' description='Short message to relay to the rider. Never promise or imply approval.')
        public String message;
    }

    @InvocableMethod(label='Submit Refund Request'
        description='Submits a refund request for review by the ZipLane support team. This action NEVER approves a refund. It only creates a request with status Pending Review, or explains why the ride is not eligible under policy. Requires booking number, account email and reason.')
    public static List<Response> submit(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            out.add(handle(req));
        }
        return out;
    }

    private static String mapReason(String raw) {
        if (String.isNotBlank(raw)) {
            for (String t : ZL_Constants.REFUND_REASONS) {
                if (t.equalsIgnoreCase(raw.trim())) {
                    return t;
                }
            }
        }
        return 'Other';
    }

    private static Response result(String code, String message) {
        Response r = new Response();
        r.success = code != ZL_Constants.ELIG_NOT_VERIFIED;
        r.requestCreated = false;
        r.eligibility = code;
        r.message = message;
        return r;
    }

    private static Response handle(Request req) {
        try {
            if (forceError) {
                throw new IllegalArgumentException('forced error (tests only)');
            }
            if (req == null || String.isBlank(req.bookingNumber) || String.isBlank(req.riderEmail)
                || String.isBlank(req.reason)) {
                Response r = result(ZL_Constants.ELIG_NOT_VERIFIED,
                    'To submit a refund request I need the booking number, the email on the account, and the reason.');
                r.success = false;
                return r;
            }
            Ride_Booking__c b = ZL_BookingService.findVerifiedBooking(req.bookingNumber, req.riderEmail);
            if (b == null) {
                Response r = result(ZL_Constants.ELIG_NOT_VERIFIED, ZL_Constants.GENERIC_NOT_FOUND);
                r.success = false;
                return r;
            }
            String status = b.Status__c;
            if (status == ZL_Constants.BOOKING_RESERVED || status == ZL_Constants.BOOKING_ACTIVE) {
                return result(ZL_Constants.ELIG_RIDE_NOT_FINISHED, 'Booking ' + b.Name + ' hasn\'t ended yet, so a refund can\'t be requested. '
                    + 'If the scooter failed during the ride, please report the breakdown first.');
            }
            if (b.Payment_Status__c == ZL_Constants.PAY_REFUNDED || b.Payment_Status__c == ZL_Constants.PAY_PARTIALLY_REFUNDED) {
                return result(ZL_Constants.ELIG_ALREADY_REFUNDED, 'Booking ' + b.Name + ' has already been refunded (' + b.Payment_Status__c + ').');
            }
            for (Refund_Request__c rr : b.Refund_Requests__r) {
                if (rr.Status__c == ZL_Constants.RR_PENDING_REVIEW || rr.Status__c == ZL_Constants.RR_APPROVED) {
                    Response r = result(ZL_Constants.ELIG_DUPLICATE, 'A refund request for ' + b.Name + ' already exists: '
                        + rr.Name + ' (status: ' + rr.Status__c + '). No new request was created.');
                    r.requestNumber = rr.Name;
                    return r;
                }
            }
            if (status == ZL_Constants.BOOKING_CANCELLED) {
                return result(ZL_Constants.ELIG_NOT_ELIGIBLE, 'The cancellation fee for ' + b.Name + ' is non-refundable under ZipLane policy. '
                    + 'If the scooter was missing or faulty at pickup, human support can review the fee.');
            }
            if (b.End_Time__c != null && b.End_Time__c < System.now().addDays(-ZL_Constants.REFUND_WINDOW_DAYS)) {
                return result(ZL_Constants.ELIG_NOT_ELIGIBLE, 'Booking ' + b.Name + ' ended more than ' + ZL_Constants.REFUND_WINDOW_DAYS
                    + ' days ago, which is outside the refund window, so it isn\'t eligible.');
            }

            String code;
            if (status == ZL_Constants.BOOKING_ENDED_BREAKDOWN) {
                code = ZL_Constants.ELIG_ELIGIBLE_PENDING_REVIEW;
            } else if (status == ZL_Constants.BOOKING_COMPLETED) {
                code = ZL_Constants.ELIG_MANUAL_REVIEW;
            } else {
                return result(ZL_Constants.ELIG_NOT_ELIGIBLE, 'Booking ' + b.Name + ' isn\'t eligible for a refund request.');
            }

            Refund_Request__c rr = new Refund_Request__c(
                Ride_Booking__c = b.Id,
                Rider__c = b.Rider__c,
                Reason__c = mapReason(req.reason),
                Details__c = req.details == null ? null : req.details.left(2000),
                Amount_Requested_INR__c = b.Fare_INR__c,
                Status__c = ZL_Constants.RR_PENDING_REVIEW,
                Eligibility__c = code,
                Submitted_By_Agent__c = true
            );
            insert rr;
            rr = [SELECT Name FROM Refund_Request__c WHERE Id = :rr.Id];

            Response r = new Response();
            r.success = true;
            r.requestCreated = true;
            r.requestNumber = rr.Name;
            r.eligibility = code;
            r.amountRequested = ZL_BookingService.formatMoney(b.Fare_INR__c);
            String gist = code == ZL_Constants.ELIG_ELIGIBLE_PENDING_REVIEW
                ? 'This ride meets the breakdown refund criteria.'
                : 'It has been submitted for case-by-case review.';
            r.message = 'I\'ve submitted refund request ' + rr.Name + ' for ' + r.amountRequested + ' on ' + b.Name + '. '
                + gist + ' ' + ZL_Constants.REFUND_DISCLAIMER;
            return r;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ZL_SubmitRefundRequest: ' + e.getMessage());
            Response r = result(ZL_Constants.ELIG_NOT_VERIFIED, ZL_Constants.GENERIC_ERROR);
            r.success = false;
            return r;
        }
    }
}