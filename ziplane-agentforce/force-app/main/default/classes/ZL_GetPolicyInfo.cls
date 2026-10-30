/**
 * Agent action: return official policy text from ZL_Policy__mdt. without sharing: policies are public,
 * non-customer data, and no customer records are read or written.
 */
public without sharing class ZL_GetPolicyInfo {

    @TestVisible private static Boolean forceError = false;

    public class Request {
        @InvocableVariable(label='Policy Topic' required=true
            description='Topic or question in natural language, e.g. "refund" or "how much does it cost".')
        public String policyTopic;
    }

    public class Response {
        @InvocableVariable(label='Success' description='False when no policy matched the topic.')
        public Boolean success;
        @InvocableVariable(label='Policy Title' description='Title of the matched policy.')
        public String policyTitle;
        @InvocableVariable(label='Policy Content' description='Official policy text. Answer only from this text.')
        public String policyContent;
        @InvocableVariable(label='Available Topics' description='Comma-separated list of available policy titles, returned when nothing matched.')
        public String availableTopics;
        @InvocableVariable(label='Message' description='Short message to relay to the rider.')
        public String message;
    }

    @InvocableMethod(label='Get ZipLane Policy'
        description='Returns the official ZipLane policy text for a topic such as refunds, cancellations, breakdown and safety, pricing, damage and parking fees, or account and privacy. Use it to answer policy questions accurately instead of guessing.')
    public static List<Response> getPolicy(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            out.add(handle(req));
        }
        return out;
    }

    /** Lowercase, non-alphanumerics to single spaces, padded so keywords match from the start of a word. */
    private static String normalize(String s) {
        return ' ' + s.toLowerCase().replaceAll('[^a-z0-9]+', ' ').trim();
    }

    private static Response handle(Request req) {
        Response r = new Response();
        r.success = false;
        try {
            if (forceError) {
                throw new IllegalArgumentException('forced error (tests only)');
            }
            List<ZL_Policy__mdt> policies = [
                SELECT DeveloperName, Label, Topic_Key__c, Keywords__c, Content__c
                FROM ZL_Policy__mdt ORDER BY DeveloperName
            ];
            List<String> titles = new List<String>();
            for (ZL_Policy__mdt p : policies) {
                titles.add(p.Label);
            }
            r.availableTopics = String.join(titles, ', ');

            if (req == null || String.isBlank(req.policyTopic)) {
                r.message = 'Which policy would you like to know about? Available topics: ' + r.availableTopics + '.';
                return r;
            }
            String topic = normalize(req.policyTopic);
            ZL_Policy__mdt best = null;
            Integer bestScore = 0;
            for (ZL_Policy__mdt p : policies) {
                Integer score = 0;
                if (String.isNotBlank(p.Topic_Key__c) && topic.contains(' ' + p.Topic_Key__c.toLowerCase())) {
                    score++;
                }
                if (String.isNotBlank(p.Keywords__c)) {
                    for (String kw : p.Keywords__c.split(',')) {
                        String k = kw.trim().toLowerCase();
                        if (k != '' && topic.contains(' ' + k)) {
                            score++;
                        }
                    }
                }
                if (score > bestScore) {
                    best = p;
                    bestScore = score;
                }
            }
            if (best == null) {
                r.message = 'I couldn\'t find a policy for that. Available topics: ' + r.availableTopics + '.';
                return r;
            }
            r.success = true;
            r.policyTitle = best.Label;
            r.policyContent = best.Content__c;
            r.message = 'Here is the ' + best.Label + '.';
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ZL_GetPolicyInfo: ' + e.getMessage());
            r = new Response();
            r.success = false;
            r.message = ZL_Constants.GENERIC_ERROR;
        }
        return r;
    }
}