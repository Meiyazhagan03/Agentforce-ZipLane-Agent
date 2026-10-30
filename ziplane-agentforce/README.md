# ZipLane Scooters — Agentforce Org Build

*ZipLane Scooters is a fictional EV scooter rental company in Bengaluru.* This project prepares a Salesforce org for an **Agentforce Service Agent** with three topics: Booking Status, Breakdown Help, Refunds & Policies. It contains the data model, demo data, agent actions (Apex invocables), permission sets and test fixtures. The agent itself is **not** included.

Target org alias: `ziplane-dev` (API v68.0). The brand name lives in `ZL_Constants.BRAND_NAME` and in the policy text (`customMetadata/ZL_Policy.*`).

## What was deployed
- **Data model:** `Scooter__c`, `Ride_Booking__c`, `Refund_Request__c`, new `Case` fields, global value set `ZL_Zones`.
- **Policies:** custom metadata type `ZL_Policy__mdt` with 6 records (also in `docs/ziplane-help-center.md`).
- **Apex:** `ZL_Constants`, `ZL_BookingService`, four invocable actions, `ZL_DemoDataSeeder`, `ZL_ActionsTest` (≥ 97% coverage on every ZL class).
- **Security:** permission sets `ZipLane_Admin` (assigned to the deploying user) and `ZipLane_Agent_Actions` (**not** assigned).
- **UI:** "ZipLane Ops" Lightning app, 3 tabs, layouts, "All Bookings" list view.
- **Demo data:** 12 riders, 20 scooters, 30 bookings, 1 refund request, 2 agent-style cases.

## Security design
Verification and refund rules are enforced in code, not left to the LLM. Every action requires booking number **and** account email. A missing booking and a wrong email return the identical message. Refund requests are always created as `Pending Review`; nothing here can approve a refund. Action classes are `without sharing` by design (the agent runs as a dedicated user and the verification is the access control).

## Reset the demo data
```bash
sf apex run --file scripts/apex/reset.apex --target-org ziplane-dev
```
All times are relative to "now", so reset right before testing or screenshots. `reset` deletes **all** Refund Requests, agent/booking-linked Cases, Ride Bookings and Scooters in the org, plus the demo account and its `@example.com` contacts, then reseeds. `seed.apex` alone does nothing if the demo data already exists.

Smoke test (rolls back, seed data stays intact): `sf apex run --file scripts/apex/smoke-test.apex --target-org ziplane-dev`

## Next: build the agent
1. Create the Agentforce Service Agent in Agentforce Builder.
2. **Assign `ZipLane_Agent_Actions` to the agent user** (Setup → Users → find the agent user → Permission Set Assignments), or run:
   ```bash
   sf org assign permset --name ZipLane_Agent_Actions --on-behalf-of <agent-username> --target-org ziplane-dev
   ```
3. Add these as agent actions (type: Apex):

| Action label | Apex class | Topic |
|---|---|---|
| Get Ride Booking Status | `ZL_GetBookingStatus` | Booking Status |
| Report Scooter Breakdown | `ZL_ReportBreakdown` | Breakdown Help |
| Submit Refund Request | `ZL_SubmitRefundRequest` | Refunds & Policies |
| Get ZipLane Policy | `ZL_GetPolicyInfo` | Refunds & Policies |

4. Optional: upload `docs/ziplane-help-center.md` to a Data Library.

See `TEST_FIXTURES.md` for the test bookings and expected outcomes.

## Agent (added after the original spec)
A draft agent, `ZipLane_Support`, was built from `force-app/main/default/aiAuthoringBundles/ZipLane_Support/ZipLane_Support.agent` and published to `ziplane-new` (not activated). It runs as `ziplane_agent@00dfj00000ryxhveav.ext` with `AgentforceServiceAgentUser` + `ZipLane_Agent_Actions`.
- Re-validate/publish: `sf agent validate authoring-bundle --api-name ZipLane_Support --target-org ziplane-new` then `sf agent publish authoring-bundle --api-name ZipLane_Support --target-org ziplane-new`
- Chat with it: `sf agent preview --authoring-bundle ZipLane_Support --use-live-actions --target-org ziplane-new` (live actions write real records; reset the data afterwards)
- Activate when ready: `sf agent activate --api-name ZipLane_Support --target-org ziplane-new`
