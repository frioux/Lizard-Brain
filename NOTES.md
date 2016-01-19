# Lizard-Brain Design Doc

## Impules

Impules are inputs to the Lizard Brain.  Currently to send data to the Lizard
Brain you simply write JSON to a pipe that the Lizard Brain reads.  Some (all?)
impules will need a corresponding action to allow reactions.

Some obvious impules are:

 * CGI
 * SMS
 * Email

## Actions

Actions come in two flavors; one-off and persistent.  Persistent actions run
forever and watch a pipe that the Lizard Brain writes to.  One-off actions get
spawned on demand, do their work, and exit.

Some obvious actions are:

 * CGI
 * SMS
 * Email
 * Remind (probably via Pushover)

## State

The Lizard Brain stores undelivered data (data that actions have not yet
acknowledged?) in a SQLite table.  Actions are assumed to do something similar
until they complete their work.

## Reactions

To support responding to queries there are special actions called "reactions."
The general idea is that an impulse can register a temporary action which will
count as the reaction to that impulse.  Often the impulse will either not need
to do this as the reaction will simply be an action.  Sometimes though, like
with CGI, the only kind of action that can be taken is responding to an
outstanding request, so the CGI impulse will need to register an action based on
the inbound request.  I suppose this will simply be done with a UUID or
something.

# Tasks

Tasks are the interpretation of the content of the impulse.  So while an impulse
might be SMS, a task might be a reminder set via SMS, and there would be a
reaction ("ok, I'll remind you!") and an action (the reminder sent, presumably
via SMS, at a given time.)

Flow:

 * SMS Impulse from frew: "Remind me to get milk tonight"
 * Lizard Brain Receives:
   * Impulse Handle
   * Reaction Handle
   * "Remind me to get milk tonight"
 * Reminder task recognizes the "Remind" prefix and consumes the impulse
 * Reminder task writes: "Ok, I'll remind you" to the reaction handle
 * Reminder task sets some internal timestamp for tonight to send "get milk"
   to me.

Impulses are just programs writing to the Lizard Brain impulse pipe.
Tasks are small programs that exit non-zero if they recognize their
input.  Maybe depending on their output LB can keep running tasks?

# Example Flow

SMS Impulse writes the following to `./pipes/lizard-brain`:

```
From: SMS/my-number
Reaction: SMS/my-number

remind me to get gas at 5pm
```

Lizard-Brain (which is really just a ghetto router) writes the above to each
task until one exits 0 or 1: `./tasks/remind`:

```
From: SMS/my-number
Reaction: SMS/my-number

remind me to get gas at 5pm
```

And the response is:

```
Session: SMS/my-number:truncate(md5sum($reminder),4)
Reaction: SMS/my-number

Ok, I'll remind you to get gas today at 5pm [truncate(md5sum($reminder),4)]
```

Lizard-Brain notes that there is a Session and thus will prioritize the remind
action when getting messages from SMS/my-number.

Next, presumably today at 5, the remind task will write to `./pipes/SMS` to
(hopefully) resolve this session:

```
Destination: SMS/my-number # can be overridden by using the `via` keyword

get gas [truncate(md5sum($reminder), 4)]
```

The session will remain open for a given timeout and automatically close if
nothing happens after that, which will put the remind task back at it's normal
priority.  To close it sooner, I could respond to the text with either simply
"OK" or "OK truncate(md5sum($reminder), 4)", which is important if
disambiguation needs to happen, otherwise it will be the most recent one or
something.
