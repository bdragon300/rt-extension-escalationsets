package RT::Action::EscalationSets;

use 5.010;
use strict;
use warnings;

use base qw(RT::Extension::EscalationSets RT::Action);
use Date::Manip::Date;
use RT::Interface::Email;

our $VERSION = '0.2';


=head1 NAME

C<RT::Action::EscalationSets> - Makes check accordingly passed escalation set on
each of given tickets. If its time to do escalation for the ticket then does it.

=head1 DESCRIPTION

This Action uses fields:

=over

=item CF with current escalation level ($EscalationField in config);

=item CF with current escalation set ($EscalationSetField in config);

=item Due (if specified in config for current escalation set/level).

=back

Escalation set can be with specified B<_dueinterval> key (Due-like) and not. In
first case it will use Due to escalate and you can specify escalation time based
on Due. In second case ticket can escalate based only Created.

Common rules are: 

=over 

=item When ticket in paused Status (stalled, etc.) then Due must be empty (some
Scrip can do that);

=item When ticket goes from paused Status then Due recalculates again based on last
Due value (Due-like sets only);

=item Actual set/value are always write in appropriate custom fields when extension
passes the ticket;

=item Ticket can go from Due-like to non-Due-like. Not conversely, because in this
case we cannot correctly calculate Due. Of course, ticket can go 
Due-like -> Due-like and non-Due-like -> non-Due-like sets;

=item If escalation set has changed then Due must be also recalculated (between 
Due-like sets);

=item If ticket has another Due before EscalationSets firstly saw it and the current
set is Due-like then Due will not be recalculated. This allows set another Due
to some tickets.

=back

Extension tests ticket's fields (Created, Due) and determines whether its time
to escalate ticket and to what level. On escalation configured actions will be
performed (send email, write comment to the ticket). Next actual set and level
will be wrote to approrpiate CustomFields.

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>


=head1 BUGS

Please report any bugs or feature requests to the L<author|/"AUTHOR">.


=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.


=head1 METHODS


=head2 Prepare

Before the action may be L<commited|/"Commit"> preparation is needed: Has RT
already been configured for this action? Has the needed custom field been
created yet?


=cut

sub Prepare {
    my $self = shift;

    my $ticket = $self->TicketObj;
    my $escalationSet = $self->Argument;

    ## Check escalation sets:
    my %escalationSets = RT->Config->Get('EscalationSets');
    unless (exists $escalationSets{$escalationSet}) {
        $RT::Logger->error("Unable to find escalation set in config: $escalationSet");
        return 0;
    }

    ## Check escalation actions:
    my $escalationActions = RT->Config->Get('EscalationActions');
    unless ($escalationActions) {
        $RT::Logger->error('Config: No EscalationActions defined');
        return 0;
    }
    

    ## Check configured default escalation value:
    # my $defaultPriority = RT->Config->Get('DefaultEscalationValue');
    # unless (defined $defaultPriority) {
    #     $RT::Logger->error('Config: DefaultEscalationValue not set.');
    #     return 0;
    # }

    ## Check configured Date::Manip:
    ## TODO This could throw 2 warnings:
    ## 'Odd number of elements in hash assignment…' and
    ## 'Use of uninitialized value in list assignment…'
    # my %dateConfig = RT->Config->Get('DateManipConfig');
    # ## TODO Does not work:
    # unless (%dateConfig) {
    #     $RT::Logger->error('Config: Date::Manip\'s configuration not set.');
    #     return 0;
    # }

    ## Check custom field:
    my $cfLvl = RT->Config->Get('EscalationField');
    unless ($cfLvl) {
        $RT::Logger->error('Config: EscalationField not set.');
        return 0;
    }

    ## Validate custom field:
    my $cf = RT::CustomField->new($RT::SystemUser);
    $cf->LoadByName(Name => $cfLvl);
    unless($cf->id) {
        $RT::Logger->error(
            'Custom field "' . $cfLvl . '" is unknown. Have you created it yet?'
        );
        return 0;
    }

    ## Validate custom field:
    my $cfSet = RT->Config->Get('EscalationSetField') || "Escalation set";
    $cf = RT::CustomField->new($RT::SystemUser);
    $cf->LoadByName(Name => $cfSet);
    unless($cf->id) {
        $RT::Logger->error(
            'Custom field "' . $cfSet . '" is unknown. Have you created it yet?'
        );
        return 0;
    }

    return 1;
}


=head2 Commit

After preparation this method commits the action. Returns 1 if everything is
good. Calls by RT itself.

=cut

sub Commit {
    my $self = shift;
    my $escalationSet = $self->Argument;

    # Read configuration
    my $cfLvl = RT->Config->Get('EscalationField');
    my $cfSet = RT->Config->Get('EscalationSetField') || "Escalation set";
    my $defaultLvl = RT->Config->Get('DefaultEscalationValue');
    my %esets = RT->Config->Get('EscalationSets');
    my $timezone = RT->Config->Get('Timezone') || 'UTC';

    # Ticket fields
    my $ticket = $self->TicketObj;
    my %ticketdate = (
        'created' => $ticket->Created,
        'due' => $ticket->Due,
    );
    my $lvl = $ticket->FirstCustomFieldValue($cfLvl);
    my $set = $ticket->FirstCustomFieldValue($cfSet) || "";

    ## MySQL date time format:
    my $format = '%Y-%m-%d %T';

    ## UNIX timestamp 0:
    my $notSet = '1970-01-01 00:00:00';

    ####

    $defaultLvl = "" unless (defined $defaultLvl);
    $lvl = "" unless (defined $lvl);
    my $newLvl = $lvl;
    $newLvl = $defaultLvl if ($lvl eq "" && $defaultLvl ne "");

    my $eset = $esets{$escalationSet};
    if ($lvl ne $defaultLvl
        && ! exists $eset->{$lvl}) 
    {
        $RT::Logger->warning("Ticket #" . $ticket->id . ": CF." . $cfLvl . " has unknown escalation level: " . $lvl);
    }

    # Special values in escalation set
    my %esetspecial = (
        '_dueinterval' => $eset->{'_dueinterval'},
    );
    #delete $eset->{$_} for keys %esetspecial;

    my %ticketdateobj = ();
    for (keys %ticketdate) {
        $ticketdateobj{$_} = $self->newDateObj($ticketdate{$_}, $timezone);
    }

    # Update escalation set CF if necessary
    if ($set ne $escalationSet)
    {
        my ($res, $msg) = $ticket->AddCustomFieldValue(Field => $cfSet, Value => $escalationSet);
        if ($res) {
            $RT::Logger->info("Ticket #" . $ticket->id . ": CF." . $cfSet . " changed " . $set . " -> " . $escalationSet);
        } else {
            $RT::Logger->error("Ticket #" . $ticket->id . ": unable to set CF." . $cfSet . ": " . $msg);
        }
    }

    # Calculate new Due
    ## If Due is empty or ticket escalation set has changed from previous check
    if ($ticket->Due eq $notSet
        || $set ne $escalationSet)
    {
        my $newDueObj = undef;

        if (defined $esetspecial{'_dueinterval'}
            && ref($esetspecial{'_dueinterval'}) eq 'HASH'
            && exists($esetspecial{'_dueinterval'}->{'created'}))
        {
            my $lastDueUnsetTxn = $self->getLastDueUnsetTxn;
            $newDueObj = $self->calculateDue($esetspecial{'_dueinterval'}->{'created'}, $lastDueUnsetTxn);

            if ($set ne $escalationSet
                && $newDueObj->printf($format) ne $notSet)
            {
                if ($ticket->Due eq $notSet 
                    && ! defined $lastDueUnsetTxn) 
                {
                    # > Due is empty and has never set. 
                    # Usually when escalation passes through ticket for the first time
                    if ($set ne "") {
                        $newDueObj = undef;
                        $RT::Logger->warning("Ticket #" . $ticket->id . ": Ticket spent unknown time in previous escalation set");
                    }
                    if ($ticket->Created eq $notSet) {
                        $newDueObj = undef;
                        $RT::Logger->warning("Ticket #" . $ticket->id . ": Cannot calculate Due because Created is empty");   
                    }
                } elsif ($set ne "") {
                    # Add the difference between new escalation set and old one to new Due value
                    # Performs when escalation set has changed from previous check (ticket moves to another set)
                    # Also both old and new sets must have _dueinterval parameter

                    my $d1 = $ticketdateobj{'created'}->new_delta;
                    $d1->parse($esetspecial{'_dueinterval'}->{'created'});

                    if (exists($esets{$set})
                        && ref($esets{$set}) eq 'HASH'
                        && exists($esets{$set}->{'_dueinterval'})
                        && ref($esets{$set}->{'_dueinterval'}) eq 'HASH'
                        && exists($esets{$set}->{'_dueinterval'}->{'created'}))
                    {
                        # Calculate difference between _dueintervals in new escalation set and old one
                        # Then add the result to Due
                        my $d2 = $ticketdateobj{'created'}->new_delta;
                        $d2->parse($esets{$set}->{'_dueinterval'}->{'created'});
                        $newDueObj = $newDueObj->calc($d1->calc($d2, 1), 0);

                    } else {
                        $newDueObj = undef;
                        $RT::Logger->warning("Ticket #" . $ticket->id . ": Ticket spent unknown time in previous escalation set");
                    }
                } else {
                    # > previous escalation set is empty in any case (except first time pass)
                    $newDueObj = undef;
                    $RT::Logger->debug("Ticket #" . $ticket->id . ": Unknown previous escalation set and Due was touched sometime. Make no changes");
                }
            }

        } elsif ($ticket->Due ne $notSet) {
            $newDueObj = new Date::Manip::Date;
            $newDueObj->parse($notSet);

            if ($set eq "") {
                $newDueObj = undef;
                $RT::Logger->warning("Ticket #" . $ticket->id . ": Ticket spent unknown time in previous escalation set");
            }
        }

        if (defined $newDueObj) {
            if ($newDueObj->printf($format) ne $notSet) {
                $newDueObj->convert("UTC");
            }
            my $newdue = $newDueObj->printf($format);
            if ($newdue ne $ticket->Due) {
                my ($res, $msg) = $ticket->SetDue($newdue);
                unless ($res) {
                    $RT::Logger->error("Ticket #" . $ticket->id . ": unable to set Due: " . $msg);
                    return 0;
                }
                $RT::Logger->info("Ticket #" . $ticket->id . ": Due set to " . $newdue);

                $ticketdate{'due'} = $newdue;
                $ticketdateobj{'due'} = $self->newDateObj($ticketdate{'due'}, $timezone);
            }
        }
    }

    my $now = new Date::Manip::Date;
    $now->parse('now');

    # Create hash {lvl => Date::Manip::Date}
    my %deadlineType = ();
    my %expiredDates = ();
    foreach my $l (keys %$eset) {
        for (keys %ticketdate) {
            if ($eset->{$l}->{$_} && ! defined $esetspecial{$l}) {
                unless ($ticketdateobj{$_}->printf("%s")) { 
                    #$RT::Logger->warning('Ticket #' . $ticket->id . ': ' . ucfirst $_ . ' is empty, but specified in escalation ' . $escalationSet . ':' . $l);
                    next;
                }
                my $dlt = $ticketdateobj{$_}->new_delta();
                my $res = $dlt->parse($eset->{$l}->{$_});
                if ($res == 1) {
                    $RT::Logger->error("Config: Cannot parse escalation time value '" . $eset->{$l} . "' in " . $escalationSet . ':' . $l);
                    return 0;
                }
                $expiredDates{$l} = $ticketdateobj{$_}->calc($dlt);
                $deadlineType{$l} = $_;
            }
        }
    }

    # Determine whether its time to change escalation level CF
    # Sort all escalation lvls by dates (only in past) desc
    # The first element will contain escalation set ticket must have now
    my @past = grep { $expiredDates{$_}->cmp($now) < 0 } 
        sort { $expiredDates{$b}->cmp($expiredDates{$a}) }
        keys %expiredDates;
    # my @past = grep { $deltas{$_}->{'data'}->{'length'} < $nowDelta->{'data'}->{'length'} } # 
    #     sort { $deltas{$b}->{'data'}->{'length'} <=> $deltas{$a}->{'data'}->{'length'} }    # Kostyli-kostyliki, cmp() not properly works
    #     keys %deltas;
    $newLvl = $past[0] || $newLvl;

    if ($lvl ne $newLvl) {
        my ($val, $msg) = $ticket->AddCustomFieldValue(Field => $cfLvl, Value => $newLvl);
        unless ($val) {
           $RT::Logger->error('Ticket #' . $ticket->id . ': could not set escalation level: ' . $msg);
           return 0;
        }
        $RT::Logger->info("Ticket #" . $ticket->id . ': CF.' . $cfLvl . " changed " . $lvl . ' -> ' . $newLvl);

        # Perform escalation
        if ($newLvl ne $defaultLvl) {
            my $dueIntervalObj = $ticketdateobj{'created'}->new_delta;
            $dueIntervalObj->parse($esetspecial{'_dueinterval'}->{'created'});

            # What to pass to templates
            my %t = map { ucfirst $_  => $ticketdateobj{$_} } keys %ticketdate; # Date::Manip::Date objects: Created, Due
            my %d = map { ucfirst $_ . 'Delta' => $now->calc($ticketdateobj{$_}, 1) } keys %ticketdate; #CreatedDelta, DueDelta
            %t = (
                'Ticket' => $ticket,
                'EscalationLevel' => $newLvl,
                'DeadlineType' => $deadlineType{$newLvl},
                'DueInterval' => $dueIntervalObj,
                %t,
                %d
            );
            $self->{'templateArguments'} = \%t;

            my %escActions = RT->Config->Get('EscalationActions');
            $self->HandleActions($escActions{$newLvl}, $ticket);
        }

    } else {
        $RT::Logger->debug("Ticket #" . $ticket->id . ": escalation level not changed");
    }
    return 1;
}

=head2 calculateDue DELTA, TRANSACTION

Calculates Due value based on level definition due string (DELTA) in config.
TRANSACTION - last Due unset transaction or undef

Due simply calculates based on last Due value (NOW + value) or config string (Created + value)
Returns Date::Manip::Date obj. 

=cut

sub calculateDue {
    my $self = shift;
    my $delta = shift; #string, i.e. "-3 minutes"
    my $txn = shift; #Last Due unset transaction

    my $timezone = RT->Config->Get('Timezone');
    my $ticket = $self->TicketObj;

    # NOW
    my $nowObj = new Date::Manip::Date;
    $nowObj->parse("now");

    ## UNIX timestamp 0:
    my $notSet = '1970-01-01 00:00:00';

    ## MySQL date time format:
    my $format = '%Y-%m-%d %T';

    my $newDueObj = new Date::Manip::Date;
    $newDueObj->config('setdate', 'zone,UTC');
    $newDueObj->parse($notSet);

    if ( ! defined $delta
        || $delta eq "")
    {
        return $newDueObj;
    }

    if ($ticket->Due ne $notSet) {
        $newDueObj->parse($ticket->Due);
    } elsif (defined $txn) { # Due based on last Due value
        # Calculate how much time left to Due when Due has unset last time
        # and write NOW+difference to Due
        my $toldObj = $self->newDateObj($txn->OldValue, $timezone);
        my $tcreatedObj = $self->newDateObj($txn->Created, $timezone);
        my $deltaObj = $toldObj->calc($tcreatedObj, 1);

        if ($txn->OldValue gt $txn->Created) {
            $newDueObj = $nowObj->calc($deltaObj, 0);
        } else { # Out of SLA
            $newDueObj->parse($txn->OldValue);
        }

    } else { # Due based on config
        return $newDueObj if $ticket->Created eq $notSet;

        my $td = $self->newDateObj($ticket->Created, $timezone);
        my $dueIntervalObj = $td->new_delta() ;
        $dueIntervalObj->parse($delta);
        $newDueObj = $td->calc($dueIntervalObj, 0);
    }
    
    return $newDueObj;
}

=head2 getLastDueUnsetTxn

Returns RT::Transaction object

=cut

sub getLastDueUnsetTxn {
    my $self = shift;

    my $ticket = $self->TicketObj;

    ## UNIX timestamp 0:   
    my $notSet = '1970-01-01 00:00:00';

    my $txns = $ticket->Transactions;
    $txns->Limit(FIELD => 'Type', VALUE => 'Set', SUBCLAUSE => 'startschange');
    $txns->Limit(FIELD => 'Field', VALUE => 'Due', ENTRYAGGREGATOR => 'AND');
    $txns->Limit(FIELD => 'NewValue', VALUE => $notSet, ENTRYAGGREGATOR => 'AND');
    $txns->OrderBy(FIELD => 'id', ORDER => 'DESC');
    return $txns->First;
}

=head2 HandleActions ACTIONS, TICKETOBJ

Performs escalation actions listed in %EscalationActions config array
ACTIONS - hashref to current escalation level actions

=cut

sub HandleActions {
    my $self = shift;
    my $actions = shift;
    my $ticket = shift;

    my $ret = 1;

    # Notify principals by email
    if ($actions->{'notify'}) {
        my $principals = $actions->{'notify'};
        my $res = $self->SendEmail($principals);
        unless ($res) {
            $RT::Logger->error("Ticket #" . $ticket->id . ': unable to send notifications. Recipients: ' . join(',', @{$self->{'Emails'}}));
            $ret = 0;
        }
        if ($res) {
            $RT::Logger->info("Ticket #" . $ticket->id . ': Notifications successfully sended');
        }
    }

    # Write comment in ticket
    if ($actions->{'comment'}) {
        my $res = $self->WriteComment($ticket);
        unless ($res) {
            $RT::Logger->error("Ticket #" . $ticket->id . ': Unable to write comment');
            $ret = 0;
        }
        if ($res) {
            $RT::Logger->info("Ticket #" . $ticket->id . ': Comment successfully wrote');
        }
    }
    return $ret;
}

=head2 WriteComment TICKETOBJ

Writes comment to ticket

=cut

sub WriteComment {
    my $self = shift;
    my $ticket = shift;

    my $ctpl = RT::Template->new($self->CurrentUser );
    my $res = $ctpl->LoadGlobalTemplate('Escalation Comment');
    unless ($res) {
        $RT::Logger->error("Ticket #" . $ticket->id . ': unable to load template Escalation Comment');
        return 0;
    }
    my ($val, $msg) = $ctpl->Parse( %{ $self->{'templateArguments'} } );
    unless ($val) {
        $RT::Logger->error('Ticket #' . $ticket->id . ': could not parse Escalation Comment template: ' . $msg);
        return 0;
    }
    my ($trid, $trmsg, $trobj) = $ticket->Comment(
        MIMEObj => $ctpl->MIMEObj,
        TimeTaken => 0,
    );
    unless ($trid) {
        $RT::Logger->error("Ticket #" . $ticket->id . ': error while write comment: ' . $trmsg);
        return 0;
    }
    return 1;
}

=head2 SendEmail PRINCIPALS

Sends emails to PRINCIPALS (string)

=cut

sub SendEmail {
    my $self = shift;
    my $principals = shift; # String: "user1,user2,group"

    if ($principals) {
        $self->SetRecipients($principals);
        my $from = RT->Config->Get('CorrespondAddress');
        my $configFrom = RT->Config->Get("EscalationEmailFrom");
        $from = $configFrom if $configFrom;

        my $res = RT::Interface::Email::SendEmailUsingTemplate(
            'Template' => 'Escalation Email',
            'Arguments' => $self->{'templateArguments'},
            'To' => join(',', @{$self->{'Emails'}}),
            'From' => $from
        );
        return abs($res);
    }
    return 0;
}

=head2 SetRecipients PRINCIPALS

Converts PRINCIPALS string to destination email addresses list

=cut

sub SetRecipients {
    my $self = shift;

    my $arg = shift;
    foreach( $self->__SplitArg( $arg ) ) {
        $self->_HandleArgument( $_ );
    }

    $self->{'seen_ueas'} = {};

    return 1;
}

sub _HandleArgument {
    my $self = shift;
    my $instance = shift;

    if ( $instance !~ /\D/ ) {
        my $obj = RT::Principal->new( $self->CurrentUser );
        $obj->Load( $instance );
        return $self->_HandlePrincipal( $obj );
    }

    my $group = RT::Group->new( $self->CurrentUser );
    $group->LoadUserDefinedGroup( $instance );
    # to check disabled and so on
    return $self->_HandlePrincipal( $group->PrincipalObj )
        if $group->id;

    require Email::Address;

    my $user = RT::User->new( $self->CurrentUser );
    if ( $instance =~ /^$Email::Address::addr_spec$/ ) {
        $user->LoadByEmail( $instance );
        return $self->__PushUserAddress( $instance )
            unless $user->id;
    } else {
        $user->Load( $instance );
    }
    return $self->_HandlePrincipal( $user->PrincipalObj )
        if $user->id;

    $RT::Logger->error(
        "'$instance' is not principal id, group name, user name,"
        ." user email address or any email address"
    );

    return;
}

sub _HandlePrincipal {
    my $self = shift;
    my $obj = shift;
    unless( $obj->id ) {
        $RT::Logger->error( "Couldn't load principal #$obj" );
        return;
    }
    if( $obj->Disabled ) {
        $RT::Logger->info( "Principal #$obj is disabled => skip" );
        return;
    }
    if( !$obj->PrincipalType ) {
        $RT::Logger->crit( "Principal #$obj has empty type" );
    } elsif( lc $obj->PrincipalType eq 'user' ) {
        $self->__HandleUserArgument( $obj->Object );
    } elsif( lc $obj->PrincipalType eq 'group' ) {
        $self->__HandleGroupArgument( $obj->Object );
    } else {
        $RT::Logger->info( "Principal #$obj has unsupported type" );
    }
    return;
}

sub __HandleUserArgument {
    my $self = shift;
    my $obj = shift;
    
    my $uea = $obj->EmailAddress;
    unless( $uea ) {
        $RT::Logger->warning( "User #". $obj->id ." has no email address" );
        return;
    }
    $self->__PushUserAddress( $uea );
}

sub __HandleGroupArgument {
    my $self = shift;
    my $obj = shift;

    my $members = $obj->UserMembersObj;
    while( my $m = $members->Next ) {
        $self->__HandleUserArgument( $m );
    }
}

sub __SplitArg {
    return grep length, map {s/^\s+//; s/\s+$//; $_} split /,/, $_[1];
}

sub __PushUserAddress {
    my $self = shift;
    my $uea = shift;
    push @{ $self->{'Emails'} }, $uea unless $self->{'seen_ueas'}{ $uea }++;
    return;
}

1;