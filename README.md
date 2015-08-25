# Summary

EscalationSets allows to escalate tickets and to apply different SLA depending on TicketSQL conditions.

# Description

Central concept is "set", that logically groups SLA time and escalation levels with their timeouts. You can apply different escalation sets to tickets depending on things in --search or --condition in rt-crontool, such as TicketSQL or Overdue. So you can tune ticket escalation more particularly.

The extension checks tickets periodically (via rt-crontool) using name of set passed as argument. If necessary the escalation process will be performed automatically to reach needed level. Extension can write comment, send email about level change. Each level can calculate based on Created, Due ticket fields.
Current escalation level and set store in appropriate Custom Fields. 

Also the extension can set Due field for each set separately (if specified in config). If ticket will move to another escalation set then Due will be recalculated. If Due was set before extension "saw" the ticket then it doesn't touch Due anymore but escalation will work. This allows specify another Due value manually or by another scrip, for example.

The extension supports pausing SLA time (such as stalled status, etc.). When ticket goes into "paused" state the Due must be unset and then the extension must not "see" the ticket until it will come from "paused" state. When this happened the Due automatically recalculated.

You can create set that will not use Due. In this case the escalation will be performed simply based on Created (**_dueinterval** is not specified, see below). "Pausing" tickets will not support, i.e. SLA time will be continuous.

# Installation

Dependencies:

* RT >= 4.2.0
* Date::Manip >= 6.25

Commands to install:

  perl Makefile.PL
  make
  make install

If you install this extension for the first time, you must to add needed objects to the database:

  make initdb

Be careful, run the last command one time only, otherwise you can get duplicates in the database.

# Configuration

RT_SiteConfig.pm configuration options.

### $EscalationField

```
Set($EscalationField, 'Escalation Level');
```

Required. Name of CF that will store current ticket escalation level. Initial data creates 'Escalation Level' CF.

### $EscalationSetField

```
Set($EscalationSetField, 'Escalation set');
```

Optional. Name of CF that will store current ticket escalation set. Initial data creates 'Escalation set' CF.
Default: 'Escalation set'.

### $DefaultEscalationValue

```
Set($DefaultEscalationValue, '0');
```

Optional. Initial value for *$EscalationField*. If not specified then no default value will write.
Default: nothing.

### $EscalationEmailFrom

```
Set($EscalationEmailFrom, 'rt-escalation@example.com');
```

Optional. Must be specified if email action specified (see below).
Default: nothing.

### %EscalationSets

```
Set(%EscalationSets, (...));
```

Required. Defines escalation sets.
Value has following structure:

`<set_name> => {<escalation_level> => {<time_moment> => 'time_value'}, ...}, ...`

* *`<set_name>`* uses as name of set in rt-crontool
* *`<escalation_level>`* writes to $EscalationField as current level
* *`<time_moment>`* can be
    * **due** - time_value counted from Due
    * **created** - time_value counted from ticket creation time
* *'time_value'* can be **'2 minutes'**, **'4hours'**, **'1 day 4 hours 32 minutes'**. Also value can be negative **'-40 minutes'** that means BEFORE *`<time_moment>`* unlike positive **'40 minutes'** that means AFTER *`<time_moment>`*. See Date::Manip::Delta docs for more info.

In *`<escalation_level>`* special keys also can be specified (not interpret as level):

* **_dueinterval** - when extension will passes ticket for the first time it also will set Due. *`<time_moment>`* possible values: **created**.

### %EscalationActions

```
Set(%EscalationActions, (...));
```

Required. Defines actions that must be performed on every escalation level.
Value has following structure:
`<escalation_level> => {<action> => <param>, ...}, ...`

* *`<escalation_level>`* - when ticket escalates to this level the specified actions will be performed
* *`<action>`* can be:
    * **notify** - send email to comma-separated RT users, RT groups (names or ids). User has priority over group if they has the same names or ids. Email sending transaction will not be recorded. Uses 'Escalation Email' template
    * **comment** - write comment. `<param>` can be 1 or 0. Uses 'Escalation Comment' template

# Templates

Initial data contains following templates:

* *Escalation Email* - uses when sending emails
* *Escalation Comment* - uses to write comment to ticket

Each template receives following variables:

* *$Ticket* - RT::Ticket obj
* *$EscalationLevel* - new escalation level
* *$DeadlineType* - *`<time_moment>`* of current escalation level (**created**, **due**)
* *$DueInterval* - **_dueinterval** value for current escalation set. If no specified then undef.
* *$Created*, *$Due* - Date::Manip::Date object with appropriate values
* *$CreatedDelta*, *$DueDelta* - Date::Manip::Delta between NOW and appropriate value

# Example

Initial configuration:

```
Set($EscalationField, 'Escalation Level');
Set($EscalationEmailFrom, 'rt-escalation@example.com');
```

Let's define two escalation sets:

* RFI (Request for information) - 2 escalation levels
* incident - 3 escalation levels

```
Set(%EscalationSets, (
    'RFI' =>      {'1' => {due => '-4 hours 50 minutes'},
                   '2' => {due => '-2 hours 7 minutes'},
                   '_dueinterval' => {created => '32 hours'}
                  },
    'incident' => {'1' => {due => '-30 minutes'},
                   '2' => {due => '-25 minutes'},
                   '3' => {due => '-15 minutes'},
                   '_dueinterval' => {created => '1 hour'}
                  },
));
```

All levels counting from Due and specify as "x minutes left before Due". For RFI tickets Due will be set to +32 hours from created time, for incident +1 hour from created time.

Now what we want to do on each escalation process?

```
Set(%EscalationActions, (
        '1' => {'notify' => 'support'},
        '2' => {'notify' => 'managers,john', "comment" => 1},
        '3' => {'notify' => 'boss,109', "comment" => 1},
));
```

Here we notify specified RT users and groups. On 2 and 3 level the comment to ticket also will be added.

Now we can use rt-crontool to call this extension periodically. Add to crontab following:

```
* * * * * /usr/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND Queue == 'support' AND CF.Type = 'RFI'" --action RT::Action::EscalationSets --action-arg 'RFI'
* * * * * /usr/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND Queue == 'support' AND CF.Type = 'Incident'" --action RT::Action::EscalationSets --action-arg 'incident'
```

Now for different types of tickets different SLA will be applied.