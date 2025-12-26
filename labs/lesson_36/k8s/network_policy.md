# lab36 NetworkPolicy Runbook

## 1. Questions to ask

1. Which pods are we **protecting**? (podSelector)
2. Which traffic directions? (ingress / egress / both)
3. Who exactly should be allowed? (from/to – podSelector, namespaceSelector, ipBlock)
4. What ports/protocols should be allowed?

## 2. Default-deny pattern

- For a namespace:
  - Ingress default-deny: NetworkPolicy with podSelector: {} and no ingress rules.
  - Egress default-deny: policyTypes: [Egress] and no egress rules.

Then add specific allow policies.

## 3. Debugging

1. Check policies:
   - kubectl get networkpolicy -n <ns>
   - kubectl describe networkpolicy <name> -n <ns>
2. From inside a Pod:
   - kubectl exec -it <pod> -n <ns> -- curl / nc
3. If in doubt, temporarily delete the policy:
   - kubectl delete networkpolicy <name> -n <ns>
