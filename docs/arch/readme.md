# Architecture Decision Records

_ADR_ for short.

## What is an Architecturally Significant Decision?

See [Documenting Architecture
Decisions](http://thinkrelevance.com/blog/2011/11/15/documenting-architecture-decisions)
for more information.

The basic idea is to capture key decisions having to do with anything _architectural_
in a way that promotes better communication than simple word-of-mouth.

What is an _architectural_ decision?  If one or more of the following ideas apply you
might be dealing with an architectural decision.

Does the design decision...

* Alter externally visible system properties?
* Modify public interfaces?
* Directly influence high priority quality attributes?
* Include or remove dependencies?
* Result from a discussion where you learned more about technical or business constraints?
* Involve taking on strategic technical debt?
* Change the structures of the system (static, dynamic, or physical)?
* Require other developers to update construction techniques or development environments?


## Template

Use this template in any new ADRs.  Replace the help text as you write the ADR.

```
# ADR N: Brief Decision Title

Context goes here.

Describe the forces at play, including technological, political, social, and project local.
These forces are likely in tension, and should be called out as such. The language in this
section is value-neutral. It is simply describing facts.

## Decision

This section describes our response to these forces. It is stated in full sentences,
with active voice. "We will ..."


## Status

choose one: [Proposed | Accepted | Deprecated | Superseded]

if deprecated, include a rationale.

If superseded, include a link to the new ADR


## Consequences

Describe the resulting context, after applying the decision. All consequences should be listed here,
not just the "positive" ones. A particular decision may have positive, negative, and neutral consequences,
but all of them affect the team and project in the future.
```

## Tips and Hints

* Titles should be descriptive, concise, and precise
* The whole document should be one or two pages long at most.
* Think of the document as a conversation with a future developer. This means write well and use full
  sentences.
* Update consequences as they become known.  The ADR becomes like a diary for seeing how the design
  decisions we make impact the system over time.
* Include diagrams as necessary.


## References

Nygard, Michael. Documenting Architecture Decisions, from _Think Relevance_ blog. [Web](http://thinkrelevance.com/blog/2011/11/15/documenting-architecture-decisions)

Kruchten, Philippe. _The Decision View's Role in Software Architecture Practice_, IEEE Software 26:36-42, February 2009

Tyree, J. and Akerman, A. _Architecture Decisions: Demystifying Architecture_, IEEE Software 22:2:19-27, March-April 2005 [PDF](http://www.utdallas.edu/~chung/SA/zz-Impreso-architecture_decisions-tyree-05.pdf)
