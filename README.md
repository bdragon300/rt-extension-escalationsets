# Summary

RT::Extension::EscalationSets - Highly configurable escalation with business hours.

# Description

Central concept is "set", that logically groups SLA time and escalation levels
with their timeouts and can be assigned to ticket based on condition. You can
apply different escalation sets to tickets depending on things in --search or
--condition in rt-crontool, such as TicketSQL or Overdue. So you can tune
ticket escalation more particularly.

The extension checks tickets periodically (via rt-crontool) and does escalation
if necessary. Each level can be calculated based on Created, Due, Starts, etc.
ticket fields. Current escalation level and set store in appropriate Custom
Fields.

Business hours are supported and can be assigned to each set separately.

Also the extension can set Due field for each set separately (if specified in
config). If ticket will move to another escalation set then Due will be
recalculated. Also you can change Due manually and escalation will do based on
that value.

The extension supports pausing SLA time (such as stalled status, etc.). When
ticket goes into "paused" state the Due must be unset and then the extension
must not "see" the ticket until it will come from "paused" state. When this
happened the Due automatically recalculated.

You can create set that will not use Due. In this case the escalation will be
performed simply based on Created (due is not specified, see below). "Pausing"
tickets in this case will not support.

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

# Configuration

RT_SiteConfig.pm configuration options.

### $EscalationField

```
Set($EscalationField, 'Escalation Level');
```

Required. Name of CF that will store current ticket escalation level. Initial
data creates 'Escalation Level' CF.

### $EscalationSetField

```
Set($EscalationSetField, 'Escalation set');
```

Required. Name of CF that will store current ticket escalation set. Initial data
creates 'Escalation set' CF.

### %EscalationSets

```
Set(%EscalationSets, (...));
```

Required. Defines escalation sets.
Example:

```
Set(%EscalationSets, (
'Incident' => {
    'levels' => {
        'reaction' => {created => '15minutes'}
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
        WorkDayBeg => '08:00',
        WorkDayEnd => '17:00',
        WorkWeekBeg => 1,
        WorkWeekEnd => 5
    }
},
));
```

The setting contains escalation sets and their configuration. Some remarks:

* If 'due' parameter is set then Due field will be set;
* Levels and 'due' contain ticket date name that calculation will be referred.
  You can use any of ticket dates, such Created, Started, Due, etc. See
  RT::Ticket docs
* Negative delta means 'Before date', positive - 'After date'. I.e. if Due is
  10:00, value in config is '-7 minutes', then level will be reached in 09:53.
* 'default_level' will be set forcibly when Extension will have seen the ticket
  'for the first time. Omit if not needed.
* 'datemanip_config' contains Date::Manip configuration. Can be used to define
  'business time in set. See Date::Manip::Config documentation.

# Usage

RT::Action::EscalationSets can be called by rt-crontool:


```
* * * * * /usr/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND Queue == 'support' AND CF.Type = 'RFS'" --action RT::Action::EscalationSets --action-arg 'RFS'
* * * * * /usr/bin/rt-crontool --search RT::Search::FromSQL --search-arg "(Status = 'new' OR Status = 'open') AND Queue == 'support' AND CF.Type = 'Incident'" --action RT::Action::EscalationSets --action-arg 'Incident'
```

# Writing templates

There are some template methods:

* $Ticket->get_datemanip_date FIELD, [ESCALATION_SET=<current>] - returns
  Date::Manip::Date object for given ticket FIELD. Retrieves config from
  ESECALATION_SET. If not passed then use current ticket escalation set
* $Ticket->get_datemanip_delta FIELD, [ESCALATION_SET=<current>], [BASE=<now>] - returns
  Date::Manip::Delta object with difference between ticket FIELD value and BASE.
  Retrieves config from ESCALATION_SET. 
* $Ticket->get_datemanip_worktime - returns Date::Manip::Delta with time which ticket 
  spent in work. Note: if Due was changed manually sometime then result will
  not be correct because it calculates based on current escalation set and 
  contains difference between whole ticket time and remaining time.

## Fields change order is:

1. Escalation Set
2. Due
3. Escalation level

Thus, on the moment of changing escalation level, Escalation set and Due are known.

All dates are in UTC timezone. To convert to local one you can use:

```
$date_obj->convert("user");
```

For more info see Date::Manip::Date and Date::Manip:TZ documentation.

## Some useful code examples:

**Print time/date**

```
$date_obj->printf("%u");                 ## Full format date,time,zone
$date_obj->printf("%Y-%m-%d %T");        ## RT timedate format, useful to set datetime fields (ISO8601)
```

**Datetime calculation**

```
$date_result_obj = $date_obj->calc($delta_obj, 0);        ## date_result_obj = $date_obj + $delta_obj
$date_result_obj = $date_obj->calc($delta_obj, 1);        ## date_result_obj = $date_obj - $delta_obj
$delta_result_obj = $date_obj->calc($date2_obj, 0);       ## delta_result_obj = $date_obj + $date2_obj
$res = $result_obj->cmp($date_obj);                       ## result_obj <=> $date_obj
```
