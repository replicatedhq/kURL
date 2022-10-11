# ADR 4: Installer objects validation/linter

kURL Installer objects validation is currently spread across multiple systems, i.e. we don't have a centralized place for this logic to live in.
This can bring inconsistencies and extra work for the team whenever a certain change needs to be implemented.

Due to the complex nature of the kURL Installer objects their validation is executed by a mix of `jsonschema` and `javascript` code, the first is a lightweight means of checking if a struct complies with a set of basic rules while the latter is used for evaluating the more complex rules or corner cases involved.

We have looked into a few options to provide a single way of covering the simple and complex validation scenarios:

### Move the `javascript` logic into a more advanced `jsonschema` document

This is possible as `jsonschema` provides us with `if-then-else` syntax. There were some drawbacks of this approach, the main one being that [jsonschema](https://json-schema.org/specification.html) specification does not provide an official way of defining custom error messages for the user.

### Implement a homebrewed linter service

Developing such a service from scratch would give us total freedom to address our complex cases but would require extra work and would invariably generate more code for the team to maintain.

Another drawback of this approach is that the result would not be a declarative document (most of the logic would be implemented by the code responsible for the service).

### Use [rego](https://www.openpolicyagent.org/docs/latest/policy-language/)

Rego is the language used by [OPA](https://www.openpolicyagent.org/) to declare policies that will, later on, be applied on top of JSON objects. It has an interpreter written in Go and gives both simplicity and freedom for expressing more complex cases.

Kots-lint, one of our projects that need to validate Installer objects, already uses `rego` for validations so integration would not be a problem.

## Decision

We will use [rego](https://www.openpolicyagent.org/docs/latest/policy-language/) to validate kURL Installer objects.
The frontend validation will be possible by employing an HTTP endpoint. 

## Status

Accepted

## Consequences

- A HTTP endpoint will need to be implemented to allow Installer object validations from kurl.sh page.
- Resulting `rego` rules will need to be used on to `kots-lint` project.
- Any host preflight validation executed on top of the Installer object will need to be re-evaluated.
