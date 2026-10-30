/**
 * Agent action: look up a ride booking. without sharing: see ZL_BookingService; access control is the
 * booking-number + email verification, and this action is read-only.
 */
public without sharing class ZL_GetBookingStatus {

    @TestVisible private static Boolean forceError = false;

    public class Request {
        @InvocableVariable(label='Booking Number' required=true
            description='Booking number the rider gives, e.g. BK-1001. Formats like 1001 or bk 1001 are accepted.')
        public String bookingNumber;

        @InvocableVariable(label='Rider Email' required=true
            description='Email address on the rider\'s ZipLane account. Must match the booking, otherwise nothing is returned.')
        public String riderEmail;
    }

    public class Response {
        @InvocableVariable(label='Success' description='False when the booking was not found, not verified, or an error occurred.')
        public Boolean success;
        @InvocableVariable(label='Booking Number' description='Normalized booking number, e.g. BK-1001.')
        public String bookingNumber;
        @InvocableVariable(label='Status' description='Reserved, Active, Completed, Cancelled or Ended - Breakdown.')
        public String status;
        @InvocableVariable(label='Scooter ID' description='ID of the scooter used, e.g. ZL-0001.')
        public String scooterId;
        @InvocableVariable(label='Scooter Model' description='Scooter model, e.g. ZL Swift.')
        public String scooterModel;
        @InvocableVariable(label='Pickup Zone' description='Zone where the ride started.')
        public String pickupZone;
        @InvocableVariable(label='Drop Zone' description='Zone where the ride ended. Empty if the ride has not ended.')
        public String dropZone;
        @InvocableVariable(label='Start Time' description='Ride start time in India Standard Time. Empty if not started.')
        public String startTime;
        @InvocableVariable(label='End Time' description='Ride end time in India Standard Time. Empty if not ended.')
        public String endTime;
        @InvocableVariable(label='Fare' description='Fare in rupees, e.g. ₹55.00.')
        public String fare;
        @InvocableVariable(label='Payment Status' description='Not Charged, Pending, Paid, Refunded or Partially Refunded.')
        public String paymentStatus;
        @InvocableVariable(label='Message' description='Short sentence to relay to the rider.')
        public String message;
    }

    @InvocableMethod(label='Get Ride Booking Status'
        description='Looks up a ZipLane ride booking and returns its status, scooter, times, zones, fare and payment status. Requires BOTH the booking number and the email address on the rider\'s account. Only returns details if both match.')
    public static List<Response> getBookingStatus(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            out.add(handle(req));
        }
        return out;
    }

    private static Response handle(Request req) {
        Response r = new Response();
        r.success = false;
        try {
            if (forceError) {
                throw new IllegalArgumentException('forced error (tests only)');
            }
            if (req == null || String.isBlank(req.bookingNumber) || String.isBlank(req.riderEmail)) {
                r.message = 'To look up a booking I need both the booking number and the email address on the account.';
                return r;
            }
            Ride_Booking__c b = ZL_BookingService.findVerifiedBooking(req.bookingNumber, req.riderEmail);
            if (b == null) {
                r.message = ZL_Constants.GENERIC_NOT_FOUND;
                return r;
            }
            r.success = true;
            r.bookingNumber = b.Name;
            r.status = b.Status__c;
            r.scooterId = b.Scooter__r == null ? null : b.Scooter__r.Name;
            r.scooterModel = b.Scooter__r == null ? null : b.Scooter__r.Model__c;
            r.pickupZone = b.Pickup_Zone__c;
            r.dropZone = b.Drop_Zone__c;
            r.startTime = ZL_BookingService.formatDateTime(b.Start_Time__c);
            r.endTime = ZL_BookingService.formatDateTime(b.End_Time__c);
            r.fare = ZL_BookingService.formatMoney(b.Fare_INR__c);
            r.paymentStatus = b.Payment_Status__c;
            r.message = 'Booking ' + b.Name + ' is ' + b.Status__c + '. Fare: ' + r.fare
                + ', payment status: ' + b.Payment_Status__c + '.';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ZL_GetBookingStatus: ' + e.getMessage());
            r = new Response();
            r.success = false;
            r.message = ZL_Constants.GENERIC_ERROR;
        }
        return r;
    }
}