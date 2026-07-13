# Philosophy

## The premise

Your digital identity — your mail, your calendar, your code, your feeds, your files,
the credentials that act as you — currently lives as a tenant in other people's
buildings. Each landlord is benevolent until incentives shift, and the rent is paid
in data, attention, and lock-in. This project exists to give one person, and then
their family, and then anyone with a phone, a building of their own.

A sovereign node is a small constellation of services running on hardware you own
(or placement you chose), reachable through a front door you control, holding
secrets only you can read, described entirely by files in a git repository you host
yourself. It is your corner of the internet, with your name on the door.

## Sovereignty is credible exit, not total self-operation

We do not define sovereignty as running everything yourself. That definition
produced a decade of abandoned home servers and a mail-deliverability priesthood.
We define it as *credible exit*: for every dependency you keep — Gmail as a mail
edge, a frontier LLM API, a rented VPS, even this project itself — you must be able
to walk away without losing data, identity, or continuity. The Google bridge keeps
a local mirror of your mail. The VPS anchor is stateless and rebuilds in twenty
minutes. The domain is registered to you, at a registrar you chose. The software is
open source. Convenience is welcome; hostages are not.

A dependency with a rehearsed exit is a choice. A dependency without one is a leash.

## One stack, many placements

There are no product tiers, only placement decisions: where do your secrets live,
where does compute run, where does inference happen, where is the front door. The
placement manifest records these answers, and moving between answers is a migration
the system knows how to perform. Someone may start with everything in the cloud and
end, years later, with a box under the television and a model running on it. The
ladder matters more than any rung.

## Rings of trust

Every surface of the node belongs to a ring. Ring 0 is the operator alone: the LLM
gateway admin, the secrets, the infrastructure controls. Ring 1 is trusted people:
the shared calendar in edit mode, the photo library, the family's accounts. Ring 2
is the public internet: deliberately small, deliberately boring — a busy-only
calendar feed, a blog, a booking page. Exposure is a decision made per-route, in a
config file, under version control. The default answer to "should this be public"
is no.

## Agents are tenants, not owners

The bet of this project is that language-model agents finally make personal
infrastructure operable by non-experts: the agent is the sysadmin. But an agent is
also, functionally, a junior employee who can be socially engineered by any text it
reads. So the architecture is built on a hard line:

Agents advise; deterministic code enforces. An agent may draft a firewall rule,
propose a policy, prepare a migration — and a human approves it, and boring config
enforces it. No model ever sits in the authorization path of the front door. No
agent ever holds a provider API key, a vault credential, or the docker socket.
Agents receive scoped virtual keys, narrow service APIs that default to read-only,
and budgets. When (not if) one is fooled, the blast radius is a sandbox, not a life.

We enforce trust with networks and credentials, not with prompts and hope.

## Pull, not push

Where the node touches the attention economy, it inverts the relationship. Feeds
are aggregated by the node on your schedule, in chronological order, with no
ranking layer whose objective is your engagement. Publishing happens on your site
first and syndicates outward; platforms become distribution channels, not homes.
You visit the internet; it does not colonize you.

## Boring technology, honestly maintained

Every component choice favors the boring option: Caddy over clever, Postgres over
novel, WireGuard over proprietary, files-in-git over dashboards. Boring survives.
And boring has a new justification unique to this project: the sysadmin is a
language model, and models are deeply competent at exactly the mainstream formats
the world's training corpora are saturated with. Choosing elegant-but-exotic
abstractions degrades the agent that keeps the node alive; here, mainstream is a
feature.
And we are honest about the tax: a self-hosted system dies of neglect around month
six unless maintenance is nearly free. Automating that maintenance — backups that
run themselves, an ops agent that watches, updates, and explains — is not a
feature of this project; it is the project. A half-maintained sovereign node is
worse than the landlords it replaced.

## Non-goals

We are not building a platform that intermediates its users; the moment this
project holds anyone's domain, keys, or data hostage, it has failed by its own
definition. We are not maximizing agent capability; we are maximizing what agents
can safely be trusted with. We are not competing on features with the hyperscalers;
we are competing on a property they structurally cannot offer: that this is yours.
