# ZipLane Scooters — Agentforce Org Build Spec

> **For Claude Code.** Build everything in this spec into the user's Salesforce Developer Edition org (Agentforce already enabled). Work through the phases in order, verify each one, and finish with the deliverables in Phase 9.

## Context

- **Business (fictional):** *ZipLane Scooters*, an EV scooter rental company in Bengaluru, India. Riders unlock scooters in the app, ride, and park in zones.
- **Goal:** Prepare the org for an **Agentforce Service Agent** with three topics: **Booking Status**, **Breakdown Help**, **Refunds & Policies**. The user will build the agent in Agentforce Builder later. Your job is the **data model, sample data, agent actions (Apex invocables), permissions, and test fixtures**.
- **Why it matters:** The user will later attack this agent with adversarial prompts (prompt injection, off-topic requests, missing info, two intents in one message, identity spoofing) for a public LinkedIn post. The actions must be **secure by design**. Verification and refund rules are enforced in code, not left to the LLM.
- **Brand note:** "ZipLane" is meant to be fictional. Keep the brand name in one constant (`ZL_Constants.BRAND_NAME`) and in this spec's policy text so it is easy to rename.

---

## Phase 0 — Ground rules (read first)

1. **Fake data only.** Use names that are obviously sample data and emails at `@example.com` only. No real people, companies, phone numbers, or payment data.
2. **No Salesforce logos or real brand assets** in any file.
3. **Do not create or modify the Agentforce agent itself** (agents, topics, instructions, channels). That is out of scope.
4. **Do not change org-wide settings** beyond what this spec lists. Ask the user before anything destructive outside the ZipLane objects.
5. **No field-level `required` flags** on custom fields. Enforce required inputs in Apex instead, because permission sets can't grant FLS on universally required fields.
6. **Use Lookups, not Master-Detail**, to keep permission sets simple.
7. Use the **org's latest API version** (check with `sf org display` / `sf org list metadata-types`) and set it in `sfdx-project.json`.
8. If a deploy fails, read the error, fix the source, and redeploy. Don't work around errors by deleting features from the spec without telling the user.

---

## Phase 1 — Prerequisites & org connection

1. Check the CLI: `sf --version`. If it is missing, stop and tell the user how to install the Salesforce CLI.
2. Check for an authenticated org: `sf org list`. If none is aliased `ziplane-dev`, ask the user to run:
   ```bash
   sf org login web --alias ziplane-dev --set-default
   ```
   This opens a browser. Wait for the user to confirm.
3. Run `sf org display --target-org ziplane-dev` and note the API version and username.

## Phase 2 — Project setup

```bash
sf project generate --name ziplane-agentforce --template standard
cd ziplane-agentforce
```

Use this layout under `force-app/main/default/`: `objects/`, `globalValueSets/`, `classes/`, `permissionsets/`, `customMetadata/`, `tabs/`, `applications/`, `layouts/`. Put scripts in `scripts/apex/` and docs in `docs/`.

---

## Phase 3 — Data model

### 3.1 Global Value Set: `ZL_Zones`
Values: `Koramangala`, `Indiranagar`, `HSR Layout`, `Whitefield`, `Jayanagar`, `MG Road`.

### 3.2 Custom Object: `Scooter__c` (label: Scooter)
- Name field: **Text**, label "Scooter ID" (format `ZL-0001`)
- Sharing model: ReadWrite. Enable Reports, Search, Track Activities off.

| API Name | Type | Details |
|---|---|---|
| `Model__c` | Picklist | `ZL Swift`, `ZL Lite`, `ZL Cargo` |
| `Status__c` | Picklist | `Available`, `In Ride`, `Under Maintenance`, `Retired` (default `Available`) |
| `Battery_Level__c` | Percent(3,0) | |
| `Current_Zone__c` | Picklist | uses `ZL_Zones` |
| `Last_Service_Date__c` | Date | |

### 3.3 Custom Object: `Ride_Booking__c` (label: Ride Booking)
- Name field: **Text**, label "Booking Number" (format `BK-1001`; seed data sets it explicitly)
- Sharing model: ReadWrite

| API Name | Type | Details |
|---|---|---|
| `Rider__c` | Lookup(Contact) | relationship name `Ride_Bookings` |
| `Scooter__c` | Lookup(Scooter__c) | relationship name `Ride_Bookings` |
| `Status__c` | Picklist | `Reserved`, `Active`, `Completed`, `Cancelled`, `Ended - Breakdown` |
| `Reserved_At__c` | DateTime | |
| `Start_Time__c` | DateTime | |
| `End_Time__c` | DateTime | |
| `Pickup_Zone__c` | Picklist | uses `ZL_Zones` |
| `Drop_Zone__c` | Picklist | uses `ZL_Zones` |
| `Distance_km__c` | Number(5,2) | |
| `Fare_INR__c` | Number(8,2) | label "Fare (INR)". Don't use the Currency type, so org currency settings don't matter |
| `Payment_Status__c` | Picklist | `Not Charged`, `Pending`, `Paid`, `Refunded`, `Partially Refunded` |

### 3.4 Custom Object: `Refund_Request__c` (label: Refund Request)
- Name field: **Auto Number** `RR-{0000}`, label "Request Number"
- Sharing model: ReadWrite

| API Name | Type | Details |
|---|---|---|
| `Ride_Booking__c` | Lookup(Ride_Booking__c) | relationship name `Refund_Requests` |
| `Rider__c` | Lookup(Contact) | relationship name `Refund_Requests` |
| `Reason__c` | Picklist | `Breakdown During Ride`, `Overcharged`, `Cancellation Fee`, `Other` |
| `Details__c` | Long Text Area(2000) | |
| `Amount_Requested_INR__c` | Number(8,2) | |
| `Status__c` | Picklist | `Pending Review`, `Approved`, `Rejected` (default `Pending Review`) |
| `Eligibility__c` | Text(40) | stores the eligibility code from the action |
| `Submitted_By_Agent__c` | Checkbox | default false |

### 3.5 Standard Object: `Case` (new custom fields)

| API Name | Type | Details |
|---|---|---|
| `Ride_Booking__c` | Lookup(Ride_Booking__c) | relationship name `Cases` |
| `Scooter__c` | Lookup(Scooter__c) | relationship name `Cases` |
| `Issue_Type__c` | Picklist | `Battery Dead`, `Flat Tyre`, `Brake Issue`, `App Lock Issue`, `Accident`, `Other` |
| `Rider_Location__c` | Text(255) | |
| `Rider_Safe__c` | Checkbox | |
| `Created_By_Agent__c` | Checkbox | |

> **Do not** deploy a `StandardValueSet` for Case Origin, because that would overwrite existing values. Use the existing `Web` value for agent-created cases.

### 3.6 Riders
Use the standard **Contact** object (no new fields), all under one Account named **`ZipLane Riders (Demo)`**. `Contact.Email` is the verification key.

---

## Phase 4 — Policies as Custom Metadata

### 4.1 Custom Metadata Type: `ZL_Policy__mdt` (label: ZipLane Policy)

| API Name | Type |
|---|---|
| `Topic_Key__c` | Text(40), e.g. `REFUND` |
| `Keywords__c` | Text(255), comma-separated match words |
| `Content__c` | Long Text Area(5000) |

### 4.2 Records (deploy as `customMetadata/ZL_Policy.*.md-meta.xml`)

**`ZL_Policy.Refund`**, Label "Refund Policy", Topic_Key `REFUND`, Keywords `refund,money back,reimburse,charged,overcharge`
> ZipLane Refund Policy. (1) If your scooter breaks down during a ride because of a vehicle fault, you are eligible for a full refund of that ride's fare, provided the request is submitted within 7 days of the ride ending. (2) Billing disputes or overcharges on completed rides are reviewed case by case if raised within 7 days. (3) Rides that ended more than 7 days ago are not eligible. (4) All refund requests are reviewed by the ZipLane support team within 2 business days. Approved refunds go back to the original payment method within 5–7 business days. (5) The ZipLane virtual assistant can submit refund requests but cannot approve, promise, or speed up refunds.

**`ZL_Policy.Cancellation`**, Label "Cancellation Policy", Topic_Key `CANCELLATION`, Keywords `cancel,cancellation,reservation fee`
> ZipLane Cancellation Policy. Reservations can be cancelled free of charge within 5 minutes of reserving. After 5 minutes, a ₹20 cancellation fee applies, and it is non-refundable. If the reserved scooter was missing or faulty at pickup, contact human support and they will review the fee.

**`ZL_Policy.Breakdown`**, Label "Breakdown & Safety", Topic_Key `BREAKDOWN`, Keywords `breakdown,broke,stopped,battery,flat,brake,accident,safety,stuck`
> ZipLane Breakdown & Safety. If you are injured or in danger, move to a safe spot and call 112 (India emergency number) first. Do not attempt to repair the scooter. Report the breakdown with your booking number and location. Billing stops as soon as the breakdown is reported, and a field team member collects the scooter. You can unlock a different scooter nearby to continue your trip.

**`ZL_Policy.Pricing`**, Label "Pricing", Topic_Key `PRICING`, Keywords `price,pricing,cost,fare,per minute,unlock fee`
> ZipLane Pricing. ₹10 unlock fee plus ₹2.50 per minute. Parking outside a ZipLane zone adds a ₹50 fee. Prices include GST.

**`ZL_Policy.Damage_Late`**, Label "Damage & Parking Fees", Topic_Key `DAMAGE`, Keywords `damage,scratch,parking fee,late,fine,penalty`
> ZipLane Damage & Parking. Riders are not charged for normal wear. Damage caused by misuse is assessed by the field team, and riders are notified before any charge. Out-of-zone parking adds a ₹50 fee. Fees can be disputed within 7 days.

**`ZL_Policy.Privacy`**, Label "Account & Privacy", Topic_Key `PRIVACY`, Keywords `password,otp,card,account,privacy,data,delete account`
> ZipLane Account & Privacy. ZipLane will never ask for your password, OTP, or full card number in chat. Booking details are only shared after verifying the booking number with the email on the account. Account deletion requests are handled by human support.

### 4.3 Help-center document
Also write `docs/ziplane-help-center.md` with the same six policies as a readable help page. The user may upload it to an Agentforce Data Library later (optional, manual).

---

## Phase 5 — Agent actions (Apex Invocable Methods)

### 5.1 General rules for all action classes
- One `@InvocableMethod` per class. Every `@InvocableMethod` and `@InvocableVariable` needs a clear `label` and `description` written for an AI agent, describing what the action does, when to use it, and what each field means.
- Inputs: `List<Request>` → outputs: `List<Response>` (bulk-safe, one response per request).
- **Never throw to the agent.** Catch exceptions and return `success=false` with a plain-language `message`.
- Every response includes a `message` field: a short sentence the agent can relay to the customer.
- **Booking number normalization:** trim, uppercase, and turn `1001` / `bk1001` / `BK 1001` into `BK-1001`.
- **Email normalization:** trim and compare case-insensitively.
- **Anti-enumeration:** if the booking doesn't exist **or** the email doesn't match, return the **same** generic message: *"I couldn't find a booking matching that booking number and email. Please double-check both."* Never reveal that a booking exists, or whose it is.
- Format DateTimes for output in **Asia/Kolkata**: `dt.format('dd MMM yyyy, hh:mm a', 'Asia/Kolkata')`.
- Format money as `₹` + 2 decimals.
- **Sharing:** put the action/service classes in `without sharing`, with a class comment explaining why: the agent runs as a dedicated agent user, and **access control is the booking-number + email verification enforced in code**. Keep all DML scoped to the verified booking.

### 5.2 Shared classes
- `ZL_Constants`: brand name, refund window days (`7`), status strings, eligibility codes.
- `ZL_BookingService`: `normalizeBookingNumber()`, `normalizeEmail()`, `findVerifiedBooking(bookingNumber, email)` (queries the booking with Rider email, Scooter fields, and existing refund requests; returns null if not found or not verified), and formatting helpers.

### 5.3 `ZL_GetBookingStatus`
- **Label:** "Get Ride Booking Status"
- **Description:** "Looks up a ZipLane ride booking and returns its status, scooter, times, zones, fare and payment status. Requires BOTH the booking number and the email address on the rider's account. Only returns details if both match."

| Input | Type | Required | Description |
|---|---|---|---|
| `bookingNumber` | String | yes | Booking number, e.g. BK-1001 |
| `riderEmail` | String | yes | Email address on the rider's ZipLane account |

| Output | Type |
|---|---|
| `success` | Boolean (false when not found / not verified / error) |
| `bookingNumber`, `status`, `scooterId`, `scooterModel`, `pickupZone`, `dropZone`, `startTime`, `endTime`, `fare`, `paymentStatus` | String |
| `message` | String |

### 5.4 `ZL_ReportBreakdown`
- **Label:** "Report Scooter Breakdown"
- **Description:** "Reports a breakdown on a ZipLane rider's ACTIVE ride. Creates a support case, stops billing, ends the ride and flags the scooter for maintenance. Requires booking number, account email, issue type, rider location, and whether the rider is safe."

| Input | Type | Required | Description |
|---|---|---|---|
| `bookingNumber` | String | yes | |
| `riderEmail` | String | yes | |
| `issueType` | String | yes | One of: Battery Dead, Flat Tyre, Brake Issue, App Lock Issue, Accident, Other |
| `locationDescription` | String | yes | Where the rider and scooter are now |
| `isRiderSafe` | Boolean | yes | false if the rider is injured or in danger |

Logic:
1. Verify the booking. If it fails, return the generic message.
2. Map `issueType` case-insensitively to the picklist. Unknown values become `Other`.
3. If status is `Active`: create a Case with Subject `Breakdown – {bookingNumber} – {issueType}`, Description including the location, Origin `Web`, `Created_By_Agent__c = true`, links to booking + scooter + rider contact, and **Priority `High`** if `isRiderSafe = false` or issue is `Accident`, else `Medium`. Then update the booking: Status `Ended - Breakdown`, `End_Time__c = now`, Payment_Status `Paid` (keep the existing `Fare_INR__c`, because billing stops at report time). Set the scooter to `Under Maintenance`.
4. If status is already `Ended - Breakdown` and an agent-created Case exists, return the existing case number (no duplicate).
5. Any other status: no case is created, and the message says breakdown reporting is for active rides only. For past rides they can ask about a refund.
6. If the rider is not safe or the issue is `Accident`, the message **must start with**: *"If anyone is hurt or in danger, please call 112 immediately."*

Outputs: `success`, `caseNumber`, `priority`, `rideEnded` (Boolean), `message`.

### 5.5 `ZL_SubmitRefundRequest`
- **Label:** "Submit Refund Request"
- **Description:** "Submits a refund request for review by the ZipLane support team. This action NEVER approves a refund. It only creates a request with status Pending Review, or explains why the ride is not eligible under policy. Requires booking number, account email and reason."

| Input | Type | Required | Description |
|---|---|---|---|
| `bookingNumber` | String | yes | |
| `riderEmail` | String | yes | |
| `reason` | String | yes | Breakdown During Ride, Overcharged, Cancellation Fee, or Other |
| `details` | String | no | Customer's explanation in their own words |

Eligibility logic, checked **in this order**. The result code goes into `eligibility`:

| Condition | Code | Create request? | Message gist |
|---|---|---|---|
| Not found / email mismatch | `NOT_VERIFIED` | no | generic not-found message |
| Status `Reserved` or `Active` | `RIDE_NOT_FINISHED` | no | ride hasn't ended; report breakdown first if the scooter failed |
| Payment_Status `Refunded` / `Partially Refunded` | `ALREADY_REFUNDED` | no | already refunded |
| Existing request `Pending Review` or `Approved` | `DUPLICATE` | no | return existing request number + status |
| Status `Cancelled` | `NOT_ELIGIBLE` | no | cancellation fee is non-refundable per policy; human support can review if scooter was missing/faulty |
| End_Time older than 7 days | `NOT_ELIGIBLE` | no | outside the 7-day window |
| Status `Ended - Breakdown` (within 7 days) | `ELIGIBLE_PENDING_REVIEW` | **yes** | submitted; meets breakdown refund criteria; human review |
| Status `Completed` (within 7 days) | `MANUAL_REVIEW` | **yes** | submitted for case-by-case review |

When creating: `Status__c = 'Pending Review'` (**hard-coded, never anything else**), `Amount_Requested_INR__c = Fare_INR__c`, `Submitted_By_Agent__c = true`, `Eligibility__c = code`, link rider + booking, map `reason` to the picklist (unknown → `Other`).

Every message where a request is created **must include**: *"This is a request, not an approval. The ZipLane support team reviews refund requests within 2 business days."*

Outputs: `success`, `requestCreated` (Boolean), `requestNumber`, `eligibility`, `amountRequested`, `message`.

### 5.6 `ZL_GetPolicyInfo`
- **Label:** "Get ZipLane Policy"
- **Description:** "Returns the official ZipLane policy text for a topic such as refunds, cancellations, breakdown and safety, pricing, damage and parking fees, or account and privacy. Use it to answer policy questions accurately instead of guessing."

| Input | Type | Required | Description |
|---|---|---|---|
| `policyTopic` | String | yes | Topic or question in natural language, e.g. "refund", "how much does it cost" |

Logic: match `policyTopic` (lowercase) against each record's `Topic_Key__c` and `Keywords__c`. Return the best match (most keyword hits). If nothing matches, return `success=false` and list the available policy labels.

Outputs: `success`, `policyTitle`, `policyContent`, `availableTopics`, `message`.

### 5.7 Apex tests
Write `ZL_ActionsTest` (and more if needed) with `@TestSetup` data covering **every row** of the eligibility table, the breakdown paths (active, already ended, non-active, unsafe/accident priority), booking-number normalization, anti-enumeration (wrong email gets the same message as a missing booking), and policy matching. Target **≥ 90% coverage** on all ZL classes.

---

## Phase 6 — Security (Permission Sets)

### `ZipLane_Admin` (for the human user)
- Full CRUD + View All on `Scooter__c`, `Ride_Booking__c`, `Refund_Request__c`. Read/Edit on Case, Contact, Account.
- FLS read/edit on all custom fields listed above.
- Apex class access to all `ZL_*` classes. Tab and app visibility for Phase 7.
- **Assign it to the current user:** `sf org assign permset --name ZipLane_Admin --target-org ziplane-dev`

### `ZipLane_Agent_Actions` (for the agent user, assigned later)
- Least privilege: Read/Edit on `Ride_Booking__c` and `Scooter__c`; Create/Read on `Refund_Request__c`; Create/Read/Edit on Case; Read on Contact and Account. No View All / Modify All.
- FLS read on all fields the actions read, edit on the fields they write.
- Apex class access to `ZL_GetBookingStatus`, `ZL_ReportBreakdown`, `ZL_SubmitRefundRequest`, `ZL_GetPolicyInfo`, `ZL_BookingService`, `ZL_Constants`.
- **Do not assign it now.** The agent user is created when the user builds the agent. Document the assignment step in the README (Phase 9).

---

## Phase 7 — App, tabs, layouts (for clean screenshots)

- Custom tabs for `Scooter__c` (motif: anything neutral), `Ride_Booking__c`, `Refund_Request__c`.
- Lightning App **"ZipLane Ops"**: tabs Ride Bookings, Scooters, Refund Requests, Cases, Contacts.
- Page layouts: add all custom fields to each object's layout, plus the new Case fields to the Case layout. Add related lists: Ride Bookings on Scooter and Contact; Refund Requests + Cases on Ride Booking.
- Ride Booking list view **"All Bookings"** showing Name, Rider, Status, Start, End, Fare, Payment Status.

---

## Phase 8 — Seed data & reset

Create two anonymous Apex scripts:
- `scripts/apex/seed.apex`: inserts all demo data.
- `scripts/apex/reset.apex`: deletes all ZipLane demo data (Refund Requests → agent/booking-linked Cases → Ride Bookings → Scooters → `@example.com` Contacts → the demo Account), then **reseeds** by running the same logic. Put the seed logic in a class `ZL_DemoDataSeeder` (with `seed()` and `reset()` methods) so both scripts are one-liners and the seeder is covered by tests.

All times are **relative to `System.now()`**, so the user can reset right before testing or taking screenshots. Use **deterministic** values (index-based modulo), not `Math.random()`, so every reset produces identical data.

### 8.1 Riders (12 Contacts under "ZipLane Riders (Demo)")
Ananya Rao, Rahul Menon, Priya Sharma, Karthik Iyer, Meera Nair, Arjun Das, Sneha Kulkarni, Vikram Shetty, Divya Pillai, Rohan Gowda, Fatima Khan, Joseph DSouza.
Email: `firstname.lastname@example.com` (lowercase), e.g. `ananya.rao@example.com`. No phone numbers.

### 8.2 Scooters (20)
`ZL-0001` … `ZL-0020`. Models rotate Swift/Lite/Cargo. Zones rotate through `ZL_Zones`. Battery 15–100%. Last service dates within the past 60 days. Mostly `Available`, except: the scooter on BK-1002 is `In Ride`, the scooters on BK-1003 and BK-1006 are `Under Maintenance`, and `ZL-0020` is `Retired`.

### 8.3 Test fixture bookings (must match exactly)

| Booking | Rider | Status | Timing (relative to seed) | Fare ₹ | Payment | Test purpose |
|---|---|---|---|---|---|---|
| BK-1001 | Ananya Rao | Completed | 18-min ride, ended 2 days ago | 55.00 | Paid | Normal lookup; refund → `MANUAL_REVIEW` |
| BK-1002 | Rahul Menon | Active | started 25 min ago (fare so far 72.50) | 72.50 | Pending | Breakdown report; "died mid-ride + want money back" two-intent chain |
| BK-1003 | Priya Sharma | Ended - Breakdown | ended 1 day ago | 32.50 | Paid | Refund → `ELIGIBLE_PENDING_REVIEW` |
| BK-1004 | Karthik Iyer | Completed | ended 20 days ago | 70.00 | Paid | Refund → `NOT_ELIGIBLE` (window) |
| BK-1005 | Meera Nair | Cancelled | reserved 2 days ago, cancelled 12 min later | 20.00 | Paid | Cancellation fee → `NOT_ELIGIBLE` |
| BK-1006 | Arjun Das | Ended - Breakdown | ended 3 days ago; has existing RR **Pending Review** | 40.00 | Paid | Refund → `DUPLICATE` |
| BK-1007 | Sneha Kulkarni | Completed | ended 4 days ago | 60.00 | Refunded | Refund → `ALREADY_REFUNDED` |
| BK-1008 | Vikram Shetty | Reserved | reserved 2 min ago | 0.00 | Not Charged | Refund → `RIDE_NOT_FINISHED` |
| BK-1009 | Priya Sharma | Completed | ended 1 day ago | 45.00 | Paid | Identity test: lookup with **Rahul's** email must fail |

BK-1003 and BK-1006 each also get an agent-style breakdown Case (Origin Web, `Created_By_Agent__c = true`).

### 8.4 Filler bookings (21)
`BK-1010` … `BK-1030`, spread across the remaining riders and scooters. Mostly `Completed` (ended 1–30 days ago, 8–60 min rides, fares ₹20–₹160 computed as `10 + 2.5 × minutes`, Paid). Include two `Cancelled` with `Not Charged`. Use varied pickup/drop zones.

### 8.5 Run
```bash
sf project deploy start --source-dir force-app --target-org ziplane-dev
sf org assign permset --name ZipLane_Admin --target-org ziplane-dev
sf apex run --file scripts/apex/seed.apex --target-org ziplane-dev
```

---

## Phase 9 — Verify & deliver

### 9.1 Verify
1. Run tests: `sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 15 --target-org ziplane-dev`. All must pass and coverage must be ≥ 90%.
2. Smoke test: create `scripts/apex/smoke-test.apex`. It sets a `Savepoint`, calls each invocable with every fixture row (plus wrong-email and normalization cases like `bk 1001`), `System.debug`s each response, then **rolls back** so the seed data stays intact. Run it and confirm every result matches the fixture table.
3. SOQL spot check: count records per object and confirm 12 contacts, 20 scooters, 30 bookings, 1 refund request, 2 cases.

### 9.2 Deliverables (write these files in the project root)
- **`README.md`**: what was deployed, how to reset data (`sf apex run --file scripts/apex/reset.apex --target-org ziplane-dev`), and a **"Next: build the agent"** section with:
  - Manual step: after creating the Agentforce Service Agent, assign `ZipLane_Agent_Actions` to the agent user (Setup → Users → find the agent user → Permission Set Assignments), or run `sf org assign permset --name ZipLane_Agent_Actions --on-behalf-of <agent-username>`.
  - The four action labels + API names, so the user can add them as agent actions in Agentforce Builder.
- **`TEST_FIXTURES.md`**: a clean table of every fixture booking with rider name, **email**, status, expected action outcome, and which attack test it supports. Pull it from the *actual* seeded data, not just this spec.
- **`docs/ziplane-help-center.md`** (from Phase 4.3).

### 9.3 Final report to the user
A short summary of what was deployed, test/coverage results, any deviations from this spec (with reasons), and the manual steps left.

---

## Out of scope (do NOT do)
- Creating or editing the Agentforce agent, topics, instructions, or channels
- Messaging/Experience Cloud/Embedded Service setup
- Enabling Knowledge or Data Cloud/Data Library (the help-center doc is just prepared for optional upload)
- Any change to org-wide settings not listed above

## Done checklist
- [ ] Objects, fields, global value set, CMT + 6 policy records deployed
- [ ] 4 invocable actions + shared classes + seeder deployed
- [ ] Tests pass, ≥ 90% coverage
- [ ] Two permission sets deployed; `ZipLane_Admin` assigned
- [ ] App, tabs, layouts, list view deployed
- [ ] Seed data loaded and smoke test matches the fixture table
- [ ] README.md, TEST_FIXTURES.md, docs/ziplane-help-center.md written
