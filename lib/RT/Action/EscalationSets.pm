package RT::Action::EscalationSets;

use 5.010;
use strict;
use warnings;

use base qw(RT::Action);
use Date::Manip::Date;
use RT::Interface::Email;

our $VERSION = '0.6';


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

sub Prepare {
    my $self = shift;

    my $ticket = $self->TicketObj;

    ## Check escalation sets:
    my $escalationSets = RT->Config->Get('EscalationSets');
    unless ($escalationSets) {
        $RT::Logger->error('Config: EscalationSets not set.');
        return 0;
    }

    ## Check escalation principals:
    my $escPrincipals = RT->Config->Get('EscalationPrincipals');
    unless ($escPrincipals) {
        $RT::Logger->error('Config: No EscalationPrincipals defined');
        return 0;
    }
    

    ## Check configured default escalation value:
    my $defaultPriority = RT->Config->Get('DefaultEscalationValue');
    unless (defined $defaultPriority) {
        $RT::Logger->error('Config: Default priority not set.');
        return 0;
    }

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
        $RT::Logger->error('Config: Priority field is not set.');
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

    return 1;
}


=head2 Commit

After preparation this method commits the action.


=cut

sub Commit {
    my $self = shift;
    return 0 unless my $escalationSet = $self->Argument;

    # Read configuration
    my $cfLvl = RT->Config->Get('EscalationField');
    my $defaultLvl = RT->Config->Get('DefaultEscalationValue');
    my %principals = RT->Config->Get('EscalationPrincipals');
    my %esets = RT->Config->Get('EscalationSets');

    # Ticket fields
    my $ticket = $self->TicketObj;
    my $starts = $ticket->Starts;
    my $due = $ticket->Due;
    my $created = $ticket->Created;
    my $lvl = $ticket->FirstCustomFieldValue($cfLvl);

    ## Set default escalation value if CF has no value
    unless (defined $lvl) {
        $lvl = $defaultLvl;

        $RT::Logger->notice("Ticket #" . $ticket->id . ': CF.' . $cfLvl . " changed (no value) -> " . $lvl);

        my $cf = RT::CustomField->new($RT::SystemUser);
        $cf->LoadByNameAndQueue(Name => $cfLvl, Queue => $ticket->Queue);
        unless ($cf->id) {
            $cf->LoadByName(Name => $cfLvl);
        }
        my ($val, $msg) = $ticket->AddCustomFieldValue(Field => $cf, Value => $lvl);
        unless ($val) {
            $RT::Logger->error("Ticket #" . $ticket->id . ': could not set escalation level: ' . $msg);
            return 0;
        }
        return 1;
    }

    my $date = new Date::Manip::Date;
    my $now = new Date::Manip::Date;
    $now->parse('now');

    unless (exists $esets{$escalationSet}) {
        $RT::Logger->error("Ticket #" . $ticket->id . ": unknown escalation set: $escalationSet");
        return 0;
    }
    my $eset = $esets{$escalationSet};
    unless ($eset->{$lvl} || $lvl == $defaultLvl) {
        $RT::Logger->error("Ticket #" . $ticket->id . ": CF." . $cfLvl . " has unknown escalation level: " . $lvl);
        return 0;
    }
    
    $date->parse($created);

    # nowDelta = now - created
    my $nowDelta = $now->calc($date, 1);

    # Create hash {lvl=>DateManip::Delta}
    my %deltas = ();
    for (keys %$eset) {
        my $x = $date->new_delta();
        my $res = $x->parse($eset->{$_}->{created}) if $eset->{$_}->{created};
        if ($res == 1 || ! defined $res) {
            $RT::Logger->error("Config: Cannot parse escalation time value '" . $eset->{$_} . "' in " . $escalationSet . '->' . $_);
            return 0;
        }
        $deltas{$_} = $x;
    }

    # Determine whether its time to change escalation level CF
    my $newLvl = undef;
    for (sort { $b <=> $a; } keys %deltas) {
        if ($deltas{$_}->cmp($nowDelta) < 0) {
            $newLvl = $_;
            last;
        }
    }
    if (defined $newLvl && $lvl ne $newLvl) {
        my ($val, $msg) = $ticket->AddCustomFieldValue(Field => $cfLvl, Value => $newLvl);
        unless ($val) {
           $RT::Logger->error('Ticket #' . $ticket->id . ': could not set escalation level: ' . $msg);
           return 0;
        }
        $RT::Logger->info("Ticket #" . $ticket->id . ': CF.' . $cfLvl . " changed " . $lvl . ' -> ' . $newLvl);

        # Set email notification parameters
        my $pcps = $principals{$newLvl};
        if ($pcps) {
            $self->SetRecipients($pcps);

            my $res = RT::Interface::Email::SendEmailUsingTemplate(
                'Template' => 'Escalation',
                'Arguments' => {
                    'Ticket' => $ticket,
                    'EscalationLevel' => $newLvl,
                    'CreatedTimeAgo' => $nowDelta->printf("%0hv:%0mv"),
                },
                'To' => join(',', @{$self->{'Emails'}}),
                'ExtraHeaders' => {'Content-Type' => "text/html; charset=\"UTF-8\""}
            );
            if ($res == 1) {
                $RT::Logger->error('Ticket #' . $ticket->id . ': error while sending message. Recipients: ' . join(',', @{$self->{'Emails'}}));
                return 0;
            }
        } else {
            $RT::Logger->warning('Ticket #' . $ticket->id . ": no principal found for escalation level " . $newLvl);
        }

    } else {
        $RT::Logger->debug("Ticket #" . $ticket->id . ": escalation level not changed");
    }
    return 1;
}

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