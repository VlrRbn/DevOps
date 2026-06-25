# Runbook: Drift After Emergency Manual Change

## Scenario

Someone changed AWS manually during an incident.

## Goal

Return the environment to Terraform control.

## Procedure

1. Record the manual change: who, when, why, exact resource.
2. Run drift detection or `terraform plan -detailed-exitcode`.
3. Classify the change: accidental drift, intentional emergency change, or state mismatch.
4. Choose recovery path: revert in AWS, codify in Terraform, or import/reconcile.
5. Open PR if config must change.
6. Apply through controlled pipeline.
7. Verify drift is clean.

## Rule

Emergency manual change is acceptable only if it is later reconciled.

## Evidence

- manual change record
- drift plan
- chosen recovery path
- PR/apply output
- post-incident check
