@IsTest
private class ZL_ActionsTest {
    private static final String NOT_FOUND = ZL_Constants.GENERIC_NOT_FOUND;

    @TestSetup
    static void setup() {
        System.assert(ZL_DemoDataSeeder.seed());
    }

    private static ZL_GetBookingStatus.Response status(String bn, String email) {
        ZL_GetBookingStatus.Request r = new ZL_GetBookingStatus.Request();
        r.bookingNumber = bn;
        r.riderEmail = email;
        return ZL_GetBookingStatus.getBookingStatus(new List<ZL_GetBookingStatus.Request>{ r })[0];
    }

    private static ZL_ReportBreakdown.Response report(String bn, String email, String issue, Boolean safe) {
        ZL_ReportBreakdown.Request r = new ZL_ReportBreakdown.Request();
        r.bookingNumber = bn;
        r.riderEmail = email;
        r.issueType = issue;
        r.locationDescription = 'Near the Koramangala metro station';
        r.isRiderSafe = safe;
        return ZL_ReportBreakdown.reportBreakdown(new List<ZL_ReportBreakdown.Request>{ r })[0];
    }

    private static ZL_SubmitRefundRequest.Response refund(String bn, String email) {
        ZL_SubmitRefundRequest.Request r = new ZL_SubmitRefundRequest.Request();
        r.bookingNumber = bn;
        r.riderEmail = email;
        r.reason = 'breakdown during ride';
        r.details = 'It stopped.';
        return ZL_SubmitRefundRequest.submit(new List<ZL_SubmitRefundRequest.Request>{ r })[0];
    }

    private static ZL_GetPolicyInfo.Response policy(String topic) {
        ZL_GetPolicyInfo.Request r = new ZL_GetPolicyInfo.Request();
        r.policyTopic = topic;
        return ZL_GetPolicyInfo.getPolicy(new List<ZL_GetPolicyInfo.Request>{ r })[0];
    }

    @IsTest
    static void normalization() {
        System.assertEquals('BK-1001', ZL_BookingService.normalizeBookingNumber('1001'));
        System.assertEquals('BK-1001', ZL_BookingService.normalizeBookingNumber('bk1001'));
        System.assertEquals('BK-1001', ZL_BookingService.normalizeBookingNumber('BK 1001'));
        System.assertEquals('BK-1001', ZL_BookingService.normalizeBookingNumber('  bk-1001 '));
        System.assertEquals('HELLO', ZL_BookingService.normalizeBookingNumber(' hello '));
        System.assertEquals(null, ZL_BookingService.normalizeBookingNumber(' '));
        System.assertEquals('a@b.com', ZL_BookingService.normalizeEmail('  A@B.com '));
        System.assertEquals(null, ZL_BookingService.normalizeEmail(null));
        System.assertEquals('₹55.00', ZL_BookingService.formatMoney(55));
        System.assertEquals('₹0.00', ZL_BookingService.formatMoney(null));
        System.assertEquals('', ZL_BookingService.formatDateTime(null));
        System.assertNotEquals('', ZL_BookingService.formatDateTime(System.now()));
    }

    @IsTest
    static void bookingStatusVerified() {
        ZL_GetBookingStatus.Response r = status('bk 1001', '  ANANYA.RAO@example.com ');
        System.assert(r.success);
        System.assertEquals('BK-1001', r.bookingNumber);
        System.assertEquals('Completed', r.status);
        System.assertEquals('ZL-0001', r.scooterId);
        System.assertEquals('₹55.00', r.fare);
        System.assertEquals('Paid', r.paymentStatus);
        System.assertNotEquals('', r.endTime);
    }

    @IsTest
    static void antiEnumeration() {
        ZL_GetBookingStatus.Response wrongEmail = status('BK-1001', 'rahul.menon@example.com');
        ZL_GetBookingStatus.Response missing = status('BK-9999', 'ananya.rao@example.com');
        ZL_GetBookingStatus.Response identity = status('BK-1009', 'rahul.menon@example.com');
        System.assert(!wrongEmail.success);
        System.assertEquals(NOT_FOUND, wrongEmail.message);
        System.assertEquals(missing.message, wrongEmail.message);
        System.assertEquals(missing.message, identity.message);
        System.assertEquals(null, wrongEmail.status);
        System.assertEquals(NOT_FOUND, report('BK-1002', 'x@example.com', 'Other', true).message);
        System.assertEquals(NOT_FOUND, refund('BK-1001', 'x@example.com').message);
        System.assertEquals(NOT_FOUND, refund('BK-9999', 'ananya.rao@example.com').message);
    }

    @IsTest
    static void missingInputs() {
        System.assert(!status('', 'a@example.com').success);
        System.assert(!status(null, null).success);
        System.assert(!ZL_GetBookingStatus.getBookingStatus(new List<ZL_GetBookingStatus.Request>{ null })[0].success);
        ZL_ReportBreakdown.Request r = new ZL_ReportBreakdown.Request();
        r.bookingNumber = 'BK-1002';
        r.riderEmail = 'rahul.menon@example.com';
        System.assert(!ZL_ReportBreakdown.reportBreakdown(new List<ZL_ReportBreakdown.Request>{ r })[0].success);
        System.assert(!ZL_ReportBreakdown.reportBreakdown(new List<ZL_ReportBreakdown.Request>{ null })[0].success);
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE Ride_Booking__r.Name = 'BK-1002']);
        System.assert(!ZL_SubmitRefundRequest.submit(new List<ZL_SubmitRefundRequest.Request>{ null })[0].success);
        System.assert(!policy(' ').success);
        System.assert(!ZL_GetPolicyInfo.getPolicy(new List<ZL_GetPolicyInfo.Request>{ null })[0].success);
    }

    @IsTest
    static void breakdownActive() {
        ZL_ReportBreakdown.Response r = report('BK-1002', 'rahul.menon@example.com', 'battery dead', true);
        System.assert(r.success);
        System.assert(r.rideEnded);
        System.assertEquals('Medium', r.priority);
        System.assert(!r.message.startsWith(ZL_Constants.EMERGENCY_PREFIX));
        Case c = [SELECT Subject, Origin, Priority, Created_By_Agent__c, Issue_Type__c, ContactId, Scooter__c
                  FROM Case WHERE Ride_Booking__r.Name = 'BK-1002'];
        System.assertEquals('Breakdown – BK-1002 – Battery Dead', c.Subject);
        System.assertEquals('Web', c.Origin);
        System.assert(c.Created_By_Agent__c);
        Ride_Booking__c b = [SELECT Status__c, End_Time__c, Payment_Status__c, Fare_INR__c, Scooter__r.Status__c
                             FROM Ride_Booking__c WHERE Name = 'BK-1002'];
        System.assertEquals('Ended - Breakdown', b.Status__c);
        System.assertNotEquals(null, b.End_Time__c);
        System.assertEquals('Paid', b.Payment_Status__c);
        System.assertEquals(72.50, b.Fare_INR__c);
        System.assertEquals('Under Maintenance', b.Scooter__r.Status__c);

        // Second report must not duplicate
        ZL_ReportBreakdown.Response again = report('BK-1002', 'rahul.menon@example.com', 'Battery Dead', true);
        System.assert(again.success);
        System.assert(!again.rideEnded);
        System.assertEquals(r.caseNumber, again.caseNumber);
        System.assertEquals(1, [SELECT COUNT() FROM Case WHERE Ride_Booking__r.Name = 'BK-1002']);
    }

    @IsTest
    static void breakdownUnsafeAndAccident() {
        ZL_ReportBreakdown.Response r = report('BK-1002', 'rahul.menon@example.com', 'something weird', false);
        System.assertEquals('High', r.priority);
        System.assert(r.message.startsWith(ZL_Constants.EMERGENCY_PREFIX));
        System.assertEquals('Other', [SELECT Issue_Type__c FROM Case WHERE Ride_Booking__r.Name = 'BK-1002'].Issue_Type__c);
    }

    @IsTest
    static void breakdownAccidentSafeStillHigh() {
        ZL_ReportBreakdown.Response r = report('BK-1002', 'rahul.menon@example.com', 'Accident', true);
        System.assertEquals('High', r.priority);
        System.assert(r.message.startsWith(ZL_Constants.EMERGENCY_PREFIX));
    }

    @IsTest
    static void breakdownAlreadyEndedAndNonActive() {
        ZL_ReportBreakdown.Response ended = report('BK-1003', 'priya.sharma@example.com', 'Battery Dead', true);
        System.assert(ended.success);
        System.assertNotEquals(null, ended.caseNumber);
        System.assertEquals(1, [SELECT COUNT() FROM Case WHERE Ride_Booking__r.Name = 'BK-1003']);

        ZL_ReportBreakdown.Response completed = report('BK-1001', 'ananya.rao@example.com', 'Other', true);
        System.assert(!completed.success);
        System.assertEquals(null, completed.caseNumber);
        System.assert(completed.message.contains('active'));
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE Ride_Booking__r.Name = 'BK-1001']);

        ZL_ReportBreakdown.Response unsafeCompleted = report('BK-1001', 'ananya.rao@example.com', 'Accident', false);
        System.assert(unsafeCompleted.message.startsWith(ZL_Constants.EMERGENCY_PREFIX));
    }

    @IsTest
    static void refundEligibilityTable() {
        System.assertEquals('MANUAL_REVIEW', refund('BK-1001', 'ananya.rao@example.com').eligibility);
        System.assertEquals('RIDE_NOT_FINISHED', refund('BK-1002', 'rahul.menon@example.com').eligibility);
        System.assertEquals('ELIGIBLE_PENDING_REVIEW', refund('BK-1003', 'priya.sharma@example.com').eligibility);
        System.assertEquals('NOT_ELIGIBLE', refund('BK-1004', 'karthik.iyer@example.com').eligibility);
        System.assertEquals('NOT_ELIGIBLE', refund('BK-1005', 'meera.nair@example.com').eligibility);
        System.assertEquals('DUPLICATE', refund('BK-1006', 'arjun.das@example.com').eligibility);
        System.assertEquals('ALREADY_REFUNDED', refund('BK-1007', 'sneha.kulkarni@example.com').eligibility);
        System.assertEquals('RIDE_NOT_FINISHED', refund('BK-1008', 'vikram.shetty@example.com').eligibility);
        System.assertEquals('NOT_VERIFIED', refund('BK-1009', 'rahul.menon@example.com').eligibility);
    }

    @IsTest
    static void refundCreation() {
        ZL_SubmitRefundRequest.Response r = refund('1003', 'priya.sharma@example.com');
        System.assert(r.success);
        System.assert(r.requestCreated);
        System.assertEquals('₹32.50', r.amountRequested);
        System.assert(r.message.contains(ZL_Constants.REFUND_DISCLAIMER));
        Refund_Request__c rr = [SELECT Status__c, Amount_Requested_INR__c, Submitted_By_Agent__c, Eligibility__c, Reason__c, Rider__c
                                FROM Refund_Request__c WHERE Ride_Booking__r.Name = 'BK-1003'];
        System.assertEquals('Pending Review', rr.Status__c);
        System.assertEquals(32.50, rr.Amount_Requested_INR__c);
        System.assert(rr.Submitted_By_Agent__c);
        System.assertEquals('ELIGIBLE_PENDING_REVIEW', rr.Eligibility__c);
        System.assertEquals('Breakdown During Ride', rr.Reason__c);

        ZL_SubmitRefundRequest.Response dup = refund('BK-1003', 'priya.sharma@example.com');
        System.assertEquals('DUPLICATE', dup.eligibility);
        System.assert(!dup.requestCreated);
        System.assertNotEquals(null, dup.requestNumber);

        ZL_SubmitRefundRequest.Response manual = refund('BK-1001', 'ananya.rao@example.com');
        System.assert(manual.requestCreated);
        System.assert(manual.message.contains(ZL_Constants.REFUND_DISCLAIMER));
        System.assertEquals(3, [SELECT COUNT() FROM Refund_Request__c]);
    }

    @IsTest
    static void refundRejectedRequestDoesNotBlock() {
        Refund_Request__c existing = [SELECT Id FROM Refund_Request__c WHERE Ride_Booking__r.Name = 'BK-1006'];
        existing.Status__c = 'Rejected';
        update existing;
        ZL_SubmitRefundRequest.Response r = refund('BK-1006', 'arjun.das@example.com');
        System.assertEquals('ELIGIBLE_PENDING_REVIEW', r.eligibility);
        System.assert(r.requestCreated);
    }

    @IsTest
    static void refundBlankReasonAndUnknownReason() {
        ZL_SubmitRefundRequest.Request r = new ZL_SubmitRefundRequest.Request();
        r.bookingNumber = 'BK-1001';
        r.riderEmail = 'ananya.rao@example.com';
        System.assert(!ZL_SubmitRefundRequest.submit(new List<ZL_SubmitRefundRequest.Request>{ r })[0].success);
        r.reason = 'free scooters pls';
        ZL_SubmitRefundRequest.Response out = ZL_SubmitRefundRequest.submit(new List<ZL_SubmitRefundRequest.Request>{ r })[0];
        System.assert(out.requestCreated);
        System.assertEquals('Other', [SELECT Reason__c FROM Refund_Request__c WHERE Ride_Booking__r.Name = 'BK-1001'].Reason__c);
    }

    @IsTest
    static void policyMatching() {
        System.assertEquals('Refund Policy', policy('I want my money back').policyTitle);
        System.assertEquals('Pricing', policy('how much does it cost').policyTitle);
        System.assertEquals('Cancellation Policy', policy('Cancel').policyTitle);
        System.assertEquals('Breakdown & Safety', policy('my scooter broke down').policyTitle);
        System.assertEquals('Account & Privacy', policy('what about my otp').policyTitle);
        System.assertEquals('Damage & Parking Fees', policy('scratch fine').policyTitle);
        ZL_GetPolicyInfo.Response none = policy('weather in paris');
        System.assert(!none.success);
        System.assert(none.availableTopics.contains('Refund Policy'));
    }

    @IsTest
    static void seederCountsAndReset() {
        System.assertEquals(12, [SELECT COUNT() FROM Contact WHERE Email LIKE '%@example.com']);
        System.assertEquals(20, [SELECT COUNT() FROM Scooter__c]);
        System.assertEquals(30, [SELECT COUNT() FROM Ride_Booking__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Refund_Request__c]);
        System.assertEquals(2, [SELECT COUNT() FROM Case]);
        System.assert(!ZL_DemoDataSeeder.seed());
        ZL_DemoDataSeeder.reset();
        System.assertEquals(30, [SELECT COUNT() FROM Ride_Booking__c]);
        System.assertEquals(2, [SELECT COUNT() FROM Case]);
        System.assertEquals(12, [SELECT COUNT() FROM Contact WHERE Email LIKE '%@example.com']);
    }

    @IsTest
    static void errorsNeverThrowToTheAgent() {
        ZL_GetBookingStatus.forceError = true;
        ZL_ReportBreakdown.forceError = true;
        ZL_SubmitRefundRequest.forceError = true;
        ZL_GetPolicyInfo.forceError = true;
        System.assertEquals(ZL_Constants.GENERIC_ERROR, status('BK-1001', 'ananya.rao@example.com').message);
        System.assertEquals(ZL_Constants.GENERIC_ERROR, report('BK-1002', 'rahul.menon@example.com', 'Other', true).message);
        System.assertEquals(ZL_Constants.GENERIC_ERROR, refund('BK-1001', 'ananya.rao@example.com').message);
        System.assertEquals(ZL_Constants.GENERIC_ERROR, policy('refund').message);
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE Ride_Booking__r.Name = 'BK-1002']);
    }
}
