/**
 * Seeds / resets the fictional ZipLane demo data. All times are relative to System.now() and all values are
 * deterministic (index-based), so every reset produces identical data.
 *
 * without sharing: admin/demo utility that must see and delete all ZipLane demo rows regardless of the running user.
 */
public without sharing class ZL_DemoDataSeeder {
    public static final String ACCOUNT_NAME = 'ZipLane Riders (Demo)';

    private static final List<String> RIDERS = new List<String>{
        'Ananya Rao', 'Rahul Menon', 'Priya Sharma', 'Karthik Iyer', 'Meera Nair', 'Arjun Das',
        'Sneha Kulkarni', 'Vikram Shetty', 'Divya Pillai', 'Rohan Gowda', 'Fatima Khan', 'Joseph DSouza'
    };
    private static final List<String> MODELS = new List<String>{ 'ZL Swift', 'ZL Lite', 'ZL Cargo' };
    private static final List<String> ZONES = new List<String>{
        'Koramangala', 'Indiranagar', 'HSR Layout', 'Whitefield', 'Jayanagar', 'MG Road'
    };

    /** Inserts all demo data. Does nothing (returns false) if the demo account already exists; run reset() instead. */
    public static Boolean seed() {
        if (![SELECT Id FROM Account WHERE Name = :ACCOUNT_NAME LIMIT 1].isEmpty()) {
            System.debug('ZipLane demo data already exists. Run scripts/apex/reset.apex to rebuild it.');
            return false;
        }
        Datetime now = System.now();

        Account acct = new Account(Name = ACCOUNT_NAME);
        Database.DMLOptions acctOpts = new Database.DMLOptions();
        acctOpts.duplicateRuleHeader.allowSave = true;
        Database.insert(acct, acctOpts);

        List<Contact> contacts = new List<Contact>();
        for (String full : RIDERS) {
            List<String> parts = full.split(' ');
            contacts.add(new Contact(
                AccountId = acct.Id, FirstName = parts[0], LastName = parts[1],
                Email = (parts[0] + '.' + parts[1]).toLowerCase() + '@example.com'
            ));
        }
        // The demo riders may collide with unrelated org contacts under duplicate rules; allow the save
        // (no org settings are changed and the other contacts are left untouched).
        Database.DMLOptions opts = new Database.DMLOptions();
        opts.duplicateRuleHeader.allowSave = true;
        for (Database.SaveResult sr : Database.insert(contacts, opts)) {
            if (!sr.isSuccess()) {
                throw new DmlException('Contact insert failed: ' + sr.getErrors()[0].getMessage());
            }
        }

        // Scooters ZL-0001..ZL-0020
        Set<Integer> maintenance = new Set<Integer>{ 3, 6 };
        List<Scooter__c> scooters = new List<Scooter__c>();
        for (Integer i = 1; i <= 20; i++) {
            String status = 'Available';
            if (i == 2) {
                status = 'In Ride';
            } else if (maintenance.contains(i)) {
                status = 'Under Maintenance';
            } else if (i == 20) {
                status = 'Retired';
            }
            scooters.add(new Scooter__c(
                Name = 'ZL-' + String.valueOf(i).leftPad(4, '0'),
                Model__c = MODELS[Math.mod(i - 1, 3)],
                Status__c = status,
                Battery_Level__c = 15 + Math.mod(i * 37, 86),
                Current_Zone__c = ZONES[Math.mod(i - 1, 6)],
                Last_Service_Date__c = Date.today().addDays(-Math.mod(i * 7, 60))
            ));
        }
        insert scooters;

        List<Ride_Booking__c> bookings = new List<Ride_Booking__c>();
        // Fixtures: BK-100i uses rider per table and scooter ZL-000i.
        bookings.add(done('BK-1001', contacts[0], scooters[0], 'Completed', now.addDays(-2), 18, 'Paid', 0));
        bookings.add(active('BK-1002', contacts[1], scooters[1], now.addMinutes(-25)));
        bookings.add(done('BK-1003', contacts[2], scooters[2], 'Ended - Breakdown', now.addDays(-1), 9, 'Paid', 2));
        bookings.add(done('BK-1004', contacts[3], scooters[3], 'Completed', now.addDays(-20), 24, 'Paid', 3));
        Datetime reserved5 = now.addDays(-2);
        bookings.add(base('BK-1005', contacts[4], scooters[4], 'Cancelled', 4, 20.00, 'Paid', reserved5, null, reserved5.addMinutes(12), 0));
        bookings.add(done('BK-1006', contacts[5], scooters[5], 'Ended - Breakdown', now.addDays(-3), 12, 'Paid', 5));
        bookings.add(done('BK-1007', contacts[6], scooters[6], 'Completed', now.addDays(-4), 20, 'Refunded', 6));
        bookings.add(base('BK-1008', contacts[7], scooters[7], 'Reserved', 7, 0.00, 'Not Charged', now.addMinutes(-2), null, null, 0));
        bookings.add(done('BK-1009', contacts[2], scooters[8], 'Completed', now.addDays(-1), 14, 'Paid', 8));

        // Fillers BK-1010..BK-1030 across the remaining riders (Divya, Rohan, Fatima, Joseph)
        for (Integer n = 10; n <= 30; n++) {
            Contact rider = contacts[8 + Math.mod(n, 4)];
            Scooter__c sc = scooters[6 + Math.mod(n, 13)];
            String name = 'BK-10' + String.valueOf(n);
            if (n == 15 || n == 25) {
                Datetime res = now.addDays(-(1 + Math.mod(n * 5, 30)));
                bookings.add(base(name, rider, sc, 'Cancelled', n, 0.00, 'Not Charged', res, null, res.addMinutes(3), 0));
            } else {
                Integer minutes = 8 + Math.mod(n * 7, 53);
                Datetime endAt = now.addDays(-(1 + Math.mod(n * 5, 30)));
                bookings.add(done(name, rider, sc, 'Completed', endAt, minutes, 'Paid', n));
            }
        }
        insert bookings;

        Map<String, Ride_Booking__c> byName = new Map<String, Ride_Booking__c>();
        for (Ride_Booking__c b : bookings) {
            byName.put(b.Name, b);
        }

        // Refund request on BK-1006
        Ride_Booking__c b6 = byName.get('BK-1006');
        insert new Refund_Request__c(
            Ride_Booking__c = b6.Id, Rider__c = b6.Rider__c, Reason__c = 'Breakdown During Ride',
            Details__c = 'Scooter stopped mid-ride (demo data).', Amount_Requested_INR__c = 40.00,
            Status__c = 'Pending Review', Eligibility__c = ZL_Constants.ELIG_ELIGIBLE_PENDING_REVIEW,
            Submitted_By_Agent__c = true
        );

        // Agent-style breakdown cases on BK-1003 and BK-1006
        List<Case> cases = new List<Case>();
        for (String[] spec : new List<String[]>{ new String[]{ 'BK-1003', 'Battery Dead' }, new String[]{ 'BK-1006', 'Flat Tyre' } }) {
            Ride_Booking__c b = byName.get(spec[0]);
            cases.add(new Case(
                Subject = 'Breakdown – ' + spec[0] + ' – ' + spec[1],
                Description = 'Breakdown reported via ZipLane virtual assistant (demo data).\nRider location: near the pickup zone',
                Origin = ZL_Constants.CASE_ORIGIN, Priority = 'Medium', Created_By_Agent__c = true,
                Ride_Booking__c = b.Id, Scooter__c = b.Scooter__c, ContactId = b.Rider__c,
                Issue_Type__c = spec[1], Rider_Location__c = 'Near the pickup zone', Rider_Safe__c = true
            ));
        }
        insert cases;
        return true;
    }

    /** Deletes all ZipLane demo data, then reseeds. */
    public static void reset() {
        delete [SELECT Id FROM Refund_Request__c];
        delete [SELECT Id FROM Case WHERE Created_By_Agent__c = true OR Ride_Booking__c != null];
        delete [SELECT Id FROM Ride_Booking__c];
        delete [SELECT Id FROM Scooter__c];
        // Only example.com contacts under the demo account, never other example.com contacts in the org.
        delete [SELECT Id FROM Contact WHERE Account.Name = :ACCOUNT_NAME AND Email LIKE '%@example.com'];
        delete [SELECT Id FROM Account WHERE Name = :ACCOUNT_NAME];
        seed();
    }

    private static Ride_Booking__c done(String name, Contact rider, Scooter__c sc, String status,
                                        Datetime endTime, Integer minutes, String pay, Integer idx) {
        Decimal fare = 10 + 2.5 * minutes;
        return base(name, rider, sc, status, idx, fare, pay, endTime.addMinutes(-minutes - 3),
            endTime.addMinutes(-minutes), endTime, minutes);
    }

    private static Ride_Booking__c active(String name, Contact rider, Scooter__c sc, Datetime start) {
        return base(name, rider, sc, 'Active', 1, 72.50, 'Pending', start.addMinutes(-2), start, null, 25);
    }

    private static Ride_Booking__c base(String name, Contact rider, Scooter__c sc, String status, Integer idx,
                                        Decimal fare, String pay, Datetime reserved, Datetime start,
                                        Datetime endTime, Integer minutes) {
        Boolean rode = start != null;
        return new Ride_Booking__c(
            Name = name, Rider__c = rider.Id, Scooter__c = sc.Id, Status__c = status,
            Reserved_At__c = reserved, Start_Time__c = start, End_Time__c = endTime,
            Pickup_Zone__c = ZONES[Math.mod(idx, 6)],
            Drop_Zone__c = (rode && endTime != null) ? ZONES[Math.mod(idx + 2, 6)] : null,
            Distance_km__c = rode ? (Decimal.valueOf(minutes) * 0.22).setScale(2) : null,
            Fare_INR__c = fare, Payment_Status__c = pay
        );
    }
}
