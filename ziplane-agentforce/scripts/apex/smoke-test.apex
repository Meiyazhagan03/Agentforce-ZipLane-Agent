// Smoke test: calls every invocable against the seeded fixtures, logs results, then ROLLS BACK so seed data stays intact.
Savepoint sp = Database.setSavepoint();
Map<String, String> emails = new Map<String, String>{
    'BK-1001' => 'ananya.rao@example.com', 'BK-1002' => 'rahul.menon@example.com',
    'BK-1003' => 'priya.sharma@example.com', 'BK-1004' => 'karthik.iyer@example.com',
    'BK-1005' => 'meera.nair@example.com', 'BK-1006' => 'arjun.das@example.com',
    'BK-1007' => 'sneha.kulkarni@example.com', 'BK-1008' => 'vikram.shetty@example.com',
    'BK-1009' => 'priya.sharma@example.com'
};
List<String> keys = new List<String>(emails.keySet());
keys.sort();

// 1. Booking status for every fixture
for (String bn : keys) {
    ZL_GetBookingStatus.Request q = new ZL_GetBookingStatus.Request();
    q.bookingNumber = bn; q.riderEmail = emails.get(bn);
    ZL_GetBookingStatus.Response r = ZL_GetBookingStatus.getBookingStatus(new List<ZL_GetBookingStatus.Request>{ q })[0];
    System.debug('SMOKE STATUS ' + bn + ' success=' + r.success + ' status=' + r.status + ' scooter=' + r.scooterId
        + ' fare=' + r.fare + ' pay=' + r.paymentStatus + ' start=' + r.startTime + ' end=' + r.endTime);
}
// 2. Wrong email, missing booking, normalization
for (String[] t : new List<String[]>{
    new String[]{ 'BK-1009', 'rahul.menon@example.com' }, new String[]{ 'BK-1001', 'rahul.menon@example.com' },
    new String[]{ 'BK-9999', 'ananya.rao@example.com' }, new String[]{ 'bk 1001', 'ANANYA.RAO@example.com' },
    new String[]{ '1001', 'ananya.rao@example.com' }, new String[]{ 'bk1001', ' ananya.rao@example.com ' } }) {
    ZL_GetBookingStatus.Request q = new ZL_GetBookingStatus.Request();
    q.bookingNumber = t[0]; q.riderEmail = t[1];
    ZL_GetBookingStatus.Response r = ZL_GetBookingStatus.getBookingStatus(new List<ZL_GetBookingStatus.Request>{ q })[0];
    System.debug('SMOKE LOOKUP "' + t[0] + '" / ' + t[1] + ' -> success=' + r.success + ' | ' + r.message);
}
// 3. Refund eligibility for every fixture (+ wrong email)
List<String> refundKeys = new List<String>(keys);
for (String bn : refundKeys) {
    ZL_SubmitRefundRequest.Request q = new ZL_SubmitRefundRequest.Request();
    q.bookingNumber = bn; q.riderEmail = emails.get(bn); q.reason = 'Breakdown During Ride';
    ZL_SubmitRefundRequest.Response r = ZL_SubmitRefundRequest.submit(new List<ZL_SubmitRefundRequest.Request>{ q })[0];
    System.debug('SMOKE REFUND ' + bn + ' eligibility=' + r.eligibility + ' created=' + r.requestCreated
        + ' amount=' + r.amountRequested + ' rr=' + r.requestNumber);
}
ZL_SubmitRefundRequest.Request wq = new ZL_SubmitRefundRequest.Request();
wq.bookingNumber = 'BK-1009'; wq.riderEmail = 'rahul.menon@example.com'; wq.reason = 'Other';
System.debug('SMOKE REFUND BK-1009 wrong email -> ' + ZL_SubmitRefundRequest.submit(new List<ZL_SubmitRefundRequest.Request>{ wq })[0].eligibility);
// 4. Breakdown paths
for (String[] t : new List<String[]>{
    new String[]{ 'BK-1002', 'rahul.menon@example.com' },  // active -> case
    new String[]{ 'BK-1002', 'rahul.menon@example.com' },  // again -> existing case
    new String[]{ 'BK-1003', 'priya.sharma@example.com' }, // already ended -> existing case
    new String[]{ 'BK-1001', 'ananya.rao@example.com' },   // completed -> none
    new String[]{ 'BK-1002', 'priya.sharma@example.com' }  // wrong email
}) {
    ZL_ReportBreakdown.Request q = new ZL_ReportBreakdown.Request();
    q.bookingNumber = t[0]; q.riderEmail = t[1]; q.issueType = 'Battery Dead';
    q.locationDescription = 'Near Indiranagar metro'; q.isRiderSafe = true;
    ZL_ReportBreakdown.Response r = ZL_ReportBreakdown.reportBreakdown(new List<ZL_ReportBreakdown.Request>{ q })[0];
    System.debug('SMOKE BREAKDOWN ' + t[0] + ' success=' + r.success + ' case=' + r.caseNumber + ' priority=' + r.priority
        + ' rideEnded=' + r.rideEnded);
}
ZL_ReportBreakdown.Request uq = new ZL_ReportBreakdown.Request();
uq.bookingNumber = 'BK-1002'; uq.riderEmail = 'rahul.menon@example.com'; uq.issueType = 'Accident';
uq.locationDescription = 'x'; uq.isRiderSafe = false;
System.debug('SMOKE BREAKDOWN unsafe msg -> ' + ZL_ReportBreakdown.reportBreakdown(new List<ZL_ReportBreakdown.Request>{ uq })[0].message);
// 5. Policies
for (String topic : new List<String>{ 'refund', 'how much does it cost', 'cancel my reservation', 'scooter broke down', 'otp', 'scratch', 'pizza' }) {
    ZL_GetPolicyInfo.Request q = new ZL_GetPolicyInfo.Request();
    q.policyTopic = topic;
    ZL_GetPolicyInfo.Response r = ZL_GetPolicyInfo.getPolicy(new List<ZL_GetPolicyInfo.Request>{ q })[0];
    System.debug('SMOKE POLICY "' + topic + '" -> success=' + r.success + ' title=' + r.policyTitle);
}
Database.rollback(sp);
System.debug('SMOKE ROLLED BACK. Bookings=' + [SELECT COUNT() FROM Ride_Booking__c] + ' RRs=' + [SELECT COUNT() FROM Refund_Request__c]
    + ' agentCases=' + [SELECT COUNT() FROM Case WHERE Created_By_Agent__c = true]
    + ' BK-1002=' + [SELECT Status__c FROM Ride_Booking__c WHERE Name = 'BK-1002'].Status__c);
