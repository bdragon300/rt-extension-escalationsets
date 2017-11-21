package RT::Extension::EscalationSets;

use 5.010;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT = qw/ str_to_dm  load_config /;
our $VERSION = '0.2b';

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

## MySQL date time format:
use constant DATE_FORMAT => '%Y-%m-%d %T';

use Date::Manip::Date;

=head1 NAME

C<RT::Extension::EscalationSets> - Highly configurable escalation with business hours.

=head1 DESCRIPTION

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
performed simply based on Created (B<due> is not specified, see below).
"Pausing" tickets in this case will not support.

=head1 DEPENDENCIES

=over

=item RT >= 4.2.0

=item Date::Manip >= 6.25

=back

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item C<make initdb>

Only run this the first time you install this module.

If you run this twice, you may end up with duplicate data
in your database.

=item Edit your RT_SiteConfig.pm

If you are using RT 4.2 or greater, add this line:

    Plugin('RT::Extension::EscalationSets');

For RT 3.8 and 4.0, add this line:

    Set(@Plugins, qw(RT::Extension::EscalationSets));

or add C<RT::Extension::EscalationSets> to your existing C<@Plugins> line.

=item Restart your webserver

=back

=head1 CONFIGURATION AND EXAMPLES

See README.md

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.



=head1 METHODS

=head2 str_to_dm Val, [FromTz], [ToTz], [Config]

Builds Date::Manip::Date object based on date string and config

Receives:

=over

=item Val - date string

=item FromTz - Val's timezone. If omitted use Date::Manip default

=item ToTz - convert Val to this timezone

=item Config - hashref, Date::Manip config

=back

Returns

=over

=item Date::Manip::Date object

=item undef if error

=back

=cut

sub str_to_dm 
{
    my %args = (
        Val     => undef,
        FromTz  => undef,
        ToTz    => undef,
        Config  => undef,
        @_
    );

    return (undef) 
        unless $args{'Val'};

    my $obj = new Date::Manip::Date;
    
    dm_set_default_config($obj);
    $obj->config(%{$args{'Config'}})
        if ref($args{'Config'}) eq 'HASH';
    $obj->config('setdate', "zone," . $args{'FromTz'})
        if $args{'FromTz'};
        
    $obj->parse($args{'Val'});
    
    $obj->convert($args{'ToTz'}) 
        if $args{'ToTz'};

    return $obj;
}

=head2 dm_set_default_config DMOBJ

Sets default config to Date::Manip object 

Receives:

=over

=item DMOBJ - Date::Manip object

=back

Returns nothing

=cut

sub dm_set_default_config
{
    my $dmobj = shift;
    
    $dmobj->config('WorkDay24Hr',  1);
    $dmobj->config('WorkDayBeg',  '00:00');
    $dmobj->config('WorkDayEnd',  '24:00');
    $dmobj->config('WorkWeekBeg',  1);
    $dmobj->config('WorkWeekEnd',  7);
}

=head2 load_config

Reads extension config

Receives

None

Returns

=over

=item HASHREF config

=item (undef) if error

=back

=cut

sub load_config 
{
	my %conf = (
	   EscalationField => RT->Config->Get('EscalationField'),
	   EscalationSetField => RT->Config->Get('EscalationSetField'),
	   EscalationSets => {RT->Config->Get('EscalationSets')}
	);
	return (undef) if (scalar(grep { ! $_ } values %conf));
	return (undef) if ref($conf{'EscalationSets'}) ne 'HASH';
    return \%conf;
}

=head2 get_worktime_delta

Counts ticket work time based on Due set/unset transactions

Receives

=over

=item TICKET - RT::Ticket

=item STARTDATE - Date::Manip::Date obj. Start date to count worktime

=item NOW - Date::Manip::Date obj. Usually refers to Now moment

=item DM_CONFIG - HASHREF. Date::Manip config

=back

Returns

=over

=item HASHREF config

=item (undef) if error

=back

=cut

sub get_worktime_delta
{
    my ($ticket, $startdate, $now, $dm_config) = @_;

    # Check parameters types
    return (undef)
        if (ref($startdate) ne 'Date::Manip::Date');
    return (undef)
        if (ref($now) ne 'Date::Manip::Date');
    return (undef)
        if (defined($dm_config) && ref($dm_config) ne 'HASH');

    my $startdate_str = $startdate->printf(DATE_FORMAT);

    # Search all txns where Due goes from or to unset value
    my $txns = $ticket->Transactions;
    $txns->Limit(FIELD => 'Type', VALUE => 'Set');
    $txns->Limit(FIELD => 'Field', VALUE => 'Due', ENTRYAGGREGATOR => 'AND');
    $txns->Limit(FIELD => 'NewValue', VALUE => NOT_SET, ENTRYAGGREGATOR => 'AND', SUBCLAUSE => 'val');
    $txns->Limit(FIELD => 'OldValue', VALUE => NOT_SET, ENTRYAGGREGATOR => 'OR', SUBCLAUSE => 'val');
    $txns->OrderBy(FIELD => 'id', ORDER => 'ASC');

    my $chunk_start = str_to_dm(
        Val => $startdate_str,
        FromTz => 'UTC',
        Config => $dm_config
    );
    my $work_delta = $chunk_start->new_delta();
    # $work_delta->parse('0:0:0:0:0:0:0', 'business');

    while (my $txn = $txns->Next) {
        # Skip txn before startdate
        next
            if ($txn->Created le $startdate_str);

        # If NOW in past (testing purposes)
        next
            if ($txn->Created gt $now->printf(DATE_FORMAT));

        my $txn_created = str_to_dm(Val => $txn->Created, FromTz => 'UTC', Config => $dm_config);
        if ($txn->NewValue eq NOT_SET) {
            # Add work chunk to delta
            $work_delta = $work_delta->calc($txn_created->calc($chunk_start, 1), 0);
            $chunk_start = undef;
        }
        elsif ($txn->OldValue eq NOT_SET
            && ! defined($chunk_start))
        {
            $chunk_start = str_to_dm(Val => $txn->Created, FromTz => 'UTC', Config => $dm_config);
        }
        else {
            # Skip txn
            # Due was set after startdate without pausing SLA
            # In this case chunk counts from startdate, not Due set moment
        }
    }

    # Due now still set
    if (defined($chunk_start)) {
        $work_delta = $work_delta->calc($now->calc($chunk_start, 1), 0);
    }

    return $work_delta;
}


=head2 get_dm_config_by_eset ESET, TICKET

Returns Date::Manip config for escalation set

Receives

=over

=item ESET - escalation set. If undef then use current ticket one

=item CONFIG - configuration hashref

=item TICKET - RT::Ticket object

=back

Returns

=over

=item HASHREF - config of Date::Manip

=item (undef) if not found or error

=back

=cut

sub get_dm_config_by_eset
{
    my $eset = shift // 'current';
    my $config = shift;
    my $ticket = shift;

    $eset = $ticket->FirstCustomFieldValue($config->{'EscalationSetField'})
        if $eset eq 'current';
    return $config->{'EscalationSets'}->{$eset}->{'datemanip_config'}
        if exists($config->{'EscalationSets'}->{$eset});
    return (undef);
}

=head2 RT::Ticket::get_datemanip_date FIELD, ESET

Template method. Builds Date::Manip::Date for FIELD value

Receives

=over

=item FIELD - ticket field name

=item ESET - escalation set. If undef then use current ticket one

=back

Returns

=over

=item Date::Manip::Date object

=item (undef) if error

=back

=cut

sub RT::Ticket::get_datemanip_date
{
    my $self = shift;
    my $field = shift;
    my $eset = shift;

    return (undef) 
        unless $self->_Accessible($field, 'read');
    
    my $config = load_config();
    unless ($config) {
        RT::Logger->error('[RT::Extension::EscalationSets]: Incomplete configuration, see README');
        return (undef);
    }

    my $res = str_to_dm(
        Val => $self->_Value($field),
        FromTz => 'UTC',
        Config => get_dm_config_by_eset($eset, $config, $self)
    );
    if ($res->err()) {
        RT::Logger->warning("[RT::Extension::EscalationSets]: get_datemanip_date: " . $res->err());
    }
    return $res;
}

=head2 RT::Ticket::get_datemanip_delta FIELD, ESET, BASE

Template method. Builds Date::Manip::Delta between FIELD value and BASE

Receives

=over

=item FIELD - ticket field name

=item ESET - escalation set. If undef then use current ticket one

=item BASE - Date::Manip::Date obj. If undef then use NOW (in UTC)

=back

Returns

=over

=item Date::Manip::Delta object

=item (undef) if error

=back

=cut

sub RT::Ticket::get_datemanip_delta
{
    my $self = shift;
    my $field = shift;
    my $eset = shift;
    my $base = shift;
    
    return (undef)
        unless $self->_Accessible($field, 'read');
    return (undef)
        unless defined($self->_Value($field));

    my $config = load_config();
    unless ($config) {
        RT::Logger->error('[RT::Extension::EscalationSets]: Incomplete configuration, see README');
        return (undef);
    }

    unless ($base) {
        $base = str_to_dm(
            Val => "now", 
            ToTz => "UTC", 
            Config => get_dm_config_by_eset($eset, $config, $self)
        );
    }

    my $f = str_to_dm(
        Val => $self->_Value($field),
        FromTz => 'UTC', 
        Config => get_dm_config_by_eset($eset, $config, $self)
    );
    return (undef)
        unless $f; 

    my $res = $f->calc($base, 1, 'business');
    if ($res->err()) {
        RT::Logger->warning("[RT::Extension::EscalationSets]: get_datemanip_delta: " . $res->err());
    }
    return $res;
}

=head2 RT::Ticket::get_datemanip_worktime

Template method. Returns ticket worktime Delta object

Note: if Due was changed manually sometime then result will not be correct
because it calculates based on current escalation set and contains difference
between whole ticket time and remaining time

Receives:

=over

=item NOW - Optional, Date::Manip::Date obj. If undef the NOW moment will be used

=back

Returns

=over

=item Date::Manip::Delta object

=back

=cut

sub RT::Ticket::get_datemanip_worktime
{
    my $self = shift;
    my $now = shift;
    
    my $conf = load_config();
    my $eset = $self->FirstCustomFieldValue($conf->{'EscalationSetField'});
    
    my $due_date_attr = (keys %{$conf->{'EscalationSets'}->{$eset}->{'due'}})[0]
        if ref($conf->{'EscalationSets'}->{$eset}->{'due'}) eq 'HASH';

    # Use this ticket attribute when 'due' was not specified
    unless ($due_date_attr) {
        $due_date_attr = 'Started';
    }

    return (undef)
        unless $self->_Accessible($due_date_attr, 'read');
    return (undef)
        unless $self->_Value($due_date_attr);
    return (undef) 
        if $self->_Value($due_date_attr) eq NOT_SET;

    my $startdate = str_to_dm(Val => $self->_Value($due_date_attr), FromTz => 'UTC');

    $now = str_to_dm(Val => 'now', ToTz => 'UTC')
        unless $now;

    my $dm_config = $conf->{'EscalationSets'}->{$eset}->{'datemanip_config'};

    my $res = get_worktime_delta($self, $startdate, $now, $dm_config);
    if ($res && $res->err()) {
        RT::Logger->warning(
            "[RT::Extension::EscalationSets]: get_datemanip_worktime: Date::Manip error: " 
            . $res->err()
        );
    }
    elsif ( ! defined($res) ) {
        RT::Logger->error(
            "[RT::Extension::EscalationSets]: get_datemanip_worktime: unknown error. "
            . "Check that NOW parameter is Date::Manip::Date object and "
            . "'datemanip_config' in configuration for ticket's escalation set (if any)"
        );
    }

    return $res;
}

1;
