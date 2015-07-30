# Summary

EscalationSets allows to escalate tickets and to apply different SLA depending on TicketSQL conditions.

# Description

Central concept is "set". It contains SLA time and escalation levels with their timeouts for tickets in this set. You can define TicketSQL expression and bind "set" with it, i.e. you can specify different SLA, for example, depending on CustomFields.

The extension calls periodically via rt-crontool to check SLA time of tickets using name of set passed as argument. If value in CF *$EscalationField* is empty then it fills by *$DefaultEscalationValue*. Also if Due is empty and **dueinterval** is specified (see below) then Due will be set. Next extension compares time of ticket (Created, Starts, etc.) and values in specified escalation set and performs escalation if necessary. When escalation performs some additional actions can be performed (send email, write comment). After this new escalation level will be writed to CF *$EscalationField*.

When ticket Starts changed then Due will be automatically recalculate.

# Installation

Dependencies:

* RT >= 4.2.0
* Date::Manip >= 6.25

*TODO: make, make install, initialdata*

# Configuration

RT_SiteConfig.pm configuration options.

### $EscalationField

```
Set($EscalationField, 'Escalation Level');
```

Required. Name of CF that will store current ticket escalation level. Initial data creates 'Escalation Level' CF.

### $DefaultEscalationValue

```
Set($DefaultEscalationValue, '0');
```

Required. Value that CF will have by default (before any escalations).

### $EscalationEmailFrom

```
Set($EscalationEmailFrom, 'rt-escalation@example.com');
```

Required if email action specified (see below).

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
  * **starts** - time_value counted from Starts
* *'time_value'* can be **'2 minutes'**, **'4hours'**, **'1 day 4 hours 32 minutes'**. Also value can be negative **'-40 minutes'** that means BEFORE *`<time_moment>`* unlike positive **'40 minutes'** that means AFTER *`<time_moment>`*. See Date::Manip::Delta docs for more info.

In *`<escalation_level>`* special keys also can be specified (not interpret as level):

* **dueinterval** - when extension will passes ticket for the first time it also will set Due. *`<time_moment>`* possible values: **starts**, **created**.

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
* *$DeadlineType* - *`<time_moment>`* of current escalation level (**created**, **starts**, **due**)
* *$DueInterval* - if **dueinterval** special key specified then this var contains Date::Manip::Delta object with that value
* *$Starts*, *$Created*, *$Due* - Date::Manip::Date object with appropriate values
* *$StartsDelta*, *$CreatedDelta*, *$DueDelta* - Date::Manip::Delta between NOW and appropriate value

# Scrips

*IncreaseDue* is a scrip that recalculates Due if Starts changes. For example, if Starts will be set to 2 days in future then Due also will be moved to future for 2 days.

# Example

Initial configuration:

```
Set($EscalationField, 'Escalation Level');
Set($DefaultEscalationValue, '0');
Set($EscalationEmailFrom, 'rt-escalation@example.com');
```

Let's define two escalation sets:

* RFI (Request for information) - 2 escalation levels
* incident - 3 escalation levels

```
Set(%EscalationSets, (
    'RFI' =>      {'1' => {due => '-4 hours 50 minutes'},
                   '2' => {due => '-2 hours 7 minutes'},
                   'dueinterval' => {created => '32 hours'}
                  },
    'incident' => {'1' => {due => '-30 minutes'},
                   '2' => {due => '-25 minutes'},
                   '3' => {due => '-15 minutes'},
                   'dueinterval' => {created => '1 hour'}
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

Now for different types of tickets defferent SLA will be applied.