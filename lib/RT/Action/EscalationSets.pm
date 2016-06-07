package RT::Action::EscalationSets;

use 5.010;
use strict;
use warnings;

use base qw(RT::Action);
use Date::Manip::Date;
use RT::Extension::EscalationSets 
    qw/ str_to_dm  load_config /;

=head1 NAME

C<RT::Action::EscalationSets> - Do escalation with escalation set passed as parameter 

=head1 DESCRIPTION

This Action uses fields:

=over

=item CF with current escalation level ($EscalationField in config);

=item CF with current escalation set ($EscalationSetField in config);

=item Due (if specified in config for current escalation set/level).

=back

Common rules are: 

=over 

=item When ticket outside of SLA (stalled, etc.) then Due must be empty (some
Scrip can do that);

=item When ticket goes to SLA then Due recalculates again based on last
Due value (if 'due' is set in config);

=item Actual set/value are always write in appropriate custom fields when extension
passes the ticket;

=item If escalation set has changed then Due will be also recalculated (between 
Due-like sets);

=item You can set Due manually and escalation will be performed based on this value.

=back

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>


=head1 BUGS

Please report any bugs or feature requests to the L<author|/"AUTHOR">.


=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.

=cut

use Data::Dumper qw(Dumper);

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

## MySQL date time format:
use constant DATE_FORMAT => '%Y-%m-%d %T';

=head1 METHODS


=head2 Prepare

Preparation before Commit and pre-flight check. Calls by RT itself.

=cut

sub Prepare {
    my $self = shift;

    my $ticket = $self->TicketObj;
    my $escalation_set = $self->Argument;
    
    my $config = $self->{'escalation_set_config'} ||= load_config();
    unless($config) {
        RT::Logger->error("[RT::Extension::EscalationSets]: Incomplete configuration, see README");
        return 0;
    }

    unless (exists $config->{'EscalationSets'}->{$escalation_set}) {
        RT::Logger->error("[RT::Extension::EscalationSets]: Unknown escalation set passed: '$escalation_set'");
        return 0;
    }

    return 1;
}


=head2 Commit

After preparation this method commits the action. Returns 1 if everything is
good. Calls by RT itself.

=cut

sub Commit 
{
    my $self = shift;

    my $ticket = $self->TicketObj;
    my $config = $self->{'escalation_set_config'};
    my $now = str_to_dm(Val => 'now', ToTz => 'UTC');


    #
    # Init some config and ticket vars
    #

    # CF
    my $lvl_cf = $config->{'EscalationField'};
    my $eset_cf = $config->{'EscalationSetField'};

    # Escalation set
    my $new_eset = $self->Argument; # already validated
    my $old_eset = $ticket->FirstCustomFieldValue($eset_cf) // '';

    # Escalation set (Old and New) config
    my %eset_data = (
        $new_eset => $config->{'EscalationSets'}->{$new_eset},
        $old_eset => $config->{'EscalationSets'}->{$old_eset}
    );
    if ( ! $eset_data{$old_eset} 
        && $old_eset ne ''
    ) {
        RT::Logger->notice("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
            . " has unknown escalation set: '$old_eset'. Will be corrected");
    }


    # {eset => [date_key, due_config], ...}
    my %conf_due = ();
    foreach my $eset ( ($old_eset, $new_eset) ) {
        $conf_due{$eset} = undef;

        if (ref($eset_data{$eset}->{'due'}) eq 'HASH') {
            $conf_due{$eset} = [(%{$eset_data{$eset}->{'due'}})[0..1]]; # First hashref pair as arrayref
            
            unless ($ticket->_Accessible($conf_due{$eset}->[0], 'read')) {
                RT::Logger->error("[RT::Extension::EscalationSets]: Unable to use due date '" . $conf_due{$eset}->[0]
                    . "' in set $eset");
                return 0;
            }
        }
    }

    #
    # Change escalation set
    #

    $self->set_cf($eset_cf, $new_eset, $ticket)
        if ($old_eset ne $new_eset);


    #
    # Calculate Due
    #

    my $new_due = undef;
    if ( ($ticket->Due eq NOT_SET && exists($conf_due{$new_eset}))
        || $old_eset ne $new_eset )
    { # User specified 'due' in config
        $new_due = $self->timeline_due(
            $conf_due{$old_eset} || $conf_due{$new_eset},
            $eset_data{ $conf_due{$old_eset} ? $old_eset : $new_eset }->{'datemanip_config'} || undef,
            $self->get_due_unset_txn($ticket),
            $now,
            $ticket
        );
        RT::Logger->debug("[RT::Extension::EscalationSets]: Due was calculated before possible changing: "
            . ($new_due ? $new_due->printf(DATE_FORMAT) : 'undef'));
    }
    if ($old_eset ne $new_eset
        && $old_eset ne ''
        && exists($conf_due{$new_eset}))
    {
        # Correct Due if escalation set is changing
        $new_due = $self->eset_change_due(
            $new_due,
            $conf_due{$old_eset},
            $conf_due{$new_eset},
            $eset_data{$new_eset}->{'datemanip_config'} || undef,
            $ticket
        );
    }

    $self->set_due($new_due, $ticket)
        if $new_due;

    #
    # Calculate escalation level
    #

    # Returns hashref lvl=>expired_dm_obj or undef
    my $expired = $self->get_lvl_expired_dates(
        $eset_data{$new_eset}->{'levels'},
        $eset_data{$new_eset}->{'datemanip_config'},
        $ticket
    );
    my $lvl = $self->get_lvl($expired, $now)
        if $expired;

    # Default escalation level
    my $default_lvl = $eset_data{$new_eset}->{'default_level'} // '';

    # Old escalation level
    my $old_lvl = $ticket->FirstCustomFieldValue($lvl_cf) // '';
    if (exists($eset_data{$old_eset})
        && ! exists($eset_data{$old_eset}->{'levels'}->{$old_lvl})
        && $old_lvl ne $default_lvl
        && $old_lvl ne ''
    ) {
        RT::Logger->notice("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
            . " has unknown escalation level: '$old_lvl'. Will be corrected");
        $old_lvl = '';
    }

    # New = New or Old (if was set) or Default
    my $new_lvl = $lvl // $old_lvl;
    $new_lvl = $default_lvl
        if $new_lvl eq '';

    $self->set_cf($lvl_cf, $new_lvl, $ticket)
        if ($old_lvl ne $new_lvl);
    
    return 1;
}

=head2 timeline_due CONFIG, DMCONFIG, TXN, NOW, TICKET

Calculates Due date using either TXN or CONFIG_DELTA otherwise.

Receives:

=over

=item CONFIG - arrayref, [date_name, config_value]

=item DMCONFIG - hashref, Date::Manip config

=item TXN - RT::Transaction obj, last Due unset transaction

=item NOW - Date::Manip::Date obj

=item TICKET - RT::Ticket obj

=back

Returns:

=over

=item Date::Manip::Date obj - Due with DMCONFIG configuration

=item undef if error

=back

=cut

sub timeline_due 
{
    my $self = shift;
    my $config = shift; #arrayref, i.e. ['Created', '3 minutes']
    my $dm_config = shift; # Date::Manip config HASHREF
    my $txn = shift; #Last Due unset transaction
    my $now = shift;
    my $ticket = shift;

    my $new_due = str_to_dm(Val => NOT_SET, FromTz => 'UTC', Config => $dm_config);
        
    return (undef) unless ($config);

    my $calc_base = str_to_dm(Val => $now->printf(DATE_FORMAT), FromTz => 'UTC', Config => $dm_config);
        
    my $delta = undef;

    if (defined $txn) {
        # If ticket was not overdue
        # Due = Now + (Txn_due - Txn_created) 
        if ($txn->OldValue gt $txn->Created) {
            my $txn_old = str_to_dm(Val => $txn->OldValue, FromTz => 'UTC');
            my $txn_created = str_to_dm(Val => $txn->Created, FromTz => 'UTC');
            $delta = $txn_old->calc($txn_created, 1, 'business');

        # If ticket was overdue
        # Due = Txn_due
        } else { 
            $new_due->parse($txn->OldValue);
            return $new_due;
        }

    } else {
        # If Due unset and was not set before, ususally when ticket is seeing
        # Due = Start_ticket_date + Config_due
        my $ticket_date = $ticket->_Value($config->[0]);
        return (undef)
            if ( ! defined($ticket_date) || $ticket_date eq NOT_SET);

        $calc_base->parse($ticket_date);
        $delta = $calc_base->new_delta();
        $delta->parse($config->[1]);
    }
    
    # Perhaps fall to start of next business day
    $calc_base->next_business_day(0, 1);
    $new_due = $calc_base->calc($delta, 0, 'business');

    return $new_due;
}


=head2 get_due_unset_txn TICKET

Retrieves last Due unset transaction in ticket

Receives:

=over

=item TICKET - RT::Ticket obj

=back

Returns:

=over

=item RT::Transaction obj

=item undef if not found

=back

=cut

sub get_due_unset_txn 
{
    my $self = shift;
    my $ticket = shift;

    my $txns = $ticket->Transactions;
    $txns->Limit(FIELD => 'Type', VALUE => 'Set', SUBCLAUSE => 'startschange');
    $txns->Limit(FIELD => 'Field', VALUE => 'Due', ENTRYAGGREGATOR => 'AND');
    $txns->Limit(FIELD => 'NewValue', VALUE => NOT_SET, ENTRYAGGREGATOR => 'AND');
    $txns->OrderBy(FIELD => 'id', ORDER => 'DESC');
    return $txns->First;
}


=head2 eset_change_due DUE, OLD_DUE_DELTA, NEW_DUE_DELTA, NEW_DMCONFIG, NOW, TICKET

Corrects DUE according with changing escalation set.

Receives:

=over

=item DUE - Date::Manip::Date obj

=item OLD_DUE_DELTA - arrayref, [date_name, config_value]

=item NEW_DUE_DELTA - arrayref, [date_name, config_value]

=item NEW_DMCONFIG - hashref, will be applied after correction

=item TICKET - RT::Ticket obj

=back

Returns:

=over

=item Date::Manip::Date obj - DUE

=item undef if error

=back

=cut

sub eset_change_due 
{
    my $self = shift;
    my $due = shift;
    my $old_due_delta = shift; #arrayref, i.e. ['Created', '3 minutes']
    my $new_due_delta = shift; #
    my $new_dm_config = shift;
    my $ticket = shift;

    return (undef) unless $due;

    #Log msgs if necessary
    if ($ticket->Due ne NOT_SET) {

        unless ($old_due_delta) {
            $due = undef;
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
                . ": Due is present in ticket with unknown escalation set.");
        }
        unless ($new_due_delta) {
            $due->parse(NOT_SET);
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
                . ": Ticket going out of escalation");
        }

    }


    # Calculate difference between _due in new escalation set and old one
    # Then add the result to new Due value
    my $d1 = $self->esets_business_delta($old_due_delta, $new_due_delta, $new_dm_config, $ticket);
    
    $due->config(%{$new_dm_config})
        if ref($new_dm_config) eq 'HASH';
        
    # Both old and new dates will ALWAYS fall to start of next business day before calculation,
    # it's Date::Manip feature during business time calculations
    # TODO: consider due time remains when changing escalation set with different business hours
    $due = $due->calc($d1, 0, 'business')
        if $d1;

    return $due;
}


=head2 esets_business_delta OLD_CONFIG_DELTA, NEW_CONFIG_DELTA, NEW_DMCONFIG, TICKET

Returns Date::Manip::Delta difference between (NEW_CONFIG_DELTA - OLD_CONFIG_DELTA)

Receives:

=over

=item OLD_CONFIG_DELTA - arrayref, [date_name, config_value]

=item NEW_CONFIG_DELTA - arrayref, [date_name, config_value]

=item NEW_DMCONFIG - hashref, will be applied after correction

=item TICKET - RT::Ticket obj

=back

Returns:

=over

=item Date::Manip::Delta obj

=item undef if error

=back

=cut

sub esets_business_delta 
{
    my $self = shift;
    my $old_config_delta = shift;
    my $new_config_delta = shift;
    my $new_dm_config = shift;
    my $ticket = shift;

    use Date::Manip::Delta;
    my $old_delta = new Date::Manip::Delta;
    $old_delta->parse($old_config_delta->[1]);
    my $new_delta = new Date::Manip::Delta;
    $new_delta->parse($new_config_delta->[1]);
    
    return (undef)
        unless($old_delta && $new_delta);

    my $old_date = str_to_dm(Val => $ticket->_Value($old_config_delta->[0]), FromTz => 'UTC')
        if ($old_config_delta && $ticket->_Accessible($old_config_delta->[0], 'read'));
        
    my $new_date = str_to_dm(Val => $ticket->_Value($new_config_delta->[0]), FromTz => 'UTC', Config => $new_dm_config)
        if ($new_config_delta && $ticket->_Accessible($new_config_delta->[0], 'read'));

    return (undef)
        unless($old_date && $new_date);
    return (undef)
        if($old_date->printf(DATE_FORMAT) eq NOT_SET || $new_date->printf(DATE_FORMAT) eq NOT_SET);
    
    $old_date = $old_date->calc($old_delta, 0);
    $new_date = $new_date->calc($new_delta, 0);
    return $new_date->calc($old_date, 1, 'business');
}


=head2 get_lvl_expired_dates LVLS, DMCONFIG, TICKET

Returns dates on which each escalation level expire

Receives:

=over

=item LVLS - hashref, 'levels' => ... part of escalation set configuration

=item DMCONFIG - hashref, Date::Manip config that all dates must have

=item TICKET - RT::Ticket obj

=back

Returns:

=over

=item HASHREF - {lvl => Date::Manip::Date, ...}

=item undef if error

=back

=cut

sub get_lvl_expired_dates
{
    my $self = shift;
    my $lvls = shift; # Hashref 'levels'=> ... from config
    my $dm_config = shift;
    my $ticket = shift;

    my %recent = (); # lvl => expired_date
    foreach my $l (keys %$lvls) {
        my %ticket_dates;

        # Get ticket date attribute in level config
        my $date_attr = (keys %{$lvls->{$l}})[0]
            if ref($lvls->{$l}) eq 'HASH';
        unless ( $ticket->_Accessible($date_attr, 'read') ) {
            RT::Logger->error("[RT::Extension::EscalationSets]: "
                . "Unable to use attribute '$date_attr' in level $l");
            return 0;
        }

        $recent{$l} = undef;

        my $val = $ticket->_Value($date_attr);
        next if ( ! $val || $val eq NOT_SET);

        # Make Date::Manip::Date obj from ticket date
        unless(exists($ticket_dates{$date_attr})) {
            $ticket_dates{$date_attr} = str_to_dm( 
                Val => ( ($val) || NOT_SET ),
                FromTz => 'UTC', 
                Config => $dm_config 
            );
        }

        my $d = $ticket_dates{$date_attr}->new_delta();
        my $res = $d->parse($lvls->{$l}->{$date_attr});
        if ($res == 1) {
            RT::Logger->error("[RT::Extension::EscalationSets]: Cannot parse escalation time '"
                . $lvls->{$l}->{$date_attr} . "'");
            return 0;
        }

        $recent{$l} = $ticket_dates{$date_attr}->calc($d, 0);
    }

    return \%recent
        if %recent;

    return (undef);
}


=head2 get_lvl EXPIRED_DATES, NOW

Returns escalation level that have to be now. In other words "the most latter level in past".

Receives:

=over

=item EXPIRED_DATES - hashref, {lvl => Date::Manip::Date,...}, see get_lvl_expired_dates

=item NOW - Date::Manip::Date obj

=back

Returns:

=over

=item STRING - escalation level name

=item undef if no level came now

=back

=cut

sub get_lvl
{
    my $self = shift;
    my $expired_dates = shift; # Hashref lvl => expired_date
    my $now = shift;

    my @past = grep { $expired_dates->{$_}->cmp($now) < 0 } 
        sort { $expired_dates->{$b}->cmp($expired_dates->{$a}) }
        keys %$expired_dates;

    return $past[0]
        if @past;

    return (undef);
}


=head2 set_cf CF, VAL, TICKET

Sets CustomField value. Removes all previous values

Receives:

=over

=item CF - CustomField name

=item VAL - CustomField value

=item TICKET - RT::Ticket obj

=back

Returns:

=over

=item SCALAR

=back

=cut

sub set_cf
{
    my $self = shift;
    my $cf = shift;
    my $val = shift;
    my $ticket = shift;
    
    # Delete old values if needed
    # my $cf_vals = $ticket->CustomFieldValues($cf);
    # while(my $cf_val = $cf_vals->Next) {
    #     my ($res, $msg) = $ticket->DeleteCustomFieldValue( Field => $cf, ValueId => $cf_val->id );

    #     unless ($res) {
    #         RT::Logger->notice("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
    #             . ": Cannot delete value for CF.$cf : $msg");
    #     }
    # }
    
    my ($res, $msg) = $ticket->AddCustomFieldValue( Field => $cf, Value => $val );

    if ($res) {
        RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
            . ": CF.$cf value changed to '$val'");
    } else {
        RT::Logger->error("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
            . ": Cannot set CF.$cf : $msg");
    }
    return $res;
}


=head2 set_due VAL, TICKET

Sets Due value

Receives:

=over

=item VAL - Due value

=item TICKET - RT::Ticket obj

=back

Returns:

=over

=item SCALAR

=back

=cut

sub set_due
{
    my $self = shift;
    my $val = shift;
    my $ticket = shift;

    my $s = $val->printf(DATE_FORMAT);
    my ($res, $msg) = $ticket->SetDue($s);
    if ($res) {
        RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
            . ": Due set to " . $val->printf("%u"));
    } else {
        RT::Logger->error("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id
            . ": unable to set Due: " . $msg);
    }


    return $res;
}

1;