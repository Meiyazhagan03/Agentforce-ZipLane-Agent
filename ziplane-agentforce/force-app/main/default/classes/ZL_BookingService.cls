/**
 * Shared lookup/verification and formatting helpers for the ZipLane agent actions.
 *
 * without sharing: the Agentforce agent runs as a dedicated agent user, and access control is the
 * booking-number + email verification enforced in findVerifiedBooking(). Callers must only touch
 * the booking that this method returns.
 */
public without sharing class ZL_BookingService {

    /** "1001", "bk1001", "BK 1001", " bk-1001 " -> "BK-1001". Anything else is returned trimmed + uppercased. */
    public static String normalizeBookingNumber(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String s = raw.trim().toUpperCase();
        String compact = s.replaceAll('[^A-Z0-9]', '');
        Matcher m = Pattern.compile('^(?:BK)?(\\d+)$').matcher(compact);
        if (m.matches()) {
            return 'BK-' + m.group(1);
        }
        return s;
    }

    public static String normalizeEmail(String raw) {
        return String.isBlank(raw) ? null : raw.trim().toLowerCase();
    }

    /**
     * Returns the booking only when it exists AND the rider's account email matches.
     * Returns null in every other case so callers cannot distinguish "missing" from "wrong email".
     */
    public static Ride_Booking__c findVerifiedBooking(String bookingNumber, String email) {
        String bn = normalizeBookingNumber(bookingNumber);
        String em = normalizeEmail(email);
        if (bn == null || em == null) {
            return null;
        }
        List<Ride_Booking__c> rows = [
            SELECT Id, Name, Status__c, Reserved_At__c, Start_Time__c, End_Time__c, Pickup_Zone__c,
                   Drop_Zone__c, Distance_km__c, Fare_INR__c, Payment_Status__c,
                   Rider__c, Rider__r.Email, Scooter__c, Scooter__r.Name, Scooter__r.Model__c,
                   (SELECT Id, Name, Status__c FROM Refund_Requests__r ORDER BY CreatedDate DESC)
            FROM Ride_Booking__c
            WHERE Name = :bn
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return null;
        }
        Ride_Booking__c b = rows[0];
        String riderEmail = normalizeEmail(b.Rider__r == null ? null : b.Rider__r.Email);
        if (riderEmail == null || riderEmail != em) {
            return null;
        }
        return b;
    }

    public static String formatDateTime(Datetime dt) {
        return dt == null ? '' : dt.format('dd MMM yyyy, hh:mm a', 'Asia/Kolkata');
    }

    public static String formatMoney(Decimal amount) {
        Decimal a = (amount == null ? 0 : amount).setScale(2);
        return '₹' + a.toPlainString();
    }
}
