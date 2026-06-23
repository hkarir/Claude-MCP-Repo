/**
 * SCRUM-1 — Batch job.
 *
 * Finds open Leads that have been open for more than 60 days and creates a follow-up Task on
 * each one, prompting the Lead owner to either close the Lead or mark it as bogus.
 *
 * Task due date  = today + 2 days.
 * Task owner     = the Lead's owner.
 *
 * "Open" means a non-closed Lead status. Note this org has a `Closed - Not Converted` status with
 * IsConverted = false, so the query excludes any status matching `Closed%` rather than relying on
 * IsConverted alone.
 */
public with sharing class LeadAgingTaskBatch implements Database.Batchable<SObject> {

    @TestVisible
    private static final Integer AGING_DAYS = 60;

    @TestVisible
    private static final Integer DUE_IN_DAYS = 2;

    @TestVisible
    private static final String TASK_SUBJECT = 'Review aging Lead: close or mark as bogus';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date cutoff = Date.today().addDays(-AGING_DAYS);
        return Database.getQueryLocator([
            SELECT Id, OwnerId
            FROM Lead
            WHERE IsConverted = false
              AND (NOT Status LIKE 'Closed%')
              AND CreatedDate < :cutoff
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lead> scope) {
        Set<Id> leadIds = new Set<Id>();
        for (Lead l : scope) {
            leadIds.add(l.Id);
        }

        // Idempotency guard: skip Leads that already have an open follow-up Task with this subject,
        // so re-running the job does not create duplicate Tasks.
        Set<Id> leadsWithOpenTask = new Set<Id>();
        for (Task t : [
            SELECT WhoId
            FROM Task
            WHERE WhoId IN :leadIds
              AND Subject = :TASK_SUBJECT
              AND IsClosed = false
        ]) {
            leadsWithOpenTask.add(t.WhoId);
        }

        Date dueDate = Date.today().addDays(DUE_IN_DAYS);
        List<Task> tasksToCreate = new List<Task>();
        for (Lead l : scope) {
            if (leadsWithOpenTask.contains(l.Id)) {
                continue;
            }
            tasksToCreate.add(new Task(
                WhoId        = l.Id,
                OwnerId      = l.OwnerId,
                Subject      = TASK_SUBJECT,
                ActivityDate = dueDate,
                Status       = 'Not Started',
                Priority     = 'Normal',
                Description  = 'This Lead has been open for more than ' + AGING_DAYS +
                               ' days. Please either close it or mark it as bogus.'
            ));
        }

        if (!tasksToCreate.isEmpty()) {
            insert tasksToCreate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing required.
    }
}
