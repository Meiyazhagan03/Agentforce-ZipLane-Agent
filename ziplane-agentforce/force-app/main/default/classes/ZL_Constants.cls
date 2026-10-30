/**
 * Shared constants for the ZipLane agent actions.
 * To rename the (fictional) brand, change BRAND_NAME and the policy text in customMetadata.
 */
public class ZL_Constants {
    public static final String BRAND_NAME = 'ZipLane';
    public static final Integer REFUND_WINDOW_DAYS = 7;

    // Ride_Booking__c.Status__c
    public static final String BOOKING_RESERVED = 'Reserved';
    public static final String BOOKING_ACTIVE = 'Active';
    public static final String BOOKING_COMPLETED = 'Completed';
    public static final String BOOKING_CANCELLED = 'Cancelled';
    public static final String BOOKING_ENDED_BREAKDOWN = 'Ended - Breakdown';

    // Ride_Booking__c.Payment_Status__c
    public static final String PAY_PAID = 'Paid';
    public static final String PAY_REFUNDED = 'Refunded';
    public static final String PAY_PARTIALLY_REFUNDED = 'Partially Refunded';

    // Refund_Request__c.Status__c
    public static final String RR_PENDING_REVIEW = 'Pending Review';
    public static final String RR_APPROVED = 'Approved';

    // Scooter__c.Status__c
    public static final String SCOOTER_MAINTENANCE = 'Under Maintenance';

    // Eligibility codes
    public static final String ELIG_NOT_VERIFIED = 'NOT_VERIFIED';
    public static final String ELIG_RIDE_NOT_FINISHED = 'RIDE_NOT_FINISHED';
    public static final String ELIG_ALREADY_REFUNDED = 'ALREADY_REFUNDED';
    public static final String ELIG_DUPLICATE = 'DUPLICATE';
    public static final String ELIG_NOT_ELIGIBLE = 'NOT_ELIGIBLE';
    public static final String ELIG_ELIGIBLE_PENDING_REVIEW = 'ELIGIBLE_PENDING_REVIEW';
    public static final String ELIG_MANUAL_REVIEW = 'MANUAL_REVIEW';

    public static final String CASE_ORIGIN = 'Web';

    public static final String GENERIC_NOT_FOUND =
        'I couldn\'t find a booking matching that booking number and email. Please double-check both.';
    public static final String GENERIC_ERROR =
        'Sorry, something went wrong while processing that request. Please try again or contact human support.';
    public static final String EMERGENCY_PREFIX = 'If anyone is hurt or in danger, please call 112 immediately.';
    public static final String REFUND_DISCLAIMER =
        'This is a request, not an approval. The ZipLane support team reviews refund requests within 2 business days.';

    public static final List<String> ISSUE_TYPES = new List<String>{
        'Battery Dead', 'Flat Tyre', 'Brake Issue', 'App Lock Issue', 'Accident', 'Other'
    };
    public static final List<String> REFUND_REASONS = new List<String>{
        'Breakdown During Ride', 'Overcharged', 'Cancellation Fee', 'Other'
    };
}
