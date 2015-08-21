package RT::Action::IncreaseDue;

use 5.010;
use strict;
use warnings;

use base qw(RT::Extension::EscalationSets RT::Action);
use Date::Manip::Date;

our $VERSION = '0.1';


=head1 NAME

C<RT::Action::IncreaseDue> - Increase Due date of ticket when Status has changed
and Starts was set


=head1 DESCRIPTION

The action performs when we need to move Due date to the future based on Starts.
Foe example, when ticket has stalled and Starts has set we move Due to keep SLA.

=head1 AUTHOR

Igor Derkach, E<lt>id@miran.ruE<gt>


=head1 SUPPORT AND DOCUMENTATION

You can find documentation for this module with the C<perldoc> command.

    perldoc RT::Extension::IncreaseDue


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
    RT::Extension::IncreaseDue


=head2 Prepare

Before the action may be L<commited|/"Commit"> we need be ensured
that Starts has set.


=cut

sub Prepare {
    my $self = shift;
    
    my $ticket = $self->TicketObj;

    ## UNIX timestamp 0:
    my $notSet = '1970-01-01 00:00:00';

    #Check whether Due was set
    if ($ticket->Due eq $notSet) {
        $RT::Logger->debug("Ticket #" . $ticket->id . ": cannot increase Due because Due is unset");
        return 0;
    }

    return 1;
}


=head2 Commit

After preparation this method commits the action.


=cut

sub Commit {
    my $self = shift;

    # Read config
    # my @pausedStatuses = RT->Config->Get('EscalationActions') || qw(stalled);

    # Ticket fields
    my $ticket = $self->TicketObj;
    my $due = $ticket->Due;
    my $status = $ticket->Status;
    my $txn = $self->TransactionObj;

    return 0 unless $txn;

    # Read configuration
    my $timezone = RT->Config->Get('Timezone');

    ## MySQL date time format:
    my $format = '%Y-%m-%d %T';

    my $nowObj = new Date::Manip::Date;
    $nowObj->parse("now");

    my $old = $txn->OldValue;
    my $new = $txn->NewValue;
    my $newDueObj = undef;

    if ($txn->Type eq "Set" && $txn->Field eq "Starts") {
        my $dueObj = $self->newDateObj($due, $timezone);
        my $oldObj = $self->newDateObj($old, $timezone);
        my $newObj = $self->newDateObj($new, $timezone);
        my $newDueDeltaObj = undef;

        if ($self->cmpDates($nowObj, $oldObj) < 0 && $self->cmpDates($nowObj, $newObj) < 0) { 
            $newDueDeltaObj = $newObj->calc($oldObj, 1); # delta=new-old
            $newDueObj = $dueObj->calc($newDueDeltaObj, 0);  # due+=delta
        }
        elsif ($self->cmpDates($nowObj, $newObj) < 0) {
            $newDueDeltaObj = $newObj->calc($nowObj, 1); # delta=new-now
            $newDueObj = $newDueObj->calc($newDueDeltaObj, 0); # due+=delta
        }
        elsif ($self->cmpDates($nowObj, $oldObj) < 0) {
            $newDueDeltaObj = $oldObj->calc($nowObj, 1); # delta=old-now
            $newDueObj = $newDueObj->calc($newDueDeltaObj, 1); # due-=delta
        } else {
            return 0;
        }
        $newDueObj = $dueObj->new_date if ($self->cmpDates($oldObj, $dueObj) > 0 || $self->cmpDates($nowObj, $dueObj) > 0);

        $newDueObj->convert("UTC");
        my $newDue = $newDueObj->printf($format);
        
        if ($self->cmpDates($newDueObj, $dueObj)) {
            my ($res, $msg) = $ticket->SetDue($newDue) ;
            unless ($res) {
                $RT::Logger->error("Ticket #" . $ticket->id . ": unable to set Due to " . $newDue . ": " . $msg);
                return 0;
            }
        } else {
            $RT::Logger->warning("Ticket #" . $ticket->id . ": Due in past or Starts is later than Due" );
        }
    }
    

    return 1;
}

1;