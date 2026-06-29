package terraform.plan

# Optional OPA/Rego v1 for the same core deny rules as security-policy.sh.

is_delete_action(actions) if {
	actions[_] == "delete"
}

# Replacement plans are destructive in operational terms even when Terraform will recreate the object.
deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	is_delete_action(rc.change.actions)
	msg := sprintf("destructive change is not allowed: %s actions=%v", [rc.address, rc.change.actions])
}

# AWS provider generations expose SG rules through multiple resource schemas.
# Keep separate rules for each schema.
deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	rc.type == "aws_security_group_rule"
	not is_delete_action(rc.change.actions)
	rc.change.after.type == "ingress"
	cidr := rc.change.after.cidr_blocks[_]
	cidr == "0.0.0.0/0"
	msg := sprintf("public IPv4 ingress is not allowed: %s", [rc.address])
}

# Tag policy applies only when the resource exposes tags/tags_all in the plan.
# Untaggable resources are outside this rule.
deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	rc.type == "aws_security_group_rule"
	not is_delete_action(rc.change.actions)
	rc.change.after.type == "ingress"
	cidr := rc.change.after.ipv6_cidr_blocks[_]
	cidr == "::/0"
	msg := sprintf("public IPv6 ingress is not allowed: %s", [rc.address])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	rc.type == "aws_vpc_security_group_ingress_rule"
	not is_delete_action(rc.change.actions)
	rc.change.after.cidr_ipv4 == "0.0.0.0/0"
	msg := sprintf("public IPv4 ingress is not allowed: %s", [rc.address])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	rc.type == "aws_vpc_security_group_ingress_rule"
	not is_delete_action(rc.change.actions)
	rc.change.after.cidr_ipv6 == "::/0"
	msg := sprintf("public IPv6 ingress is not allowed: %s", [rc.address])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	rc.type == "aws_security_group"
	not is_delete_action(rc.change.actions)
	ingress := rc.change.after.ingress[_]
	cidr := ingress.cidr_blocks[_]
	cidr == "0.0.0.0/0"
	msg := sprintf("public IPv4 inline ingress is not allowed: %s", [rc.address])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	rc.type == "aws_security_group"
	not is_delete_action(rc.change.actions)
	ingress := rc.change.after.ingress[_]
	cidr := ingress.ipv6_cidr_blocks[_]
	cidr == "::/0"
	msg := sprintf("public IPv6 inline ingress is not allowed: %s", [rc.address])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	not is_delete_action(rc.change.actions)
	tags := object.get(rc.change.after, "tags", object.get(rc.change.after, "tags_all", null))
	tags != null
	object.get(tags, "Project", "") == ""
	msg := sprintf("missing or empty Project tag: %s", [rc.address])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	not is_delete_action(rc.change.actions)
	tags := object.get(rc.change.after, "tags", object.get(rc.change.after, "tags_all", null))
	tags != null
	object.get(tags, "Environment", "") == ""
	msg := sprintf("missing or empty Environment tag: %s", [rc.address])
}

deny contains msg if {
	rc := input.resource_changes[_]
	rc.mode == "managed"
	not is_delete_action(rc.change.actions)
	tags := object.get(rc.change.after, "tags", object.get(rc.change.after, "tags_all", null))
	tags != null
	object.get(tags, "ManagedBy", "") == ""
	msg := sprintf("missing or empty ManagedBy tag: %s", [rc.address])
}
