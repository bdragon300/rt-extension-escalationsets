# Summary

RT::Extension::EscalationSets - Highly configurable SLA and escalation with 
business hours.

# Key features

* Tracks SLA time and sets proper Escalation Level CF value at the right 
moment
* Several SLA levels can have completely different escalation levels in each one
(use business time or not, even inside one SLA service type)
* SLA service type can be applied to tickets based on conditions such as 
TicketSQL (you can have different SLA and escalation timeouts inside one queue, 
say, based on incident priority. Or the one SLA and escalation only for 
certain tickets in different queues)
* Moving a ticket between different SLA levels is supported. All dates and
escalation levels will be recalculated automatically
* Automatic recalculation Due field (if used) after SLA time stopped in the past

This extension is cron-based, the rt-crontool utility is used.

# Installation

Dependencies:

* RT >= 4.2.0
* Date::Manip >= 6.25

Commands to install:

  perl Makefile.PL

  make
  
  make install

If you install this extension for the first time, you must to add needed objects
to the database:

  make initdb

Be careful, run the last command one time only, otherwise you can get duplicates
in the database.

# Overview

The extension defines two concepts: Escalation Set and Escalation Level. They 
are controled by two CFs with the same names, created by `make initdb` command.

Each Set includes one or more Levels and optionally can include information to
manipulate SLA time. Also, each Level, SLA time can use business time.

Each ticket, "seen" by the Action, has certain Set and Level values in CFs, that
set automatically. 

Escalation Level value is changed during the ticket lifetime. Such changes
timeouts defined inside Set config.

Escalation Set value writes initially and can be changed when ticket "migrates"
from one Set to another one.

If SLA time is defined in Set then Action tracks SLA on the tickets, belongs
to this Set.

# Description

## What is Escalation Set?

Central concept is Escalation Set. In few words: escalation timeouts + SLA 
time.

Each Set consists of:

1. Escalation Levels. Required. Each Level has field name and timedelta. Field
can be one of the standard ticket date fields, such as Due, Created, Starts,
etc. Timedelta points to a time moment when a ticket must be escalated to
this Level.
2. Default Level. Writes to the Escalation Level CF when the ticket has not 
escalated yet. Also uses on ticket "migration" between Sets.
3. Default "Due" field timedelta. If this parameter is present then
Due will be set initially. Also it uses to calculate right Due on SLA interrupt
and transfer to another Escalation Set. If absent then calculating of Due 
ignores.
4. Business time definition (Date::Manip config). Can be HASH or filename. 
If present then you can use 'business' word in Set's timedeltas. Also can be
filename.

All parts are optional except Levels. See example below for more info.

## How extension works?

### Ticket selection

Firstly, the EscalationSet Action must "see" this ticket. In case of the 
rt-crontool this means the ticket meets the --search, --condition restrictions.

Next, the Set name must be passed as Action arg.

Example. Suppose you have different timeouts for management incident escalation 
depending on incident's InitialPriority. In this case you can define 
the Set with desired timeouts and SLA time inside. Next, add rt-crontool command 
to the crontab using EscalationSets action with your Set as argument and search 
param with TicketSQL that matches to incidents with given InitialPriority.

```
rt-crontool --search RT::Search::FromSQL --search-arg "Status=__Active__ AND Queue='support' AND CF.Interaction_type='incident' AND Priority = '40'" --action RT::Action::EscalationSets --action-arg 'Incident40'
```

### Brand new ticket

If ticket previously was not "seen" by the EscalationSets ("Escalation Set" CF 
is empty) then the Action does following:

* Escalation Set name will be written to 'Escalation set' CF
* If due timedelta is present in Set's config then ticket's Due will be 
calculated and written
* If Default Level is present in Set's config then it is written to 
"Escalation Level" CF

### Periodical check and escalation

Escalation is just "Escalation level" CF value change process from one level 
to another. That is it. The Extension does not additional work during
escalation process (such sending email or modifying the ticket). But you can 
create some Scrips, that, for example, send correspondence or something else.

Escalation is caused by the rt-crontool. For each ticket the Action calculates 
which level must be the current and writes it to "Escalation level" CF if 
needed.

During every check the Action also tracks Set change and SLA interruption. See
below.

## SLA interruption

The EscalationSets does not interrupt SLA itself by some events. SLA must be 
interrupted by another Scrips/Extensions.

SLA time is usually controlled by Due field. Typically this field contains time 
when the ticket must be resolved. If Due is unset then SLA is considered as 
interrupted. While this is so, the Action must not "see" the ticket.

When the Action will have "seen" the ticket it will resume SLA time which means
the new Due value. The value will be: 
`Due = NOW + (last_Due_value - unset_due_time)`. In other words, remained SLA 
time will be added to now moment.

If due option in Set config is omitted then SLA continuation ignores.

## Moving ticket between Sets

Its possible to "migrate" a ticket from one Set to another. Movings between 
Sets with different business time, or with and without business time, are 
supported.

This feature can suitable when, for instance, support engineer can increase
incident priority during problem analysis. Or when a ticket, initially 
errorneously classified as incident, must be an RFS and you fix this mistake. 
It's ok, but the RFS uses business time (technology management escalation), 
when incident does not use it (24/7/365 support management escalation).
In these examples the escalation timeouts have to be changed and SLA
time have to be calculated properly.

Technically such ticket "migrating" means the Action have seen the ticket whose
"Escalation Set" CF (old Set) has different value than passed to Action as 
argument (new Set). In this case the following happens:

* If new Set has no defined SLA inside ("due" parameter is absent) then Due 
is not touched.
* Otherwise:
  * Remained SLA timedelta takes from a last Due unset transaction 
  (last_Due_value - unset_due_time)
  * It is converted from an old Set business time (if any) to a new Set 
  business time (if any)
  * Next, Due field is written as `Due = NOW + new_timedelta`
* New Set is written to the Escalation Set CF
* Finally, current escalation level recalculates according a new Set and it is
written to the "Escalation Level" CF. If no escalation should happen yet
according the new Set then the "default_level" value will be written. If
"default_level" is absent then "Escalation Level" CF will be unset.

If either new or old Set has not using business time then timedelta calculates
using linear time.

## Business time remark

If some time calculation result falls on non-business time (holidays for 
example) then it will be moved to the first business minute.

Example. Suppose we have business day 9:00-17:00. SLA time is 1 hour. If the
ticket was created on 16:01, then Due will be set on 9:01 of the next business
day.

# Configuration

RT_SiteConfig.pm configuration options.

### $EscalationField

```
Set($EscalationField, 'Escalation Level');
```

Required. Name of CF with current Escalation Level. `make initdb` creates
"Escalation Level" CF.

### $EscalationSetField

```
Set($EscalationSetField, 'Escalation set');
```

Required. Name of CF with current Escalation Set. `make initdb` creates
"Escalation set" CF.

### %EscalationSets

```
Set(%EscalationSets, (...));
```

Required. Escalation Sets definition.

Example:

```
Set(%EscalationSets, (
'Incident' => {
    'levels' => {
        'reaction' => {created => '15minutes'},
        '1' => {due => '-24 minutes'},
        '2' => {due => '-12 minutes'},
        '3' => {due => '-5 minutes'},
    },
    'due' => {created => '94 hours'},
    'default_level' => '0'
},
'RFS' => {
    'levels' => {
        '1' => {due => '-288 business minutes'},
        '2' => {due => '-192 business minutes'},
        '3' => {due => '-96 business minutes'},
    },
    'due' => {started => '32 business hours'},
    'default_level' => '0',
    'datemanip_config' => {
        WorkDayBeg => '09:00',
        WorkDayEnd => '17:00',
        WorkWeekBeg => 1,
        WorkWeekEnd => 5
    }
},
));
```

Each escalation set has a name (passed as Action parameter) and can
contain following parameters:

* "levels", required. It contains any Escalation Levels (can contain no levels,
which means no escalation). Some remarks about Levels:
  * Inside each level there is specified from which field it will be counted.
  Possible values are equal to ticket date fields: Due, Started, Created, etc.
  See RT::Ticket docs.
  * Timedelta is a string expression (see Date::Manip::Delta::parse docs).
  Negative timedelta means "Before date", positive - "After date". E.g. if Due
  set to 10:00, level is {due => "-7 minutes"}, then level will be reached 
  in 09:53.
  * If timedelta contains word "business" then it uses business time from 
  "datemanip_config" parameter.
* "due", optional. If specified this timedelta will be used to track SLA (see
above). The format as same as levels definition.
* "default_level", optional. If present then this value will be written to
"Escalation Level" CF initially, when no Level is active, i.e. ticket was not
escalated yet.
* "datemanip_config", optional. This hash is passed as parameter for 
Date::Manip library configuration. It can contain either business time directly
or specify the config filename. For full options list see Date::Manip::Config
docs.

# Helper methods

You can use following helper methods while making you own Scrips or Templates.

### RT::Ticket::get_datemanip_date

`RT::Ticket::get_datemanip_date(field, escalation_set=CURRENT) -> Date::Manip::Date object`

Returns Date::Manip::Date object configured for given escalation_set with value
of field.

Template example:

```
Ticket was started at:
{$Ticket->get_datemanip_date('started')->printf("%c")}
```

### RT::Ticket::get_datemanip_delta

`RT::Ticket::get_datemanip_delta(field, escalation_set=CURRENT, base=NOW) -> Date::Manip::Delta object`

Returns Date::Manip::Delta object configured for given escalation_set with value
of field. By default the delta counts from NOW moment, but you can pass custom 
Date::Manip::Date object as base. (result = field_value - base)

Template example:

```
Ticket was started {$Ticket->get_datemanip_date('started')->printf("%sv")} seconds ago
```

### RT::Ticket::get_datemanip_worktime

`RT::Ticket::get_datemanip_worktime() -> Date::Manip::Delta object`

Returns Date::Manip::Delta object configured for current ticket escalation set.

This method counts time the ticket spent in work starting from the field 
specified in "due" parameter in ticket's Escalation Set config. If "due" is 
omitted then "Started" field is used.

Unlike the other time calculation methods this method walks through 
Due set/unset transactions in ticket and totalizes all SLA time chunks into one
timedelta. This delta is returned as configured Date::Manip::Delta object.

Template example:

```
Ticket was started {$Ticket->get_datemanip_worktime()->printf("%sv")} seconds ago
```

# Example

All tickets that come to your company's support divide on three interaction 
types:

* RFS - Request For Service. Executed by second line support engineers or 
admins. Their business time: 7:00-21:00, 7/365 days.
* RFI - Request For Information. Executed by manager. Business time: 
9:00-17:00, mon-fri, including holidays.
* Incident - When some of the services (or all ones) are degraded. Incident can
have priority 10 or 20 depending on problem seriousness. Can be executed by 
support engineers or admins. No business time, 24/7/365.

SLA:

* RFS - 48 business hours, answer not later then 5 business minutes
* RFI - 90 business hours, answer not later then 5 business minutes
* Incident - depending on service degrade level (30 minutes or 90 minutes), 
answer not later then 5 minutes

Escalation levels:

* RFS
  * 'chief' (10 business hours) - notify chief@example.com
  * 'CTO' (20 business hours) - notify above cto@example.com
* RFI
  * 'managers' (30 business hours) - notify manager2@example.com
* Incident
  * priority<10
    * 1 (10 minutes) - notify support_shift@example.com
    * 2 (15 minutes) - notify above + chief@example.com
    * 3 (20 minutes) - notify above + cto@example.com
  * priority>=10
    * 1 (30 minutes) - notify support_shift@example.com
    * 2 (45 minutes) - notify above + chief@example.com
    * 3 (60 minutes) - notify above + cto@example.com

Let's consolidate wrote above to EscalationSets config:

```
Set(%EscalationSets, (
'RFS' => {
    'levels' => {
        'reaction' => {created => '5minutes'},
        'chief' => {due => '-38 business hours'},
        'CTO' => {due => '-28 business hours'},
    },
    'due' => {started => '48 business hours'},
    'datemanip_config' => {
        WorkDayBeg => '07:00',
        WorkDayEnd => '21:00',
        WorkDay24Hr => 1
    }
},
'RFI' => {
    'levels' => {
        'reaction' => {created => '5minutes'},
        'managers' => {due => '-60 business hours'},
    },
    'due' => {started => '90 business hours'},
    'datemanip_config' => {
        ConfigFile => '/opt/rt4/etc/Managers_Workday.conf'
    }
},
'Incident10' => {
    'levels' => {
        'reaction' => {created => '5minutes'},
        '1' => {started => '10 minutes'},
        '2' => {started => '15 minutes'},
        '3' => {started => '20 minutes'},
    },
    'default_level' => '0'
},
'Incident20' => {
    'levels' => {
        'reaction' => {created => '5minutes'},
        '1' => {started => '30 minutes'},
        '2' => {started => '45 minutes'},
        '3' => {started => '60 minutes'},
    },
    'default_level' => '0'
},
));
```

Add following tasks to crontab:

```
* * * * * /opt/rt4/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND CF.Type = 'RFS'" --action RT::Action::EscalationSets --action-arg 'RFS'
* * * * * /opt/rt4/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND CF.Type = 'RFI'" --action RT::Action::EscalationSets --action-arg 'RFI'
* * * * * /opt/rt4/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND CF.Type = 'Incident' AND Priority <= 10" --action RT::Action::EscalationSets --action-arg 'Incident10'
* * * * * /opt/rt4/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND CF.Type = 'Incident' AND Priority > 10" --action RT::Action::EscalationSets --action-arg 'Incident20'
```

Now we've got just "Escalation Level" CF value changing on proper moments. Now
we need to do smth during change.

Scrip Condition example for, say, RFS "chief" Level:

```
my $elvl_cf = $self->TicketObj->LoadCustomFieldByIdentifier(RT->Config->Get('EscalationField'));

$self->TransactionObj->Field == $elvl_cf->id
&& $self->TransactionObj->NewValue eq 'chief'
&& $self->TicketObj->FirstCustomFieldValue(RT->Config->Get('EscalationSetField')) eq 'RFS';
```

Other Scrips are made similarly. You can use the single Scrip for all 
escalations, everything is depended on your tasks.

