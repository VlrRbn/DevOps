# lesson_18

---

# Alerts & Probes: Alertmanager + Blackbox + Nginx Exporter

**Date:** 2025-11-01

**Topic:** Wire **Alertmanager**, add **blackbox_exporter** (HTTP probes) and **nginx-prometheus-exporter** (Nginx), create actionable alerts, and verify end-to-end

---

## Goals

- Add **Alertmanager** lesson_17 stack and route alerts.
- Probe endpoints with **blackbox_exporter** (HTTP/HTTPS).
- Expose Nginx metrics via **nginx-prometheus-exporter** + `/nginx_status`.
- Create useful alerts (node, HTTP probes, Nginx 5xx/rate).
- Prove alert lifecycle: **Pending → Firing → Resolved**.

---