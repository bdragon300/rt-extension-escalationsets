package RT::Action::EscalationSets;

use 5.010;
use strict;
use warnings;

use base qw(RT::Action);
use Date::Manip::Date;
use RT::Interface::Email;

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

    ## Check escalation sets:
    unless (exists $config->{'EscalationSets'}->{$escalation_set}) {
        RT::Logger->error("[RT::Extension::EscalationSets]: Unknown escalation set passed: '$escalation_set'");
        return 0;
    }

    ## Check configured Date::Manip:
    ## TODO This could throw 2 warnings:
    ## 'Odd number of elements in hash assignment…' and
    ## 'Use of uninitialized value in list assignment…'
    # my %dateConfig = RT->Config->Get('DateManipConfig');
    # ## TODO Does not work:
    # unless (%dateConfig) {
    #     RT::Logger->error('Config: Date::Manip\'s configuration not set.');
    #     return 0;
    # }

    return 1;
}


=head2 Commit

After preparation this method commits the action.


=cut

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
    my $new_eset_data = $config->{'EscalationSets'}->{$new_eset};
    my $old_eset_data = $config->{'EscalationSets'}->{$old_eset}
        if exists($config->{'EscalationSets'}->{$old_eset});
        
    unless($old_eset_data && $old_eset) {
        RT::Logger->notice("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . " has unknown escalation set: '$old_eset'");
    }

    RT::Logger->debug(Dumper $new_eset_data);
    RT::Logger->debug(Dumper $old_eset_data);

    # Default escalation level
    my $default_lvl = $new_eset_data->{'_default_level'} 
        if exists($new_eset_data->{'_default_level'}) || '';
    my $old_lvl = $ticket->FirstCustomFieldValue($lvl_cf) || '';
    
    # Set new escalation level to the default if no level was set before
    # If both are empty we imply that ticket was not passed
    if ($old_lvl ne $default_lvl) {
        $new_lvl = $default_lvl;
        
    } elsif ( ! $old_eset_data) {
        RT::Logger->notice("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": CF." . $lvl_cf . " has unknown escalation level: " . $old_lvl . '. Will be corrected');
        $new_lvl = $default_lvl;
        
    # $new_lvl will be calculated later
    } else {
        $new_lvl = $old_lvl;
    }

    # Retrieve data from old and new levels
    my $old_level_data = $old_eset_data->{$old_lvl} 
        if exists($old_eset_data->{$old_lvl});

    # Retrieve (intervals) from config
    my $old_due_conf = '';
    if (exists($old_eset_data->{'_due'})) {
        my @k = grep{ exists $old_eset_data->{'_due'}->{$_} } @ticket_date_attrs;
        $old_due_conf = $old_eset_data->{'_due'}->{$k[0]};
    }
    my $new_due_conf = '';
    if (exists($new_eset_data->{'_due'})) {
        my @k = grep{ exists $new_eset_data->{'_due'}->{$_} } @ticket_date_attrs;
        $new_due_conf = $new_eset_data->{'_due'}->{$k[0]};
    }
    

    ## Update escalation set CF if necessary
    if ($old_eset ne $new_eset)
    {
        my ($res, $msg) = $ticket->AddCustomFieldValue(Field => $eset_cf, Value => $new_eset);
        if ($res) {
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": CF." . $eset_cf . " changed " . $old_eset . " -> " . $new_eset);
        } else {
            RT::Logger->error("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": unable to set CF." . $eset_cf . ": " . $msg);
            return 0;
        }
    }


    ## Calculate new Due value
    my $new_due = $self->calculate_due(
        $old_eset,
        $old_due_conf,
        $new_eset,
        $new_due_conf,
        $ticket,
        $self->get_due_unset_txn
    );
    # Write new Due to the ticket
    if (defined $new_due) {
        my $s = RT::Extension::EscalationSets::dm_to_str($new_due, DATE_FORMAT);
        if ($s ne $ticket->Due) {
            my ($res, $msg) = $ticket->SetDue($s);
            unless ($res) {
                RT::Logger->error("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": unable to set Due: " . $msg);
                return 0;
            }
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": Due set to " . $s);
        }
    }


    ## Create some Date::Manip objects
    # NOW
    my $now = new Date::Manip::Date;
    $now->parse('now');
    #
    # Ticket date attributes
    my %ticket_dates = map{ $_ => RT::Extension::EscalationSets::str_to_dm($ticket->_Value($_)) } @ticket_date_attrs;
    #
    # Create hash {lvl => Date::Manip::Date} for new escalation set
    my %eset_expired_dates = ();
    foreach my $l (keys %$new_eset_data) {
        # Date attributes in level definition
        my @lvl_attrs = grep{exists $new_eset_data->{$l}->{$_}} @ticket_date_attrs; 
        if (scalar(@lvl_attrs) > 1) {
            RT::Logger->notice('[RT::Extension::EscalationSets]: Escalation level $l in set $new_eset has multiple dates. Will be used: ' . $lvl_attrs[0]);
        } elsif ( ! @lvl_attrs) {
            RT::Logger->error('[RT::Extension::EscalationSets]: Escalation level $l in set $new_eset has no correct date name. Abort');
            return 0;
        }
        my $lvl_attr = $lvl_attrs[0];
        
        # No need to compare with unset value
        unless ($ticket_dates->{$lvl_attr}->printf("%s")) {
            next;
        }
        
        my $dlt = $ticket_dates->{$lvl_attr}->new_delta();
        my $res = $dlt->parse($new_eset_data->{$l}->{$lvl_attr});
        if ($res == 1) {
            RT::Logger->error("[RT::Extension::EscalationSets]: Config: Cannot parse escalation time value '" . $new_eset_data->{$l} . "' in " . $new_eset . ':' . $l);
            return 0;
        }
        $eset_expired_dates{$l} = $ticket_dates->{$lvl_attr}->calc($dlt);
    }

    ## Calculate new escalation level
    # Sort all escalation lvls by dates (only in past) descending
    # The first element will contain needed escalation set
    my @past = grep { $eset_expired_dates{$_}->cmp($now) < 0 } 
        sort { $eset_expired_dates{$b}->cmp($eset_expired_dates{$a}) }
        keys %eset_expired_dates;
    $new_lvl = $past[0] || $new_lvl;

    ## Write escalation level if needed
    if ($old_lvl ne $new_lvl) {
        my ($val, $msg) = $ticket->AddCustomFieldValue(Field => $lvl_cf, Value => $new_lvl);
        if ($val) {
            RT::Logger->info("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ': CF.' . $lvl_cf . " changed " . $old_lvl . ' -> ' . $new_lvl);
        } else {
            RT::Logger->error('[RT::Extension::EscalationSets]: Ticket #' . $ticket->id . ': could not set escalation level: ' . $msg);
            return 0;
        }

    } else {
        RT::Logger->debug("[RT::Extension::EscalationSets]: Ticket #" . $ticket->id . ": escalation level not changed");
    }
    return 1;
}

sub calculate_due {
    my $self = shift;
    my $old_eset = shift; #string
    my $old_due_delta = shift; #string
    my $new_eset = shift; #string
    my $new_due_delta = shift; #string
    my $ticket = shift;
    my $due_unset_txn = shift;

    my $new_due = undef;

    if ($ticket->Due eq NOT_SET
        || $new_eset ne $old_eset)
    {
        if ($old_due_delta)
        {
            $new_due = $self->timeline_due($old_due_delta, $ticket, $due_unset_txn); #Due that would be with old eset

            if ($new_eset ne $old_eset
                && $new_due->printf("%s") != 0) # epoch != 0
            {
                if ($ticket->Due eq NOT_SET 
                    && ! defined $due_unset_txn) 
                {
                    # > Due is empty and has never set. 
                    # Usually when escalation passes through ticket for the first time
                    if ($new_eset ne "") {
                        $new_due = undef; #Do nothing
                        RT::Logger->warning("Ticket #" . $ticket->id . ": Ticket spent unknown time in previous escalation set");
                    }
                    if ($ticket->Created eq NOT_SET) { # Something wrong
                        $new_due = undef; #Do nothing
                        RT::Logger->warning("Ticket #" . $ticket->id . ": Cannot calculate Due because Created is empty");   
                    }

                } elsif ($new_eset ne "") {

                    # Add the difference between new escalation set and old one to new Due value
                    # Performs when escalation set has changed from previous check (ticket moves to another set)
                    # Also both old and new sets must have _dueinterval parameter
                    if ($new_due_delta)
                    {
                        # Calculate difference between _dueintervals in new escalation set and old one
                        # Then add the result to Due
                        $new_due = $new_due->calc(
                            $self->esets_delta($old_due_delta, $new_due_delta),
                            0
                        );

                    } else {
                        $new_due = undef; #Do nothing
                        RT::Logger->warning("Ticket #" . $ticket->id . ": Ticket spent unknown time in previous escalation set");
                    }

                } else {
                    # > previous escalation set is empty in any case (except first time pass)
                    $new_due = undef; #Do nothing
                    RT::Logger->debug("Ticket #" . $ticket->id . ": Unknown previous escalation set and Due was touched sometime. Make no changes");
                }
            }

        } elsif ($ticket->Due ne NOT_SET) {
            $new_due = new Date::Manip::Date;
            $new_due->parse(NOT_SET); #Unset Due

            if ($new_eset eq "") {
                $new_due = undef; #Do nothing
                RT::Logger->warning("Ticket #" . $ticket->id . ": Ticket spent unknown time in previous escalation set");
            }
        }
    }
    return $new_due;
}

sub timeline_due {
    #Calculates Due based on config delta or last Due, excluding escalation set transitions

    my $self = shift;
    my $config_delta = shift; #string, i.e. "3 minutes"
    my $ticket = shift;
    my $txn = shift; #Last Due unset transaction

    my $timezone = RT->Config->Get('Timezone');

    # NOW
    my $now = new Date::Manip::Date;
    $now->parse("now");

    my $new_due = new Date::Manip::Date;
    $new_due->config('setdate', 'zone,UTC');
    $new_due->parse(NOT_SET);

    if ( ! defined $config_delta
        || $config_delta eq "")
    {
        return $new_due;
    }

    my $calc_base = $now->new_date();
    my $delta = $calc_base->new_delta();
    $delta->parse($config_delta);

    if ($ticket->Due ne NOT_SET) {
        $new_due->parse($ticket->Due);
        return $new_due;

    } elsif (defined $txn) {
        # Based on last Due value (before as it was unset)

        # Calculate how much time left to Due when Due has unset last time
        # and write NOW+difference to Due

        if ($txn->OldValue gt $txn->Created) {
            my $txn_old = $self->str_to_dm($txn->OldValue, $timezone);
            my $txn_created = $self->str_to_dm($txn->Created, $timezone);
            $delta = $txn_old->calc($txn_created, 1);

        } else { # Out of SLA
            $delta = undef;
            $new_due->parse($txn->OldValue);
            return $new_due;
        }

    } else { # Due based on config
        return undef if $ticket->Created eq NOT_SET; # Something wrong

        $calc_base = $self->str_to_dm($ticket->Created, $timezone);
        $delta = $calc_base->new_delta();
        $delta->parse($config_delta);
    }
    
    $new_due = $calc_base->calc($delta, 0);

    return $new_due;
}

sub esets_delta {
    my $self = shift;
    my $old_due = shift;
    my $new_due = shift;

    # NOW
    my $now = new Date::Manip::Date;
    $now->parse("now");

    my $old_delta = $now->new_delta()->parse($old_due);
    my $new_delta = $now->new_delta()->parse($new_due);
    return $new_delta->calc($old_delta, 1); # Date::Manip::Delta
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

#sub get_ticket_attr_dm {
#    my ($self, $attr, $ticket) = @_;
#    
#    return (undef) unless ($ticket->_Accessible($attr, 'read'));
#    return RT::Extension::EscalationSets::str_to_dm($ticket->_Value($attr));
#}


1;