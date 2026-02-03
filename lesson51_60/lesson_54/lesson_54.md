# lesson_54

---

# Blue/Green Deployments with ALB + ASG

**Date:** 2026-02-03

**Focus:** Deploy new versions safely using **two target groups** and **controlled traffic shifting**, with rollback that’s basically “flip the switch”.

---

## Target Architecture

```
                 ┌──────────────┐
Client ───────►  │     ALB      │
                 │ Listener :80 │
                 └──────┬───────┘
                        │ (weights)
         ┌──────────────┴──────────────┐
         │                               │
   Target Group BLUE                Target Group GREEN
   (ASG blue)                       (ASG green)
   AMI v1                           AMI v2

```

You will be able to do:

- 100/0 (all blue)
- 90/10 (canary-ish)
- 0/100 (full cutover)
- instant rollback (back to blue)

---

## Goals / Acceptance Criteria

- [ ]  Two target groups exist: `blue` and `green`
- [ ]  Two ASGs exist: `web-blue-asg` and `web-green-asg`
- [ ]  ALB listener forwards traffic with **weights**
- [ ]  90/10 shift works and is observable via responses
- [ ]  Rollback works instantly (weights back)
- [ ]  A bad green deploy never takes down prod traffic

---

## Preconditions

- You can reach the internal ALB via proxy (your current model)
- Web page prints instance identity (hostname/instance-id or build stamp)
- ASG + Launch Template already working (lesson_50–51)

---
