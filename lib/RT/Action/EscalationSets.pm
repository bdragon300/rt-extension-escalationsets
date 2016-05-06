package RT::Action::EscalationSets;

use 5.010;
use strict;
use warnings;

use base qw(RT::Action);
use Date::Manip::Date;
use RT::Interface::Email;
use RT::Extension::EscalationSets;

our $VERSION = '0.2';
our $PACKAGE = __PACKAGE__;

=head1 NAME

C<RT::Action::EscalationSets> - Increment escalation custom field value based
on escalation settings and notify RT users and groups associated with 
escalation levels


=head1 DESCRIPTION

This Action launches periodically via rt-crontool and reads escalation custom
field of ticket. If ticket needs an escalation then this field is set to proper
level and RT group and users associated with the level will be notified.  It 
provides handling business hours defined in RT site configuration file.

=head1 AUTHOR

Igor Derkach, E<lt>id@miran.ruE<gt>


=head1 SUPPORT AND DOCUMENTATION

You can find documentation for this module with the C<perldoc> command.

    perldoc RT::Extension::EscalationSets


=head1 BUGS

Please report any bugs or feature requests to the L<author|/"AUTHOR">.


=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.


=head1 SEE ALSO

    RT
    Date::Manip
    RT::Extension::EscalationSets


=head1 API


=head2 Prepare

Before the action may be L<commited|/"Commit"> preparation is needed: Has RT
already been configured for this action? Has the needed custom field been
created yet?


=cut

use Data::Dumper qw(Dumper);

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

## MySQL date time format:
use constant DATE_FORMAT => '%Y-%m-%d %T';

my @ticket_date_attrs = qw/Told Starts Started Due Resolved LastUpdated Created/; 

sub Prepare {
    my $self = shift;

    my $ticket = $self->TicketObj;
    my $escalation_set = $self->Argument;
    
    my $config = $self->{'escalation_set_config'} ||= RT::Extension::EscalationSets::load_config();
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

After preparation this method commits the action.


=cut

#TODO: huge Commit function, need to be refactored
sub Commit {
    my $self = shift;
    my $ticket = $self->TicketObj;
    my $timezone = RT->Config->Get('Timezone') || 'UTC';
    my $config = $self->{'escalation_set_config'};


    ## Do retrieve info from config and ticket
    # CF
    my $lvl_cf = $config->{'EscalationField'};
    my $eset_cf = $config->{'EscalationSetField'};

    # Escalation set name
    my $new_eset = $self->Argument; # already validated
    my $old_eset = $ticket->FirstCustomFieldValue($eset_cf) || '';

    # Retrieve eset definitions
    my %eset_data = ($new_eset => $config->{'EscalationSets'}->{$new_eset});
    $eset_data{$old_eset} = $config->{'EscalationSets'}->{$old_eset}
        if exists($config->{'EscalationSets'}->{$old_eset});
        
    if ( ! $eset_data{$old_eset} && $old_eset) {
        RT::Logger->notice("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . " has unknown escalation set: '$old_eset'");
    }

    # Default escalation level
    my $default_lvl = $eset_data{$new_eset}->{'_default_level'} 
        if exists($eset_data{$new_eset}->{'_default_level'}) || '';
    my $old_lvl = $ticket->FirstCustomFieldValue($lvl_cf) // '';
    if ( ! defined($default_lvl)) {
        RT::Logger->error("[RT::Extension::EscalationSets]: Unable to get '_default_level' from escalation set '$new_eset'");
        return 0;
    }
    
    
    # Set new escalation level to the default if no level was set before
    # If both are empty we imply that ticket was not seen before by extension
    my $new_lvl = '';
    if ($old_lvl ne $default_lvl) {
        $new_lvl = $default_lvl;
        
    } elsif ( ! $eset_data{$old_eset}) {
        RT::Logger->notice("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": CF." . $lvl_cf . " has unknown escalation level: " . $old_lvl . '. Will be corrected');
        $new_lvl = $default_lvl;
        
    # $new_lvl will be calculated later
    } else {
        $new_lvl = $old_lvl;
    }


    # Retrieve data from old and new levels
    my %level_data = ($old_lvl => $eset_data{$old_eset}->{$old_lvl})
        if exists($eset_data{$old_eset}->{$old_lvl});

    # Retrieve (intervals) from config
    my %conf_due = ();
    if (exists($eset_data{$old_eset}->{'_due'})) {
        my @k = grep{ exists $eset_data{$old_eset}->{'_due'}->{$_} } @ticket_date_attrs;
        unless(@k) {
            RT::Logger->error("[RT::Extension::EscalationSets]: No suitable dates found in _due in level $old_lvl in set $old_eset");
            return 0;
        }
        $conf_due{$old_eset} = {
            Value => $eset_data{$old_eset}->{'_due'}->{$k[0]},
            Attribute => $k[0]
        };
    } else {
        $conf_due{$old_eset} = { Value => '' };
    }
    if (exists($eset_data{$new_eset}->{'_due'})) {
        my @k = grep{ exists $eset_data{$new_eset}->{'_due'}->{$_} } @ticket_date_attrs;
        unless(@k) {
            RT::Logger->error("[RT::Extension::EscalationSets]: No suitable dates found in _due in level $new_lvl in set $new_eset");
            return 0;
        }
        $conf_due{$new_eset} = {
            Value => $eset_data{$new_eset}->{'_due'}->{$k[0]},
            Attribute => $k[0]
        };
    } else {
        $conf_due{$new_eset} = { Value => '' };
    }
    
    ## Update escalation set CF if necessary
    $self->set_cf($ticket, $eset_cf, $new_eset)
        if ($old_eset ne $new_eset);

    # NOW Date::Manip obj
    my $now = RT::Extension::EscalationSets::str_to_dm(Val => 'now', ToTz => 'UTC');

    ## Calculate new Due value
    # Has old eset config
    my $new_due = $self->timeline_due(
        $conf_due{$old_eset}->{'Value'} || $conf_due{$new_eset}->{'Value'},
        $eset_data{ ($old_eset ne '') ? $old_eset : $new_eset }->{'_datemanip_config'} || undef,
        $ticket,
        $self->get_due_unset_txn,
        $now
    );
    # Possible correct Due if escalation set is changing
    if ( $conf_due{$old_eset}->{'Value'} ne $conf_due{$new_eset}->{'Value'} )
    {
        $new_due = $self->eset_change_due(
            $new_due,
            $conf_due{$old_eset}->{'Value'},
            $conf_due{$new_eset}->{'Value'},
            $eset_data{$new_eset}->{'_datemanip_config'} || undef,
            $ticket,
            $now
        );
    }
    
    # Write new Due to the ticket
    if (defined $new_due) {
        my $s = $new_due->printf(DATE_FORMAT);
        if ($s ne $ticket->Due) {
            my ($res, $msg) = $ticket->SetDue($s);
            unless ($res) {
                RT::Logger->error("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": unable to set Due: " . $msg);
                return 0;
            }
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": Due set to " . $new_due->printf("%u"));
        }
    }
    

    # Ticket date attributes
    my %ticket_dates = map{ $_ => (RT::Extension::EscalationSets::str_to_dm( Val => ($ticket->_Value($_) || NOT_SET ), FromTz => 'UTC' )) } 
        @ticket_date_attrs;
    map{ $_->config(%{$eset_data{$new_eset}->{'_datemanip_config'}}) }
        values %ticket_dates
        if ref($eset_data{$new_eset}->{'_datemanip_config'}) eq 'HASH';
#    my %ticket_deltas = map{ $_ => $ticket_dates{$_}->calc($now, 1) } 
#        grep{ defined($ticket->_Value($_)) && $ticket->_Value($_) ne NOT_SET }
#        @ticket_date_attrs;

    #
    # Create hash {lvl => Date::Manip::Date(expired)} for new escalation set
    my %eset_expired_dates = ();
    foreach my $l (keys %{$eset_data{$new_eset}}) {
        next if $l =~ /^_/;
        # Date attributes in level definition
        my @lvl_attrs = grep{ ref($eset_data{$new_eset}->{$l}) eq 'HASH' && exists($eset_data{$new_eset}->{$l}->{$_}) } @ticket_date_attrs;
        if (scalar(@lvl_attrs) > 1) {
            RT::Logger->notice("[RT::Extension::EscalationSets]: Escalation level $l in set $new_eset has multiple dates. Will be used: " . $lvl_attrs[0]);
        } elsif ( ! @lvl_attrs) {
            RT::Logger->error("[RT::Extension::EscalationSets]: Escalation level $l in set $new_eset has no correct date. Abort");
            return 0;
        }
        my $lvl_attr = $lvl_attrs[0];
        
        # Skip if appropriate date is unset
        unless ($ticket_dates{$lvl_attr}->printf("%s")) {
            next;
        }
        
        my $dlt = $ticket_dates{$lvl_attr}->new_delta();
        my $res = $dlt->parse($eset_data{$new_eset}->{$l}->{$lvl_attr});
        if ($res == 1) {
            RT::Logger->error("[RT::Extension::EscalationSets]: Config: Cannot parse escalation time value '" . $eset_data{$new_eset}->{$l} . "' in " . $new_eset . ':' . $l);
            return 0;
        }
        $eset_expired_dates{$l} = $ticket_dates{$lvl_attr}->calc($dlt, 0, 'business');
    }


    ## Calculate new escalation level
    # Sort all escalation lvls by dates (only in past) descending
    # The first element will contain needed escalation set
    my @past = grep { $eset_expired_dates{$_}->cmp($now) < 0 } 
        sort { $eset_expired_dates{$b}->cmp($eset_expired_dates{$a}) }
        keys %eset_expired_dates;
    $new_lvl = $past[0] || $new_lvl;

    ## Write escalation level if needed
    $self->set_cf($ticket, $lvl_cf, $new_lvl)
        if ($old_lvl ne $new_lvl);
    
    return 1;
}

# Calculates Due based on config delta or last Due for current (old) escalation set
sub timeline_due {
    my $self = shift;
    my $config_delta = shift; #string, i.e. "3 minutes"
    my $dm_config = shift; # Date::Manip config HASHREF
    my $ticket = shift;
    my $txn = shift; #Last Due unset transaction
    my $now = shift;

    my $timezone = RT->Config->Get('Timezone') // 'UTC';

    my $new_due = RT::Extension::EscalationSets::str_to_dm(Val => NOT_SET, FromTz => 'UTC');
    $new_due->config(%{$dm_config})
        if ref($dm_config) eq "HASH";
        
    unless ($config_delta) {
        $new_due = RT::Extension::EscalationSets::str_to_dm(Val => $ticket->Due, FromTz => 'UTC');
        $new_due->config(%{$dm_config})
            if ref($dm_config) eq "HASH";
        return $new_due;        
    }

    my $calc_base = RT::Extension::EscalationSets::str_to_dm(Val => $now->printf(DATE_FORMAT), FromTz => 'UTC');
    $calc_base->config(%{$dm_config})
        if ref($dm_config) eq "HASH";
        
    my $delta = undef;

    if ($ticket->Due ne NOT_SET) {
        $new_due->parse($ticket->Due);
        return $new_due;

    } elsif (defined $txn) {
        # If ticket was not overdue
        # Due = Now + (Txn_due - Txn_created) 
        if ($txn->OldValue gt $txn->Created) {
            my $txn_old = RT::Extension::EscalationSets::str_to_dm(Val => $txn->OldValue, FromTz => 'UTC');
            my $txn_created = RT::Extension::EscalationSets::str_to_dm(Val => $txn->Created, FromTz => 'UTC');
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
        return (undef) if $ticket->Created eq NOT_SET; # Something wrong

        $calc_base->parse($ticket->Created);
        $delta = $calc_base->new_delta();
        $delta->parse($config_delta);
    }
    
    # Perhaps fall to start of next business day
    $calc_base->next_business_day(0, 1);
    $new_due = $calc_base->calc($delta, 0, 'business');

    return $new_due;
}

sub eset_change_due {
    my $self = shift;
    my $due = shift;
    my $old_due_delta = shift; #string
    my $new_due_delta = shift; #string
    my $new_dm_config = shift;
    my $ticket = shift;
    my $now = shift;

    #Log msgs if necessary
    if ($ticket->Due eq NOT_SET) {

        unless ($new_due_delta) {
            $due->parse(NOT_SET);
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": Due is not set when going out of escalation by some reason.");
        }
        elsif ($old_due_delta && $new_due_delta ne $old_due_delta) {
            RT::Logger->warning("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": Due is unset when changing escalation set.");
        }

    } else {

        unless ($old_due_delta) {
            $due = undef;
            RT::Logger->warning("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": Due is set on ticket with no escalation set. Cannot calculate Due.");
        }
        unless ($new_due_delta) {
            $due->parse(NOT_SET);
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": Ticket going out of escalation");
        }

    }

    return (undef) unless $due;

    # Calculate difference between _due in new escalation set and old one
    # Then add the result to new Due value
    my $d1 = $self->esets_business_delta($old_due_delta, $new_due_delta, $now);
    
    $due->config(%{$new_dm_config})
        if ref($new_dm_config) eq 'HASH';
        
    # Both old and new dates will ALWAYS fall to start of next business day before calculation,
    # it's Date::Manip feature during business time calculations
    # TODO: consider due time remains when changing escalation set with different business hours
    $due = $due->calc($d1, 0, 'business')
        if $d1;

    return $due;
}

sub esets_business_delta {
    my $self = shift;
    my $old_config_delta = shift;
    my $new_config_delta = shift;
    my $now = shift;

    my $old_delta = $now->new_delta();
    $old_delta->parse($old_config_delta, 'business');
    my $new_delta = $now->new_delta();
    $new_delta->parse($new_config_delta, 'business');
    
    return $new_delta->calc($old_delta, 1) 
        if ($new_delta && $old_delta); # Date::Manip::Delta
    return (undef);
}


#sub date_delta_calc {
#    my $self = shift;
#    my $date = shift; # Date::Manip::Date obj
#    my $delta = shift; # string, for example "-3 minutes"
#    my $subtract = shift || 0;
#
#    my $delta_obj = $date->new_delta();
#    $delta_obj->parse($delta);
#    my $new_date = $date->new_date();
#    return $new_date->calc($delta_obj, $subtract);
#}

sub get_due_unset_txn {
    my $self = shift;

    my $ticket = $self->TicketObj;

    my $txns = $ticket->Transactions;
    $txns->Limit(FIELD => 'Type', VALUE => 'Set', SUBCLAUSE => 'startschange');
    $txns->Limit(FIELD => 'Field', VALUE => 'Due', ENTRYAGGREGATOR => 'AND');
    $txns->Limit(FIELD => 'NewValue', VALUE => NOT_SET, ENTRYAGGREGATOR => 'AND');
    $txns->OrderBy(FIELD => 'id', ORDER => 'DESC');
    return $txns->First;
}

sub set_cf
{
    my $self = shift;
    my $ticket = shift;
    my $cf = shift;
    my $val = shift;
    
    my ($res, $msg) = $ticket->AddCustomFieldValue(Field => $cf, Value => $val);
    if ($res) {
        RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": CF." . $cf . " changed to " . $val);
    } else {
        RT::Logger->error("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": unable to set CF." . $cf . ": " . $msg);
    }
    return $res;
}


#sub get_ticket_attr_dm {
#    my ($self, $attr, $ticket) = @_;
#    
#    return (undef) unless ($ticket->_Accessible($attr, 'read'));
#    return RT::Extension::EscalationSets::str_to_dm($ticket->_Value($attr));
#}


1;