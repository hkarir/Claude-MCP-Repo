/**
 * Tests for LeadAgingTaskBatch (SCRUM-1).
 */
@isTest
private class LeadAgingTaskBatchTest {

    @testSetup
    static void setup() {
        List<Lead> leads = new List<Lead>{
            new Lead(LastName = 'AgingOpen',   Company = 'Acme', Status = 'Open - Not Contacted'),
            new Lead(LastName = 'RecentOpen',  Company = 'Acme', Status = 'Open - Not Contacted'),
            new Lead(LastName = 'AgingClosed', Company = 'Acme', Status = 'Closed - Not Converted')
        };
        insert leads;

        // Backdate the two "aging" leads to 90 days ago; RecentOpen stays created "now".
        System.Test.setCreatedDate(leads[0].Id, Datetime.now().addDays(-90));
        System.Test.setCreatedDate(leads[2].Id, Datetime.now().addDays(-90));
    }

    @isTest
    static void createsTaskForAgingOpenLeadsOnly() {
        System.Test.startTest();
        Database.executeBatch(new LeadAgingTaskBatch(), 200);
        System.Test.stopTest();

        Lead agingOpen = [SELECT Id, OwnerId FROM Lead WHERE LastName = 'AgingOpen' LIMIT 1];

        List<Task> tasks = [SELECT WhoId, OwnerId, ActivityDate, Subject FROM Task];
        System.assertEquals(1, tasks.size(),
            'Only the aging open lead should receive a follow-up task');

        Task t = tasks[0];
        System.assertEquals(agingOpen.Id, t.WhoId, 'Task should be linked to the aging open lead');
        System.assertEquals(agingOpen.OwnerId, t.OwnerId, 'Task owner should match the lead owner');
        System.assertEquals(Date.today().addDays(2), t.ActivityDate, 'Due date should be today + 2');
        System.assertEquals(LeadAgingTaskBatch.TASK_SUBJECT, t.Subject, 'Subject should match');
    }

    @isTest
    static void doesNotCreateDuplicateWhenOpenTaskExists() {
        Lead agingOpen = [SELECT Id, OwnerId FROM Lead WHERE LastName = 'AgingOpen' LIMIT 1];
        insert new Task(
            WhoId        = agingOpen.Id,
            OwnerId      = agingOpen.OwnerId,
            Subject      = LeadAgingTaskBatch.TASK_SUBJECT,
            Status       = 'Not Started',
            ActivityDate = Date.today().addDays(2)
        );

        System.Test.startTest();
        Database.executeBatch(new LeadAgingTaskBatch(), 200);
        System.Test.stopTest();

        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE WhoId = :agingOpen.Id AND Subject = :LeadAgingTaskBatch.TASK_SUBJECT
        ];
        System.assertEquals(1, taskCount, 'Re-run should not create a duplicate task');
    }
}
